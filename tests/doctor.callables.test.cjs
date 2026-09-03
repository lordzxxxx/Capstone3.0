const assert = require('node:assert/strict');

const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'demo-doctor-portal';
if (!admin.apps.length) admin.initializeApp({projectId});
const db = new admin.firestore.Firestore({projectId, databaseId: 'capstone-c98f9'});

const doctorUid = 'doctor-portal-test-doctor';
const targetUid = 'doctor-portal-test-target';
const referralId = 'doctor-portal-test-referral';
const doctorEmail = 'doctor-portal-test@example.test';
const targetEmail = 'doctor-portal-target@example.test';
const declineReferralId = 'doctor-portal-test-decline-referral';

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
  let doctorAuth;
  let targetAuth;
  try {
    doctorAuth = await admin.auth().createUser({
      uid: doctorUid,
      email: doctorEmail,
      password: 'A-strong-test-password-123!',
      displayName: 'Portal Test Doctor',
    });
    targetAuth = await admin.auth().createUser({
      uid: targetUid,
      email: targetEmail,
      password: 'A-strong-test-password-123!',
      displayName: 'Portal Target Doctor',
    });
    const profile = (uid, email, fullName) => ({
      uid,
      email,
      fullName,
      displayName: fullName,
      username: fullName.toLowerCase().replaceAll(' ', '-'),
      usernameLower: fullName.toLowerCase().replaceAll(' ', '-'),
      role: 'DOCTOR',
      approvalStatus: 'approved',
      accountStatus: 'active',
      isApproved: true,
      permissions: [
        'dashboard.view',
        'referrals.assigned.view',
        'profile.view',
      ],
      specialization: 'General Medicine',
      availability: 'available',
    });
    await db.collection('users').doc(doctorUid).set(profile(doctorUid, doctorEmail, 'Portal Test Doctor'));
    await db.collection('users').doc(targetUid).set(profile(targetUid, targetEmail, 'Portal Target Doctor'));
    const referralData = (id, patientName) => ({
      patientId: `patient-${id}`,
      patientName,
      referralReason: 'Controlled doctor portal workflow test',
      priority: 'routine',
      barangay: 'Test Barangay',
      createdByUid: 'doctor-portal-test-bhw',
      createdByName: 'Test BHW',
      status: 'assigned',
      submissionStatus: 'submitted',
      assignedDoctorUid: doctorUid,
      assignedDoctorName: 'Portal Test Doctor',
      assignedDoctorEmail: doctorEmail,
      assignmentEventId: `${id}:${doctorUid}`,
      assignmentNotificationStatus: 'sent',
      assignmentNotificationSentFor: `${id}:${doctorUid}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection('referrals').doc(referralId).set(
        referralData(referralId, 'Controlled Test Patient'));
    await db.collection('referrals').doc(declineReferralId).set(
        referralData(declineReferralId, 'Controlled Decline Patient'));

    const token = await signIn(doctorEmail, 'A-strong-test-password-123!');
    const targets = await call('listDoctorTransferTargets', token);
    assert.equal(targets.response.status, 200, JSON.stringify(targets.body));
    assert.equal(targets.body.result.doctors.length, 1);
    assert.equal(targets.body.result.doctors[0].uid, targetUid);

    const accepted = await call('doctorReferralAction', token, {
      referralId,
      action: 'accept',
      operationId: `${referralId}:accept:test`,
    });
    assert.equal(accepted.response.status, 200, JSON.stringify(accepted.body));
    assert.equal(accepted.body.result.status, 'waiting_consultation');

    const updated = await call('doctorReferralAction', token, {
      referralId,
      action: 'update_care',
      status: 'consulted',
      doctorDiagnosis: 'Controlled assessment',
      doctorNotes: 'Controlled note',
      operationId: `${referralId}:consult:test`,
    });
    assert.equal(updated.response.status, 200, JSON.stringify(updated.body));
    assert.equal(updated.body.result.status, 'consulted');

    const declined = await call('doctorReferralAction', token, {
      referralId: declineReferralId,
      action: 'decline',
      reason: 'Controlled decline test',
      operationId: `${declineReferralId}:decline:test`,
    });
    assert.equal(declined.response.status, 200, JSON.stringify(declined.body));
    assert.equal(declined.body.result.status, 'declined');

    const transferred = await call('doctorReferralAction', token, {
      referralId,
      action: 'transfer',
      targetDoctorUid: targetUid,
      reason: 'Controlled workload transfer',
      operationId: `${referralId}:transfer:test`,
    });
    assert.equal(transferred.response.status, 200, JSON.stringify(transferred.body));
    assert.equal(transferred.body.result.newDoctorUid, targetUid);
    // No local mail provider is configured in the emulator. The assignment
    // must still persist and report a notification failure safely.
    assert.equal(transferred.body.result.notificationSent, false);

    const transferRetry = await call('doctorReferralAction', token, {
      referralId,
      action: 'transfer',
      targetDoctorUid: targetUid,
      reason: 'Controlled workload transfer',
      operationId: `${referralId}:transfer:test`,
    });
    assert.equal(transferRetry.response.status, 200, JSON.stringify(transferRetry.body));
    assert.equal(transferRetry.body.result.alreadyProcessed, true);

    const targetToken = await signIn(targetEmail, 'A-strong-test-password-123!');
    const targetAccepted = await call('doctorReferralAction', targetToken, {
      referralId,
      action: 'accept',
      operationId: `${referralId}:target-accept:test`,
    });
    assert.equal(targetAccepted.response.status, 200, JSON.stringify(targetAccepted.body));
    const targetConsulted = await call('doctorReferralAction', targetToken, {
      referralId,
      action: 'update_care',
      status: 'consulted',
      doctorNotes: 'Target doctor consultation test',
      operationId: `${referralId}:target-consult:test`,
    });
    assert.equal(targetConsulted.response.status, 200, JSON.stringify(targetConsulted.body));
    const targetClosed = await call('doctorReferralAction', targetToken, {
      referralId,
      action: 'close',
      operationId: `${referralId}:target-close:test`,
    });
    assert.equal(targetClosed.response.status, 200, JSON.stringify(targetClosed.body));
    assert.equal(targetClosed.body.result.status, 'completed');

    const finalReferral = (await db.collection('referrals').doc(referralId).get()).data();
    assert.equal(finalReferral.assignedDoctorUid, targetUid);
    assert.equal(finalReferral.status, 'completed');
    assert.equal(finalReferral.transferHistory.length, 1);
    assert.equal(finalReferral.assignmentNotificationStatus, 'failed');
    assert.ok(finalReferral.statusHistory.some((entry) => entry.action === 'transfer'));
    assert.ok(finalReferral.statusHistory.some((entry) => entry.action === 'close'));
    assert.equal(
        (await db.collection('referrals').doc(declineReferralId).get()).data().status,
        'declined');

    const oldDoctorAttempt = await call('doctorReferralAction', token, {
      referralId,
      action: 'close',
      operationId: `${referralId}:old-doctor-close:test`,
    });
    assert.equal(oldDoctorAttempt.response.status, 403);
    assert.equal(oldDoctorAttempt.body.error.status, 'PERMISSION_DENIED');

    const profileUpdate = await call('updateOwnDoctorProfile', token, {
      fullName: 'Portal Test Doctor Updated',
      username: 'portal-test-doctor-updated',
      contactNumber: '09171234567',
      professionalTitle: 'Medical Doctor',
      specialization: 'Family Medicine',
    });
    assert.equal(profileUpdate.response.status, 200, JSON.stringify(profileUpdate.body));
    const updatedProfile = (await db.collection('users').doc(doctorUid).get()).data();
    assert.equal(updatedProfile.fullName, 'Portal Test Doctor Updated');
    assert.equal(updatedProfile.specialization, 'Family Medicine');

    const unauthenticated = await call('doctorReferralAction', '', {referralId, action: 'accept'});
    assert.equal(unauthenticated.response.status, 401);
    console.log('Doctor callable workflow test passed.');
  } finally {
    await db.collection('referrals').doc(referralId).delete().catch(() => {});
    await db.collection('referrals').doc(declineReferralId).delete().catch(() => {});
    await db.collection('users').doc(doctorUid).delete().catch(() => {});
    await db.collection('users').doc(targetUid).delete().catch(() => {});
    if (doctorAuth) await admin.auth().deleteUser(doctorAuth.uid).catch(() => {});
    if (targetAuth) await admin.auth().deleteUser(targetAuth.uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
