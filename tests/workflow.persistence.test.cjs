// Real persistence/retrieval check for the connected BHW -> CHO -> Doctor
// workflow, run against the actual Firestore Security Rules and a live
// (emulated) Firestore instance -- not mocks, and not just confirming the
// application code path exists.
//
// Scope and honesty note: this exercises the DATA LAYER of the workflow
// (the exact Firestore documents/fields the app's own service code writes
// and reads, verified in health_ai_classifier.dart's sibling app files
// and cho_referral_management.dart/referrals.dart) through the real
// security rules. It does not drive the Flutter UI itself -- no browser
// or device automation tool is available in this environment. Where the
// report says "verified," it means these Firestore operations actually
// executed and were actually rejected/accepted by the real rules; it does
// not claim the on-screen widgets were clicked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {serverTimestamp} = require('firebase/firestore');
const {
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const projectId = 'demo-capstone-workflow';
let testEnv;

const activeProfile = (uid, email, overrides = {}) => ({
  uid,
  email,
  emailLower: email.toLowerCase(),
  role: 'BHW',
  approvalStatus: 'approved',
  accountStatus: 'active',
  barangay: 'Barangay 10',
  barangayCode: 'barangay_10',
  accessScope: 'barangay',
  ...overrides,
});

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '..', 'firestore.rules'),
        'utf8',
      ),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

async function seed(pathName, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(pathName).set(data);
  });
}

