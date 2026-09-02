const assert = require('node:assert/strict');

const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'capstone-c98f9';
if (!admin.apps.length) admin.initializeApp({projectId});

const db = new admin.firestore.Firestore({
  projectId,
  databaseId: 'capstone-c98f9',
});
const auth = admin.auth();
const password = 'A-strong-test-password-123!';
const adminUid = 'bhw-management-test-admin';
const targetUid = 'bhw-management-test-target';
const bhwUid = 'bhw-management-test-caller';
const adminEmail = 'bhw-management-admin@example.test';
const targetEmail = 'bhw-management-target@example.test';
const bhwEmail = 'bhw-management-caller@example.test';

async function call(name, token, data = {}) {
  const headers = {'Content-Type': 'application/json'};
  if (token) headers.Authorization = `Bearer ${token}`;
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

async function signIn(email) {
  const response = await fetch(
      'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:' +
      'signInWithPassword?key=fake-api-key',
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

async function cleanup() {
  await Promise.all([
    db.collection('users').doc(adminUid).delete(),
    db.collection('users').doc(targetUid).delete(),
    db.collection('users').doc(bhwUid).delete(),
    db.collection('bhw_registration_requests').doc(targetUid).delete(),
  ].map((operation) => operation.catch(() => {})));
  await Promise.all(
      [adminUid, targetUid, bhwUid].map((uid) =>
        auth.deleteUser(uid).catch(() => {})),
  );
}

async function main() {
  try {
    await auth.createUser({
      uid: adminUid,
      email: adminEmail,
      password,
      displayName: 'Flow Admin',
    });
    await auth.createUser({
      uid: targetUid,
      email: targetEmail,
      password,
      displayName: 'Pending BHW',
    });
    await auth.createUser({
      uid: bhwUid,
      email: bhwEmail,
      password,
      displayName: 'BHW Caller',
    });

    await db.collection('users').doc(adminUid).set({
      uid: adminUid,
      email: adminEmail,
      role: 'CHO_ADMIN',
      approvalStatus: 'approved',
      accountStatus: 'active',
    });
    await db.collection('users').doc(targetUid).set({
      uid: targetUid,
      email: targetEmail,
      fullName: 'Pending BHW',
      username: 'pending-bhw',
      role: 'BHW',
      approvalStatus: 'pending',
      accountStatus: 'pending_approval',
      status: 'Pending',
      barangay: 'Barangay 10',
      barangayCode: 'BARANGAY_10',
      barangayDistrict: 'District',
    });
    await db.collection('users').doc(bhwUid).set({
      uid: bhwUid,
      email: bhwEmail,
      role: 'BHW',
      approvalStatus: 'approved',
      accountStatus: 'active',
      barangay: 'Barangay 10',
      barangayCode: 'BARANGAY_10',
    });
    await db.collection('bhw_registration_requests').doc(targetUid).set({
      uid: targetUid,
      email: targetEmail,
      fullName: 'Pending BHW',
      username: 'pending-bhw',
      role: 'BHW',
      approvalStatus: 'pending',
      accountStatus: 'pending_approval',
      reviewStatus: 'pending',
      barangay: 'Barangay 10',
      barangayCode: 'BARANGAY_10',
      address: {barangay: 'Barangay 10'},
      bhw: {assignedBarangay: 'Barangay 10'},
    });

    const adminToken = await signIn(adminEmail);

    const approved = await call('reviewBhwRegistration', adminToken, {
      uid: targetUid,
      approved: true,
    });
    assert.equal(approved.response.status, 200, JSON.stringify(approved.body));
    let target = (await db.collection('users').doc(targetUid).get()).data();
    assert.equal(target.approvalStatus, 'approved');
    assert.equal(target.accountStatus, 'active');
    assert.equal(target.accessRoleKey, 'BHW');
    assert.equal((await auth.getUser(targetUid)).disabled, false);
    let request = (await db.collection('bhw_registration_requests')
        .doc(targetUid).get()).data();
    assert.equal(request.approvalStatus, 'approved');
    assert.equal(request.reviewStatus, 'approved');

    const edited = await call('updateChoAccount', adminToken, {
      uid: targetUid,
      role: 'BHW',
      accountStatus: 'active',
      barangay: 'Barangay 11',
      barangayCode: 'BARANGAY_11',
      barangayDistrict: 'District',
      fullName: 'Edited BHW',
      username: 'edited-bhw',
      contactNumber: '09171234567',
      assignedPurok: 'Purok 2',
    });
    assert.equal(edited.response.status, 200, JSON.stringify(edited.body));
    target = (await db.collection('users').doc(targetUid).get()).data();
    request = (await db.collection('bhw_registration_requests')
        .doc(targetUid).get()).data();
    assert.equal(target.fullName, 'Edited BHW');
    assert.equal(target.barangay, 'Barangay 11');
    assert.equal(target.assignedPurok, 'Purok 2');
    assert.equal(request.fullName, 'Edited BHW');
    assert.equal(request.approvalStatus, 'approved');
    assert.equal(request.reviewStatus, 'approved');
    assert.equal(request.address.sitio, 'Purok 2');
    assert.equal(request.bhw.assignedBarangay, 'Barangay 11');

    const rejected = await call('reviewBhwRegistration', adminToken, {
      uid: targetUid,
      approved: false,
      rejectionReason: 'Controlled emulator rejection test',
    });
    assert.equal(rejected.response.status, 200, JSON.stringify(rejected.body));
    target = (await db.collection('users').doc(targetUid).get()).data();
    assert.equal(target.approvalStatus, 'rejected');
    assert.equal(target.accountStatus, 'rejected');
    assert.equal((await auth.getUser(targetUid)).disabled, true);

    const bhwToken = await signIn(bhwEmail);
    const bhwAttempt = await call('reviewBhwRegistration', bhwToken, {
      uid: targetUid,
      approved: true,
    });
    assert.equal(bhwAttempt.response.status, 403, JSON.stringify(bhwAttempt.body));

    const unauthenticated = await call('reviewBhwRegistration', null, {
      uid: targetUid,
      approved: true,
    });
    assert.equal(
        unauthenticated.response.status,
        401,
        JSON.stringify(unauthenticated.body),
    );

    console.log('BHW approve/edit/save/reject authorization flow passed.');
  } finally {
    await cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
