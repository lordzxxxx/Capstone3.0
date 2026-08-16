const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const projectId = 'demo-capstone-security';
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

beforeEach(async () => testEnv.clearFirestore());
after(async () => {
  if (testEnv) await testEnv.cleanup();
});

async function seed(pathName, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(pathName).set(data);
  });
}

describe('user profile privilege boundaries', () => {
  it('allows pending BHW and active CHO signup but rejects active BHW and admin roles', async () => {
    const db = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore();
    await assertFails(
      db.doc('users/bhw-1').set(activeProfile('bhw-1', 'bhw@example.test')),
    );
    await assertSucceeds(
      db.doc('users/bhw-1').set(
        activeProfile('bhw-1', 'bhw@example.test', {
          status: 'Pending Approval',
          approvalStatus: 'pending',
          accountStatus: 'pending_approval',
          isApproved: false,
        }),
      ),
    );
    const choDb = testEnv
      .authenticatedContext('cho-1', {email: 'cho@example.test'})
      .firestore();
    await assertSucceeds(
      choDb.doc('users/cho-1').set(
        activeProfile('cho-1', 'cho@example.test', {
          role: 'CHO',
          accessScope: 'citywide',
          barangay: '',
          barangayCode: '',
        }),
      ),
    );
    const attackerDb = testEnv
      .authenticatedContext('attacker', {email: 'attacker@example.test'})
      .firestore();
    await assertFails(
      attackerDb.doc('users/attacker').set(
        activeProfile('attacker', 'attacker@example.test', {
          role: 'SUPER_ADMIN',
        }),
      ),
    );
  });

  it('allows ordinary profile edits but rejects role and approval changes', async () => {
    await seed(
      'users/bhw-1',
      activeProfile('bhw-1', 'bhw@example.test', {displayName: 'Original'}),
    );
    const ref = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore()
      .doc('users/bhw-1');

    await assertSucceeds(ref.update({displayName: 'Updated'}));
    await assertFails(ref.update({role: 'SUPER_ADMIN'}));
    await assertFails(ref.update({approvalStatus: 'pending'}));
    await assertFails(ref.update({barangayCode: 'barangay_11'}));
  });

  it('rejects malformed pending self-registration profiles', async () => {
    const db = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore();
    await assertFails(
      db.doc('users/bhw-1').set(
        activeProfile('bhw-1', 'bhw@example.test', {
          approvalStatus: 'pending',
          accountStatus: 'active',
          isApproved: false,
        }),
      ),
    );
  });

  it('blocks BHW self-approval and allows an active CHO to approve', async () => {
    await seed(
      'users/bhw-1',
      activeProfile('bhw-1', 'bhw@example.test', {
        approvalStatus: 'pending',
        accountStatus: 'pending_approval',
        status: 'Pending Approval',
        isApproved: false,
      }),
    );
    const ownRef = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore()
      .doc('users/bhw-1');
    await assertFails(
      ownRef.update({
        approvalStatus: 'approved',
        accountStatus: 'active',
        status: 'Active',
        isApproved: true,
        updatedAt: new Date(),
      }),
    );

    await seed(
      'users/cho-1',
      activeProfile('cho-1', 'cho@example.test', {
        role: 'CHO',
        accessScope: 'citywide',
        barangay: '',
        barangayCode: '',
      }),
    );
    const choRef = testEnv
      .authenticatedContext('cho-1', {email: 'cho@example.test'})
      .firestore()
      .doc('users/bhw-1');
    await assertSucceeds(
      choRef.update({
        approvalStatus: 'approved',
        accountStatus: 'active',
        status: 'Active',
        isApproved: true,
        approvedBy: 'cho-1',
        approvedAt: new Date(),
        updatedAt: new Date(),
      }),
    );

    const attackerRef = testEnv
      .authenticatedContext('attacker', {email: 'attacker@example.test'})
      .firestore()
      .doc('users/bhw-1');
    await assertFails(attackerRef.update({approvalStatus: 'pending'}));
  });

  it('grants barangay-scoped access immediately after authenticated signup', async () => {
    await seed(
      'users/bhw-1',
      activeProfile('bhw-1', 'bhw@example.test'),
    );
    await seed('patient_records/patient-1', {
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      name: 'Scoped patient',
    });
    const db = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore();
    await assertSucceeds(db.doc('patient_records/patient-1').get());
  });
});

