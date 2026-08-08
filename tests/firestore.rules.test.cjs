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
