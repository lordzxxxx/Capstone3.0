const assert = require('assert/strict');

const admin = require('../functions/node_modules/firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || 'demo-capstone-auto'});
}

const db = new admin.firestore.Firestore({
  projectId: process.env.GCLOUD_PROJECT || 'demo-capstone-auto',
  databaseId: 'capstone-c98f9',
});
const doctorId = 'automatic-referral-test-doctor';
const referralId = 'automatic-referral-test-referral';
const secondReferralId = 'automatic-referral-test-referral-2';

async function waitForReferral(id) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const snapshot = await db.collection('referrals').doc(id).get();
    const data = snapshot.data() || {};
    const notificationFinished = ['sent', 'failed'].includes(
        data.assignmentNotificationStatus,
    );
    if (data.status === 'awaiting_doctor_assignment' ||
        (data.assignedDoctorUid === doctorId && notificationFinished)) {
      return data;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('The automatic referral trigger did not complete in time.');
}

async function main() {
  try {
    await db.collection('users').doc(doctorId).set({
      uid: doctorId,
      username: 'Automatic Referral Test Doctor',
      email: 'automatic-referral-doctor@example.test',
      role: 'DOCTOR',
      approvalStatus: 'approved',
      accountStatus: 'active',
      availability: 'available',
    });
    await db.collection('referrals').doc(referralId).set({
      patientId: 'automatic-referral-test-patient',
      patientName: 'Automatic Referral Test Patient',
      referralReason: 'Controlled routing test',
      priority: 'routine',
      barangay: 'Test Barangay',
      barangayCode: 'TEST',
      createdByUid: 'automatic-referral-test-bhw',
      createdByRole: 'bhw',
      status: 'submitted',
      submissionStatus: 'submitted',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const referralPayload = (id, patientName) => ({
      patientId: `automatic-referral-test-patient-${id}`,
      patientName,
      referralReason: 'Controlled routing test',
      priority: 'routine',
      barangay: 'Test Barangay',
      barangayCode: 'TEST',
      createdByUid: 'automatic-referral-test-bhw',
      createdByRole: 'bhw',
      status: 'submitted',
      submissionStatus: 'submitted',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection('referrals').doc(secondReferralId).set(
        referralPayload(secondReferralId, 'Automatic Referral Test Patient 2'));

    const [result, secondResult] = await Promise.all([
      waitForReferral(referralId),
      waitForReferral(secondReferralId),
    ]);
    assert.equal(result.assignedDoctorUid, doctorId);
    assert.equal(result.status, 'assigned');
    assert.equal(result.assignmentSource, 'bhw_auto');
    assert.ok(result.assignmentEventId);
    assert.ok(['sent', 'failed'].includes(result.assignmentNotificationStatus));
    assert.equal(secondResult.assignedDoctorUid, doctorId);
    assert.equal(secondResult.status, 'assigned');
    assert.notEqual(result.assignmentEventId, secondResult.assignmentEventId);
    console.log('Automatic referral routing test passed:', {
      assignedDoctorUid: result.assignedDoctorUid,
      notificationStatus: result.assignmentNotificationStatus,
    });
  } finally {
    await db.collection('referrals').doc(referralId).delete();
    await db.collection('referrals').doc(secondReferralId).delete();
    await db.collection('users').doc(doctorId).delete();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