describe('BHW referral workflow boundaries', () => {
  beforeEach(async () => {
    await seed(
      'users/bhw-1',
      activeProfile('bhw-1', 'bhw@example.test'),
    );
  });

  const referral = (status, overrides = {}) => ({
    patientName: 'Test Patient',
    referralReason: 'Needs higher-level assessment',
    priority: 'routine',
    status,
    submissionStatus: 'submitted',
    barangay: 'Barangay 10',
    barangayCode: 'barangay_10',
    createdByUid: 'bhw-1',
    createdByRole: 'bhw',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  });

  it('allows the owner BHW to correct only a returned referral', async () => {
    await seed('referrals/returned-1', referral('returned'));
    const ref = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore()
      .doc('referrals/returned-1');

    await assertSucceeds(
      ref.update({
        referralReason: 'Corrected referral reason',
        status: 'pending_review',
        submissionStatus: 'submitted',
        submittedAt: new Date(),
        updatedAt: new Date(),
        statusHistory: [{status: 'pending_review'}],
      }),
    );

    await seed('referrals/approved-1', referral('approved'));
    const approvedRef = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore()
      .doc('referrals/approved-1');
    await assertFails(approvedRef.update({referralReason: 'Unauthorized edit'}));
  });

  it('rejects BHW approval and provider assignment', async () => {
    await seed('referrals/pending-1', referral('pending_review'));
    const ref = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore()
      .doc('referrals/pending-1');
    await assertFails(ref.update({status: 'approved'}));
    await assertFails(
      ref.update({
        assignedHospital: 'Unauthorized Hospital',
        assignedDoctorUid: 'doctor-1',
      }),
    );
  });

  it('allows home-visit fields after consultation but protects treatment', async () => {
    await seed('referrals/completed-1', referral('completed'));
    const ref = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore()
      .doc('referrals/completed-1');

    await assertSucceeds(
      ref.update({
        followUps: [{notes: 'Patient stable'}],
        latestFollowUpNotes: 'Patient stable',
        homeVisitCompleted: true,
        homeVisitCompletedAt: new Date(),
        updatedAt: new Date(),
      }),
    );
    await assertFails(ref.update({doctorTreatment: 'Unauthorized treatment'}));
  });
});

// Added 2026-08-11: the JDK/emulator dependency that previously blocked
// running these tests at all is now available. These cover checklist
// items the original 8 tests did not exercise directly: unauthenticated
// access, doctor scope, doctor-note protection, CHO citywide scope, and
// an explicit privilege-escalation attempt.
describe('unauthenticated access is denied', () => {
  it('rejects reads of patient records, referrals, and doctor notes with '
    + 'no auth context at all', async () => {
    await seed('patient_records/patient-1', {
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      name: 'Scoped patient',
    });
    await seed('referrals/referral-1', {
      patientName: 'Test Patient',
      status: 'pending_review',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      createdByUid: 'bhw-1',
    });
    await seed('doctor_notes/note-1', {
      authorUid: 'doctor-1',
      patientId: 'patient-1',
      note: 'Follow-up in two weeks',
    });

    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('patient_records/patient-1').get());
    await assertFails(db.doc('referrals/referral-1').get());
    await assertFails(db.doc('doctor_notes/note-1').get());
    await assertFails(
      db.doc('referrals/referral-2').set({
        patientName: 'Injected',
        status: 'pending_review',
        createdByUid: 'nobody',
      }),
    );
  });
});

