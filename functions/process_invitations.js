const functions = require('firebase-functions');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { ServerValue } = require('firebase-admin/database');
const { generateTemporaryPassword } = require('./password_policy');
const { sendSystemEmail } = require('./mailer');
const { defaultPermissionsForRole } = require('./rbac_policy');

const FIRESTORE_DATABASE_ID = 'capstone-c98f9';

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);

/**
 * Firestore trigger: when an admin writes an `invitations` document, this function
 * will create the Auth user if missing, set a custom claim role (e.g., 'CHO'),
 * write the Realtime Database `users/{uid}` node with role/email, and email a
 * secure password-setup link. The link is never persisted in Firestore logs.
 */
exports.processInvitation = onDocumentCreated({
  document: 'invitations/{invId}',
  database: FIRESTORE_DATABASE_ID,
  region: 'us-central1',
}, async (event) => {
  const snap = event.data;
  if (!snap) {
    return;
  }

  const data = snap.data() || {};
  const email = (data.email || '').toString().toLowerCase();
  const requestedRole = (data.role || 'CHO').toString();
  const createdBy = data.createdBy || null;
  const fullName = (data.fullName || data.displayName || '').toString().trim();
  const specialization = (data.specialization || data.doctorSpecialization || 'General Medicine').toString().trim() || 'General Medicine';
  const availability = (data.availability || data.doctorAvailability || 'available').toString().trim().toLowerCase() || 'available';

  if (!email) {
    await snap.ref.update({ status: 'error', error: 'missing email', processedAt: FieldValue.serverTimestamp() });
    return;
  }

  const inviter = createdBy ? await db.collection('users').doc(createdBy).get() : null;
  const inviterData = inviter?.exists ? inviter.data() || {} : {};
  const inviterRole = String(inviterData.role || '').trim().toUpperCase();
  const inviterApproval = String(inviterData.approvalStatus || '').trim().toLowerCase();
  const inviterStatus = String(inviterData.accountStatus || inviterData.status || '').trim().toLowerCase();
  const authorizedInviter = ['CHO_ADMIN', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'].includes(inviterRole) &&
    inviterApproval === 'approved' && ['active', 'approved'].includes(inviterStatus);
  if (!authorizedInviter || !['CHO', 'DOCTOR'].includes(requestedRole.toUpperCase())) {
    await snap.ref.update({
      status: 'rejected',
      error: 'Only the CHO Admin may create CHO or doctor accounts.',
      processedAt: FieldValue.serverTimestamp(),
    });
    return;
  }

  try {
    // Try to find existing user
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch (e) {
      // Create user with a random temporary password
      const tempPass = generateTemporaryPassword();
      userRecord = await admin.auth().createUser({ email, password: tempPass });
      console.log('Created user', userRecord.uid, 'for', email);
    }

    await admin.auth().updateUser(userRecord.uid, {
      displayName: fullName || userRecord.displayName || email,
      disabled: false,
    });

    // Set custom claims
    const roleClaim = requestedRole.toLowerCase();
    await admin.auth().setCustomUserClaims(userRecord.uid, { role: roleClaim });

    // Write users node in Realtime Database
    await admin.database().ref(`users/${userRecord.uid}`).update({
      email,
      role: requestedRole,
      username: fullName || email,
      fullName: fullName || email,
      displayName: fullName || email,
      specialization,
      doctorSpecialization: specialization,
      availability,
      doctorAvailability: availability,
      invitedBy: createdBy,
      invitedAt: Date.now(),
    });

    const existingUserSnap = await db.collection('users').doc(userRecord.uid).get();
    const existingUserData = existingUserSnap.data() || {};

    await db.collection('users').doc(userRecord.uid).set({
      uid: userRecord.uid,
      username: fullName || existingUserData.username || email,
      usernameLower: (fullName || existingUserData.username || email).toString().trim().toLowerCase(),
      fullName: fullName || existingUserData.fullName || '',
      displayName: fullName || existingUserData.displayName || email,
      email,
      emailLower: email,
      role: requestedRole.toUpperCase(),
      accessRoleKey: requestedRole.toUpperCase(),
      permissions: defaultPermissionsForRole(requestedRole),
      accessScope: 'citywide',
      organizationLevel: 'citywide',
      dataVisibilityStartAt: existingUserData.dataVisibilityStartAt || FieldValue.serverTimestamp(),
      specialization,
      doctorSpecialization: specialization,
      specialty: specialization,
      availability,
      doctorAvailability: availability,
      approvalStatus: existingUserData.approvalStatus || 'approved',
      accountStatus: existingUserData.accountStatus || 'active',
      doctorRegistrySource: 'invitation_trigger',
      doctorRegisteredByUid: createdBy,
      createdAt: existingUserData.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    await db.collection('registration_email_locks').doc(email).set({
      uid: userRecord.uid,
      email,
      emailLower: email,
      updatedAt: FieldValue.serverTimestamp(),
      source: 'invitation-trigger',
    }, { merge: true });

    if (fullName) {
      await db.collection('registration_username_locks').doc(fullName.toLowerCase()).set({
        uid: userRecord.uid,
        username: fullName,
        usernameLower: fullName.toLowerCase(),
        updatedAt: FieldValue.serverTimestamp(),
        source: 'invitation-trigger',
      }, { merge: true });
    }

    // Generate password reset link so invitee can set their own password
    let resetLink = null;
    try {
      resetLink = await admin.auth().generatePasswordResetLink(email);
    } catch (e) {
      console.warn('Could not generate reset link:', e);
    }

    // Send through the fixed AI-DSUHIS system mailer.
    let emailSent = false;
    let emailError = null;
    const emailResult = resetLink ? await sendSystemEmail({
      to: email,
      subject: 'Your AI-DSUHIS Account Is Ready',
      text: `A CHO Admin created your AI-DSUHIS ${requestedRole.toUpperCase()} account. Set your password securely: ${resetLink}`,
      html: `<p>A CHO Admin created your AI-DSUHIS ${requestedRole.toUpperCase()} account.</p><p><a href="${resetLink}">Set your password securely</a></p>`,
    }) : {sent: false, reason: 'activation_link_unavailable'};
    emailSent = emailResult.sent;
    emailError = emailResult.sent ? null : emailResult.reason;

    // Update invitation doc with result
    await snap.ref.update({
      status: 'processed',
      uid: userRecord.uid,
      emailSent: emailSent,
      emailError: emailError,
      processedAt: FieldValue.serverTimestamp(),
    });

    console.log('Processed invitation for', email);
  } catch (err) {
    console.error('processInvitation error:', err);
    await snap.ref.update({ status: 'error', error: err.message || String(err), processedAt: FieldValue.serverTimestamp() });
  }
});
