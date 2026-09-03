const assert = require('node:assert/strict');

const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'capstone-c98f9';
if (!admin.apps.length) admin.initializeApp({projectId});
const db = new admin.firestore.Firestore({projectId, databaseId: 'capstone-c98f9'});
const adminUid = 'rbac-callable-test-admin';
const targetUid = 'rbac-callable-test-user';
const email = 'rbac-callable-test-admin@example.test';
const targetEmail = 'rbac-target@example.test';

async function call(name, idToken, data = {}) {
  const response = await fetch(
    `http://127.0.0.1:5001/${projectId}/us-central1/${name}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({data}),
    },
  );
  const body = await response.json();
  return {response, body};
}

async function main() {
  let authUser;
  let targetAuthUser;
  try {
    authUser = await admin.auth().createUser({
      uid: adminUid,
      email,
      password: 'A-strong-test-password-123!',
      displayName: 'RBAC Test Admin',
    });
    await db.collection('users').doc(adminUid).set({
      uid: adminUid,
      email,
      // Reproduce the legacy mismatch that previously hid CHO management:
      // Auth has the authoritative admin claim while the profile is stale.
      role: 'CHO',
      approvalStatus: 'approved',
      accountStatus: 'active',
    });
    await admin.auth().setCustomUserClaims(adminUid, {
      role: 'CHO_ADMIN',
      approvalStatus: 'approved',
      accountStatus: 'active',
    });

    const signIn = await fetch(
      'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key',
      {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({email, password: 'A-strong-test-password-123!', returnSecureToken: true}),
      },
    );
    const signInBody = await signIn.json();
    assert.ok(signInBody.idToken, JSON.stringify(signInBody));

    const listed = await call('listAccessRoles', signInBody.idToken);
    assert.equal(listed.response.status, 200);
    assert.ok(Array.isArray(listed.body.result.roles));

    const saved = await call('saveAccessRole', signInBody.idToken, {
      name: 'Referral Intake Helper',
      description: 'Can submit and view referrals.',
      baseRole: 'CHO',
      permissions: ['dashboard.view', 'referrals.view', 'referrals.create', 'rbac.manage'],
    });
    assert.equal(saved.response.status, 200, JSON.stringify(saved.body));
    assert.equal(saved.body.result.roleKey, 'CUSTOM_REFERRAL_INTAKE_HELPER');

    const edited = await call('saveAccessRole', signInBody.idToken, {
      roleKey: 'CUSTOM_REFERRAL_INTAKE_HELPER',
      name: 'Referral Intake Coordinator',
      description: 'Updated referral access for the test role.',
      baseRole: 'CHO',
      permissions: ['dashboard.view', 'referrals.view'],
    });
    assert.equal(edited.response.status, 200, JSON.stringify(edited.body));
    assert.deepEqual(edited.body.result.permissions, ['dashboard.view', 'referrals.view']);
    const editedRole = await db.collection('roles').doc('CUSTOM_REFERRAL_INTAKE_HELPER').get();
    assert.equal(editedRole.data().name, 'Referral Intake Coordinator');
    const listedAfterEdit = await call('listAccessRoles', signInBody.idToken);
    assert.equal(listedAfterEdit.response.status, 200);
    assert.equal(
      listedAfterEdit.body.result.roles.find((role) => role.roleKey === 'CUSTOM_REFERRAL_INTAKE_HELPER').name,
      'Referral Intake Coordinator',
    );

    await db.collection('users').doc(targetUid).set({
      uid: targetUid,
      email: targetEmail,
      role: 'CHO',
      approvalStatus: 'approved',
      accountStatus: 'active',
      barangay: 'Barangay 10',
      barangayCode: 'BARANGAY_10',
    });
    targetAuthUser = await admin.auth().createUser({
      uid: targetUid,
      email: targetEmail,
      password: 'A-strong-test-password-123!',
      displayName: 'RBAC Test User',
    });
    const assigned = await call('updateChoAccount', signInBody.idToken, {
      uid: targetUid,
      accessRoleKey: 'CUSTOM_REFERRAL_INTAKE_HELPER',
      role: 'CHO',
      accountStatus: 'disabled',
    });
    assert.equal(assigned.response.status, 200, JSON.stringify(assigned.body));
    const target = (await db.collection('users').doc(targetUid).get()).data();
    assert.equal(target.accessRoleKey, 'CUSTOM_REFERRAL_INTAKE_HELPER');
    assert.deepEqual(target.permissions, ['dashboard.view', 'referrals.view']);

    const blockedDelete = await call('deleteAccessRole', signInBody.idToken, {
      roleKey: 'CUSTOM_REFERRAL_INTAKE_HELPER',
    });
    assert.equal(blockedDelete.response.status, 400);
    assert.equal(blockedDelete.body.error?.status, 'FAILED_PRECONDITION');

    const unassigned = await call('updateChoAccount', signInBody.idToken, {
      uid: targetUid,
      accessRoleKey: 'CHO',
      role: 'CHO',
      accountStatus: 'disabled',
    });
    assert.equal(unassigned.response.status, 200, JSON.stringify(unassigned.body));

    const doctorUpdated = await call('updateChoAccount', signInBody.idToken, {
      uid: targetUid,
      role: 'DOCTOR',
      accountStatus: 'active',
      accessRoleKey: 'DOCTOR',
      fullName: 'RBAC Test Doctor',
      username: 'rbac-test-doctor',
      specialization: 'General Medicine',
      availability: 'available',
    });
    assert.equal(doctorUpdated.response.status, 200, JSON.stringify(doctorUpdated.body));
    const archived = await call('archiveChoAccount', signInBody.idToken, {
      uid: targetUid,
    });
    assert.equal(archived.response.status, 200, JSON.stringify(archived.body));
    assert.equal(archived.body.result.accountStatus, 'archived');
    const archivedTarget = (await db.collection('users').doc(targetUid).get()).data();
    assert.equal(archivedTarget.accountStatus, 'archived');
    assert.equal(archivedTarget.status, 'Archived');
    assert.equal((await admin.auth().getUser(targetUid)).disabled, true);

    const deleted = await call('deleteAccessRole', signInBody.idToken, {
      roleKey: 'CUSTOM_REFERRAL_INTAKE_HELPER',
    });
    assert.equal(deleted.response.status, 200, JSON.stringify(deleted.body));
    assert.equal((await db.collection('roles').doc('CUSTOM_REFERRAL_INTAKE_HELPER').get()).exists, false);
    console.log('RBAC callable test passed.');
  } finally {
    await db.collection('users').doc(targetUid).delete().catch(() => {});
    await db.collection('users').doc(adminUid).delete().catch(() => {});
    await db.collection('roles').doc('CUSTOM_REFERRAL_INTAKE_HELPER').delete().catch(() => {});
    if (targetAuthUser) await admin.auth().deleteUser(targetAuthUser.uid).catch(() => {});
    if (authUser) await admin.auth().deleteUser(authUser.uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