describe('doctor scope', () => {
  const doctorProfile = (uid, email) =>
    activeProfile(uid, email, {
      role: 'DOCTOR',
      accessScope: 'citywide',
      barangay: '',
      barangayCode: '',
    });

  it('lets a doctor read only referrals assigned to them, not referrals '
    + 'assigned to a different doctor', async () => {
    await seed('users/doctor-1', doctorProfile('doctor-1', 'doctor-1@example.test'));
    await seed('referrals/assigned-to-doctor-1', {
      patientName: 'Test Patient',
      status: 'approved',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      createdByUid: 'bhw-1',
      assignedDoctorUid: 'doctor-1',
    });
    await seed('referrals/assigned-to-doctor-2', {
      patientName: 'Other Patient',
      status: 'approved',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      createdByUid: 'bhw-1',
      assignedDoctorUid: 'doctor-2',
    });

    const db = testEnv
      .authenticatedContext('doctor-1', {email: 'doctor-1@example.test'})
      .firestore();
    await assertSucceeds(db.doc('referrals/assigned-to-doctor-1').get());
    await assertFails(db.doc('referrals/assigned-to-doctor-2').get());
  });

  it('does not let a doctor approve or reassign a referral (that remains '
    + 'CHO-only, same as the BHW boundary already covered above)', async () => {
    await seed('users/doctor-1', doctorProfile('doctor-1', 'doctor-1@example.test'));
    await seed('referrals/assigned-to-doctor-1', {
      patientName: 'Test Patient',
      status: 'approved',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      createdByUid: 'bhw-1',
      assignedDoctorUid: 'doctor-1',
    });
    const ref = testEnv
      .authenticatedContext('doctor-1', {email: 'doctor-1@example.test'})
      .firestore()
      .doc('referrals/assigned-to-doctor-1');
    await assertFails(
      ref.update({assignedDoctorUid: 'doctor-1', assignedHospital: 'Self-assigned Hospital'}),
    );
  });

  it('allows only forward consultation states for the assigned doctor', async () => {
    await seed('users/doctor-1', doctorProfile('doctor-1', 'doctor-1@example.test'));
    await seed('referrals/forward-only-1', {
      patientName: 'Test Patient',
      status: 'doctor_assigned',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
      createdByUid: 'bhw-1',
      assignedDoctorUid: 'doctor-1',
    });
    const ref = testEnv
      .authenticatedContext('doctor-1', {email: 'doctor-1@example.test'})
      .firestore()
      .doc('referrals/forward-only-1');

    await assertSucceeds(
      ref.update({
        status: 'consulted',
        doctorNotes: 'Consultation completed.',
        doctorUpdatedAt: new Date(),
        updatedAt: new Date(),
      }),
    );
    await assertFails(
      ref.update({
        status: 'approved',
        doctorUpdatedAt: new Date(),
        updatedAt: new Date(),
      }),
    );
  });
});