describe('connected workflow: real Firestore persistence and retrieval', () => {
  it('BHW creates a referral -> CHO reads and assigns a doctor -> doctor '
    + 'reads the assigned referral and records a consultation -> doctor '
    + 'adds a doctor note -> BHW reads their own patient history, all '
    + 'through the real security rules against a live emulator', async () => {
    // --- Seed the three role profiles the way the app's own signup flow
    // would produce them. ---
    await seed('users/bhw-1', activeProfile('bhw-1', 'bhw@example.test'));
    await seed(
      'users/cho-1',
      activeProfile('cho-1', 'cho@example.test', {
        role: 'CHO',
        accessScope: 'citywide',
        barangay: '',
        barangayCode: '',
      }),
    );
    await seed(
      'users/doctor-1',
      activeProfile('doctor-1', 'doctor-1@example.test', {
        role: 'DOCTOR',
        accessScope: 'citywide',
        barangay: '',
        barangayCode: '',
      }),
    );

    // --- BHW: create a patient record and a new check-up record (the
    // "Patient -> Previous Check-Up -> New Check-Up" steps). ---
    const bhwDb = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore();
    await assertSucceeds(
      bhwDb.doc('patient_records/patient-workflow-1').set({
        name: 'Workflow Test Patient',
        barangay: 'Barangay 10',
        barangayCode: 'barangay_10',
        createdByUid: 'bhw-1',
      }),
    );

    // --- BHW: create a referral (the "AI Guidance -> Save -> Referral"
    // steps -- the referral document itself is what the app persists
    // after AI guidance is shown; the guidance text is not separately
    // security-rule-gated). ---
    await assertSucceeds(
      bhwDb.doc('referrals/workflow-referral-1').set({
        patientId: 'patient-workflow-1',
        patientName: 'Workflow Test Patient',
        referralReason: 'Suspected communicable disease, needs assessment',
        priority: 'routine',
        status: 'pending_review',
        submissionStatus: 'submitted',
        barangay: 'Barangay 10',
        barangayCode: 'barangay_10',
        createdByUid: 'bhw-1',
        createdByRole: 'bhw',
        createdAt: new Date(),
        updatedAt: new Date(),
      }),
    );

    // Retrieval check: the referral the BHW just wrote reads back with
    // the same field values (real round-trip, not an existence check).
    const bhwReadBack = await bhwDb.doc('referrals/workflow-referral-1').get();
    assert.equal(bhwReadBack.exists, true);
    assert.equal(bhwReadBack.data().status, 'pending_review');
    assert.equal(bhwReadBack.data().patientName, 'Workflow Test Patient');

    // --- CHO: reads the pending referral (citywide scope, not the
    // creating BHW's own barangay-only view) and assigns a doctor (the
    // "Review Referral -> Doctor Availability -> Assign Doctor" steps).
    // ---
    const choDb = testEnv
      .authenticatedContext('cho-1', {email: 'cho@example.test'})
      .firestore();
    const choRead = await choDb.doc('referrals/workflow-referral-1').get();
    assert.equal(choRead.exists, true);
    assert.equal(choRead.data().status, 'pending_review');

    await assertSucceeds(
      choDb.doc('hospitals/hospital-1').set({
        name: 'Workflow Test District Hospital',
        active: true,
      }),
    );
    const choHospitalRead = await bhwDb.doc('hospitals/hospital-1').get();
    assert.equal(choHospitalRead.exists, true);

    await assertSucceeds(
      choDb.doc('referrals/workflow-referral-1').update({
        status: 'approved',
        assignedDoctorUid: 'doctor-1',
        assignedHospital: 'Workflow Test District Hospital',
        updatedAt: new Date(),
      }),
    );

    // --- Doctor: reads only their own assigned referral (scope check,
    // real retrieval) -- the "Assigned Referral" step. ---
    const doctorDb = testEnv
      .authenticatedContext('doctor-1', {email: 'doctor-1@example.test'})
      .firestore();
    const doctorRead = await doctorDb.doc('referrals/workflow-referral-1').get();
    assert.equal(doctorRead.exists, true);
    assert.equal(doctorRead.data().assignedDoctorUid, 'doctor-1');
    assert.equal(doctorRead.data().status, 'approved');

    // --- Doctor: reads the patient's prior check-up/patient record for
    // history (the "Patient History" step) -- doctors have citywide
    // read access to patient_records via canReadBarangayScopedRecord's
    // CHO/doctor... actually patient_records match uses
    // canReadScopedRecord (CHO or same-barangay); a doctor's own read
    // path is the assigned referral's embedded patient info, which was
    // already verified above. This additionally confirms the raw
    // patient_records collection remains reachable to CHO for the
    // continuity-of-care cross-check.
    const choPatientRead = await choDb.doc('patient_records/patient-workflow-1').get();
    assert.equal(choPatientRead.exists, true);
    assert.equal(choPatientRead.data().name, 'Workflow Test Patient');

    // --- Doctor: records the consultation outcome on the referral (the
    // exact field set the app's real referrals.dart consultation dialog
    // writes: doctorDiagnosis/doctorTreatment/doctorMedication/
    // doctorNotes/status/doctorUpdatedAt/updatedAt -- this is the field
    // allowlist added to firestore.rules this session after the emulator
    // test found doctors could otherwise write unrelated fields).
    //
    // The status moves to 'consulted' first, not straight to 'completed':
    // isAllowedDoctorReferralTransition() (and the matching
    // referrals.dart dropdown, which only offers a status one step ahead
    // of the current one) requires a documented consultation before a
    // case can be marked complete, so this mirrors the two real, separate
    // dialog saves a doctor performs rather than one combined write. ---
    await assertSucceeds(
      doctorDb.doc('referrals/workflow-referral-1').update({
        doctorDiagnosis: 'Confirmed communicable illness, stable',
        doctorTreatment: 'Supportive care plan documented by physician',
        doctorMedication: 'Prescribed by physician (out of AI scope)',
        doctorNotes: 'Follow-up in one week',
        status: 'consulted',
        assignedDoctorUid: 'doctor-1',
        doctorUpdatedAt: new Date(),
        updatedAt: new Date(),
      }),
    );

    // --- Doctor: a second, later save closes out the case (the "mark
    // completed" follow-up action, only reachable once consulted). ---
    await assertSucceeds(
      doctorDb.doc('referrals/workflow-referral-1').update({
        status: 'completed',
        assignedDoctorUid: 'doctor-1',
        doctorUpdatedAt: new Date(),
        updatedAt: new Date(),
      }),
    );

    // --- Doctor: adds an append-only doctor note tied to this patient
    // (the "Add Doctor Note" step). ---
    await assertSucceeds(
      doctorDb.doc('doctor_notes/workflow-note-1').set({
        authorUid: 'doctor-1',
        patientId: 'patient-workflow-1',
        note: 'Patient counseled on hydration and follow-up schedule.',
        barangay: 'Barangay 10',
        barangayCode: 'barangay_10',
        // Required exactly: canCreateDoctorNote() checks
        // data.createdAt == request.time, so this must be the real
        // server-timestamp sentinel, not a client-supplied Date.
        createdAt: serverTimestamp(),
      }),
    );

    // Retrieval + continuity-of-care check: the BHW who originally
    // created the case can read the doctor's note back (same barangay),
    // and the referral now shows the completed status and doctor's
    // documented outcome -- this is the "Doctor Note Continuity" and
    // "Referral Accuracy" verification, executed as real reads against
    // the emulator, not assumed from the code path.
    const bhwNoteRead = await bhwDb.doc('doctor_notes/workflow-note-1').get();
    assert.equal(bhwNoteRead.exists, true);
    assert.equal(
      bhwNoteRead.data().note,
      'Patient counseled on hydration and follow-up schedule.',
    );

    const finalReferral = await bhwDb.doc('referrals/workflow-referral-1').get();
    assert.equal(finalReferral.data().status, 'completed');
    assert.equal(
      finalReferral.data().doctorDiagnosis,
      'Confirmed communicable illness, stable',
    );

    // --- CHO: report/filter check -- a citywide query for completed
    // referrals returns this record (the "Apply Report Filters" step's
    // underlying data access pattern). ---
    const completedQuery = await choDb
      .collection('referrals')
      .where('status', '==', 'completed')
      .get();
    assert.equal(
      completedQuery.docs.some((d) => d.id === 'workflow-referral-1'),
      true,
    );
  });
});
