const assert = require('node:assert/strict');

const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'demo-doctor-portal';
if (!admin.apps.length) admin.initializeApp({projectId});
const db = new admin.firestore.Firestore({projectId, databaseId: 'capstone-c98f9'});

const adminUid = 'doctor-account-test-admin';
const doctorEmail = 'doctor-account-test@example.test';
const doctorName = 'Doctor Account Test';

async function call(name, idToken, data = {}) {
  const headers = {'Content-Type': 'application/json'};
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(
      `http://127.0.0.1:5001/${projectId}/us-central1/${name}`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify({data}),
      },
  );
  return {response, body: await response.json()};
}

async function signIn(email, password) {
  const response = await fetch(
      'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key',
      {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({email, password, returnSecureToken: true}),
      },
  );
  const body = await response.json();
  assert.ok(body.idToken, JSON.stringify(body));
  return body.idToken;
}

async function main() {
  let adminAuth;
  let doctorAuth;
  const adminEmail = 'doctor-account-test-admin@example.test';
  const adminPassword = 'A-strong-test-password-123!';
  try {
    adminAuth = await admin.auth().createUser({
      uid: adminUid,
      email: adminEmail,
      password: adminPassword,
      displayName: 'Doctor Account Test Admin',
    });
    await admin.auth().setCustomUserClaims(adminUid, {
      role: 'cho_admin',
      approvalStatus: 'approved',
      accountStatus: 'active',
    });
    await db.collection('users').doc(adminUid).set({
      uid: adminUid,
      email: adminEmail,
      emailLower: adminEmail,
      fullName: 'Doctor Account Test Admin',
      role: 'CHO_ADMIN',
      approvalStatus: 'approved',
      accountStatus: 'active',
      isApproved: true,
    });

    const token = await signIn(adminEmail, adminPassword);
    const result = await call('createChoAccount', token, {
      fullName: doctorName,
      email: doctorEmail,
      role: 'DOCTOR',
      specialization: 'General Medicine',
      availability: 'available',
      accountStatus: 'active',
    });
    assert.equal(result.response.status, 200, JSON.stringify(result.body));
    assert.equal(result.body.result.success, true);
    assert.equal(result.body.result.role, 'DOCTOR');
    assert.equal(result.body.result.email, doctorEmail);
    assert.equal(result.body.result.activationEmailSent, false);
    assert.ok(result.body.result.activationEmailReason);

    doctorAuth = await admin.auth().getUserByEmail(doctorEmail);
    assert.equal(doctorAuth.disabled, false);
    const doctorProfile = (await db.collection('users').doc(doctorAuth.uid).get()).data();
    assert.equal(doctorProfile.role, 'DOCTOR');
    assert.equal(doctorProfile.email, doctorEmail);
    assert.equal(doctorProfile.approvalStatus, 'approved');
    assert.equal(doctorProfile.accountStatus, 'active');
    assert.deepEqual(doctorProfile.permissions, [
      'dashboard.view',
      'patients.view',
      'checkups.view',
      'prenatal.view',
      'immunization.view',
      'surveillance.view',
      'referrals.view',
      'referrals.assigned.view',
      'notifications.view',
      'profile.view',
    ]);
    console.log('Doctor account callable test passed.');
  } finally {
    if (doctorAuth) {
      await db.collection('users').doc(doctorAuth.uid).delete().catch(() => {});
      await admin.auth().deleteUser(doctorAuth.uid).catch(() => {});
    }
    await db.collection('registration_email_locks').doc(doctorEmail).delete().catch(() => {});
    await db.collection('registration_username_locks').doc(doctorName.toLowerCase()).delete().catch(() => {});
    await db.collection('users').doc(adminUid).delete().catch(() => {});
    if (adminAuth) await admin.auth().deleteUser(adminAuth.uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
