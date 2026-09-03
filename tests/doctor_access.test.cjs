const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const admin = require('../functions/node_modules/firebase-admin');
const {
  createDoctorSetupLink,
  DOCTOR_SETUP_LINK_TTL_MS,
} = require('../functions/doctor_access');

const projectId = process.env.GCLOUD_PROJECT || 'demo-doctor-access';
if (!admin.apps.length) admin.initializeApp({projectId});
const db = new admin.firestore.Firestore({
  projectId,
  databaseId: 'capstone-c98f9',
});

const doctorUid = 'doctor-access-lifecycle-test';
const doctorEmail = 'doctor-access-lifecycle@example.test';

function hash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

async function call(name, data = {}) {
  const response = await fetch(
      `http://127.0.0.1:5001/${projectId}/us-central1/${name}`,
      {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
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
  return {response, body: await response.json()};
}

function tokenFromLink(link) {
  return new URL(link.url).searchParams.get('token');
}

async function main() {
  let authUser;
  try {
    authUser = await admin.auth().createUser({
      uid: doctorUid,
      email: doctorEmail,
      password: 'Initial-Doctor-Password-123!',
      displayName: 'Lifecycle Test Doctor',
    });
    await db.collection('users').doc(doctorUid).set({
      uid: doctorUid,
      email: doctorEmail,
      emailLower: doctorEmail,
      fullName: 'Lifecycle Test Doctor',
      role: 'DOCTOR',
      approvalStatus: 'approved',
      accountStatus: 'active',
      isApproved: true,
    });

    assert.equal(DOCTOR_SETUP_LINK_TTL_MS, 5 * 60 * 1000);
    const firstLink = await createDoctorSetupLink({
      uid: doctorUid,
      email: doctorEmail,
      source: 'test-first',
    });
    assert.match(firstLink.url, /\/auth\/doctor-setup\?/);
    assert.equal(firstLink.expiresAt - Date.now() <= DOCTOR_SETUP_LINK_TTL_MS, true);
    const firstToken = tokenFromLink(firstLink);

    const firstVerification = await call('verifyDoctorSetupLink', {token: firstToken});
    assert.equal(firstVerification.response.status, 200, JSON.stringify(firstVerification.body));
    assert.equal(firstVerification.body.result.valid, true);
    assert.equal(firstVerification.body.result.email, doctorEmail);

    // Issuing a new link invalidates the previous link for the same doctor.
    const secondLink = await createDoctorSetupLink({
      uid: doctorUid,
      email: doctorEmail,
      source: 'test-replacement',
    });
    const replacedVerification = await call('verifyDoctorSetupLink', {token: firstToken});
    assert.equal(replacedVerification.body.result.valid, false);
    assert.equal(replacedVerification.body.result.reason, 'replaced');

    // Expiry is read from the server-side Firestore record, not a browser
    // countdown. The test forces the record into the past without waiting.
    const expiredLink = await createDoctorSetupLink({
      uid: doctorUid,
      email: doctorEmail,
      source: 'test-expired',
    });
    await db.collection('doctor_access_links').doc(doctorUid).update({
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1),
    });
    const expiredVerification = await call('verifyDoctorSetupLink', {
      token: tokenFromLink(expiredLink),
    });
    assert.equal(expiredVerification.body.result.valid, false);
    assert.equal(expiredVerification.body.result.reason, 'expired');

    const usableLink = await createDoctorSetupLink({
      uid: doctorUid,
      email: doctorEmail,
      source: 'test-complete',
    });
    const completion = await call('completeDoctorAccountSetup', {
      token: tokenFromLink(usableLink),
      newPassword: 'Completed-Doctor-Password-123!',
    });
    assert.equal(completion.response.status, 200, JSON.stringify(completion.body));
    assert.equal(completion.body.result.success, true);

    // The completed setup password is the credential used by the Doctor
    // Login Portal; the original provisioning password is no longer usable.
    const completedLogin = await signIn(
        doctorEmail,
        'Completed-Doctor-Password-123!',
    );
    assert.equal(completedLogin.response.status, 200, JSON.stringify(completedLogin.body));
    assert.ok(completedLogin.body.idToken);
    const oldPasswordLogin = await signIn(
        doctorEmail,
        'Initial-Doctor-Password-123!',
    );
    assert.notEqual(oldPasswordLogin.response.status, 200);

    // A setup token is one-time even after the password update succeeds.
    const reusedVerification = await call('verifyDoctorSetupLink', {
      token: tokenFromLink(usableLink),
    });
    assert.equal(reusedVerification.body.result.valid, false);
    assert.equal(reusedVerification.body.result.reason, 'used');

    // The resend endpoint is doctor-scoped and has a server-side cooldown.
    const resend = await call('requestDoctorAccountSetupLink', {email: doctorEmail});
    assert.equal(resend.response.status, 200, JSON.stringify(resend.body));
    assert.equal(resend.body.result.success, false);
    assert.match(resend.body.result.message, /could not send/i);
    const rateLimited = await call('requestDoctorAccountSetupLink', {email: doctorEmail});
    assert.equal(rateLimited.response.status, 429, JSON.stringify(rateLimited.body));
    assert.equal(rateLimited.body.error.status, 'RESOURCE_EXHAUSTED');

    console.log('Doctor access link lifecycle test passed.');
  } finally {
    await db.collection('doctor_access_links').doc(doctorUid).delete().catch(() => {});
    await db.collection('doctor_setup_rate_limits').doc(`email_${hash(doctorEmail)}`).delete().catch(() => {});
    await db.collection('doctor_setup_rate_limits').doc(`ip_${hash('127.0.0.1')}`).delete().catch(() => {});
    await db.collection('users').doc(doctorUid).delete().catch(() => {});
    if (authUser) await admin.auth().deleteUser(authUser.uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