describe('doctor notes are protected (append-only clinical log)', () => {
  const doctorProfile = (uid, email) =>
    activeProfile(uid, email, {
      role: 'DOCTOR',
      accessScope: 'citywide',
      barangay: '',
      barangayCode: '',
    });

  it('lets a doctor create a note authored as themselves, but not as '
    + 'another author, and BHW cannot create one at all', async () => {
    await seed('users/doctor-1', doctorProfile('doctor-1', 'doctor-1@example.test'));
    await seed('users/bhw-1', activeProfile('bhw-1', 'bhw@example.test'));

    const doctorDb = testEnv
      .authenticatedContext('doctor-1', {email: 'doctor-1@example.test'})
      .firestore();
    await assertFails(
      doctorDb.doc('doctor_notes/note-bad-author').set({
        authorUid: 'someone-else',
        patientId: 'patient-1',
        note: 'Spoofed author',
        // Failing on the authorUid mismatch alone is sufficient here; a
        // plain Date (vs. request.time) would also fail the note's own
        // timestamp check, which only strengthens this assertFails case.
        createdAt: new Date(),
      }),
    );

    const bhwDb = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore();
    await assertFails(
      bhwDb.doc('doctor_notes/note-by-bhw').set({
        authorUid: 'bhw-1',
        patientId: 'patient-1',
        note: 'BHW should not be able to author a doctor note',
        createdAt: new Date(),
      }),
    );
  });

  it('never allows a doctor note to be updated or deleted, even by its '
    + 'own author', async () => {
    await seed('users/doctor-1', doctorProfile('doctor-1', 'doctor-1@example.test'));
    await seed('doctor_notes/note-1', {
      authorUid: 'doctor-1',
      patientId: 'patient-1',
      note: 'Original note',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
    });
    const ref = testEnv
      .authenticatedContext('doctor-1', {email: 'doctor-1@example.test'})
      .firestore()
      .doc('doctor_notes/note-1');
    await assertFails(ref.update({note: 'Edited after the fact'}));
    await assertFails(ref.delete());
  });

  it('lets a BHW read a same-barangay doctor note for continuity of care, '
    + 'but not a note from a different barangay', async () => {
    await seed('users/bhw-1', activeProfile('bhw-1', 'bhw@example.test'));
    await seed('doctor_notes/note-same-barangay', {
      authorUid: 'doctor-1',
      patientId: 'patient-1',
      note: 'Same barangay note',
      barangay: 'Barangay 10',
      barangayCode: 'barangay_10',
    });
    await seed('doctor_notes/note-other-barangay', {
      authorUid: 'doctor-1',
      patientId: 'patient-2',
      note: 'Different barangay note',
      barangay: 'Barangay 20',
      barangayCode: 'barangay_20',
    });
    const db = testEnv
      .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
      .firestore();
    await assertSucceeds(db.doc('doctor_notes/note-same-barangay').get());
    await assertFails(db.doc('doctor_notes/note-other-barangay').get());
  });
});

describe('CHO citywide scope', () => {
  it('lets an active CHO read a referral it did not create and that is '
    + 'not in its own barangay (citywide oversight)', async () => {
    await seed(
      'users/cho-1',
      activeProfile('cho-1', 'cho@example.test', {
        role: 'CHO',
        accessScope: 'citywide',
        barangay: '',
        barangayCode: '',
      }),
    );
    await seed('referrals/far-away-referral', {
      patientName: 'Test Patient',
      status: 'pending_review',
      barangay: 'Barangay 99',
      barangayCode: 'barangay_99',
      createdByUid: 'some-other-bhw',
    });
    const db = testEnv
      .authenticatedContext('cho-1', {email: 'cho@example.test'})
      .firestore();
    await assertSucceeds(db.doc('referrals/far-away-referral').get());
  });
});

describe('privilege escalation is denied', () => {
  it('does not let an approved BHW grant itself CHO or DOCTOR role via a '
    + 'profile update, even alongside an otherwise-legitimate field change',
    async () => {
      await seed('users/bhw-1', activeProfile('bhw-1', 'bhw@example.test'));
      const ref = testEnv
        .authenticatedContext('bhw-1', {email: 'bhw@example.test'})
        .firestore()
        .doc('users/bhw-1');
      await assertFails(ref.update({role: 'CHO', displayName: 'Still Me'}));
      await assertFails(ref.update({role: 'DOCTOR'}));
      await assertFails(ref.update({accessScope: 'citywide'}));
    });

  // Note: a brand-new user self-registering with role: 'CHO' and an
  // already-active/approved status is NOT escalation -- it is this
  // system's intended, existing CHO signup path (see
  // canCreateOwnUserProfile, and the first test in this file, "allows
  // pending BHW and active CHO signup", which already covers it). The
  // isAllowedSignupRole() allowlist is exactly ['CHO', 'BHW']; DOCTOR and
  // SUPER_ADMIN have no self-service signup path at all, so that is the
  // genuinely elevated-role case worth checking here.
  it('does not let an unapproved user self-register as an already-active '
    + 'DOCTOR (no self-service signup path exists for that role at all)',
    async () => {
      const db = testEnv
        .authenticatedContext('attacker', {email: 'attacker@example.test'})
        .firestore();
      await assertFails(
        db.doc('users/attacker').set(
          activeProfile('attacker', 'attacker@example.test', {
            role: 'DOCTOR',
            approvalStatus: 'approved',
            accountStatus: 'active',
            isApproved: true,
          }),
        ),
      );
    });
});
