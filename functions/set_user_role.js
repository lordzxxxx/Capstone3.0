/**
 * set_user_role.js
 *
 * Cloud Function to set custom claims and role for a user.
 * Restricted to callers who already hold a CHO-tier administrative role.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');

if (!admin.apps.length) {
  admin.initializeApp();
}

// Keep this aligned with lib/firebase_helper.dart and account_policy.js.
const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);
const CHO_OPERATOR_ROLES = ['CHO_ADMIN', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'];

/**
 * Verifies the CALLER already holds a CHO-tier role before they are allowed
 * to assign a role to anyone. Both checks read server-trusted sources only
 * (the caller's own Auth custom claims and their own Firestore profile) —
 * never the client-supplied request payload.
 */
async function ensureCallerIsChoOperator(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to call this function'
    );
  }

  const [authRecord, profileSnapshot] = await Promise.all([
    admin.auth().getUser(context.auth.uid),
    db.doc(`users/${context.auth.uid}`).get(),
  ]);

  const claimRole = String(authRecord.customClaims && authRecord.customClaims.role || '').toUpperCase();
  const profileRole = String(profileSnapshot.exists ? (profileSnapshot.data().role || '') : '').toUpperCase();

  const profile = profileSnapshot.exists ? profileSnapshot.data() : {};
  const approval = String(profile.approvalStatus || '').toLowerCase();
  const accountStatus = String(profile.accountStatus || profile.status || '').toLowerCase();
  if ((!CHO_OPERATOR_ROLES.includes(claimRole) && !CHO_OPERATOR_ROLES.includes(profileRole)) ||
      approval !== 'approved' || !['active', 'approved'].includes(accountStatus)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only CHO or administrator accounts may assign user roles.'
    );
  }
}

/**
 * Callable Cloud Function to set role and custom claims.
 * Caller must already be an approved CHO/administrator account.
 *
 * Usage from client:
 * const functions = firebase.functions();
 * const setUserRole = functions.httpsCallable('setUserRole');
 *
 * await setUserRole({
 *   uid: targetUid,
 *   role: 'CHO' // or 'BHW'
 * });
 */
exports.setUserRole = functions.https.onCall(async (data, context) => {
  await ensureCallerIsChoOperator(context);

  const { uid, role } = data;

  // Validate inputs
  if (!uid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'UID is required'
    );
  }

  if (!role) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Role is required'
    );
  }

  // Validate role
  const validRoles = ['CHO', 'DOCTOR', 'BHW'];
  if (!validRoles.includes(role.toUpperCase())) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Role must be one of: ${validRoles.join(', ')}`
    );
  }

  try {
    const normalizedRole = role.toUpperCase();
    const targetRef = db.doc(`users/${uid}`);
    const targetSnapshot = await targetRef.get();
    if (!targetSnapshot.exists) {
      throw new functions.https.HttpsError('not-found', 'The target account does not exist.');
    }
    const target = targetSnapshot.data() || {};
    if (normalizedRole === 'BHW' &&
        String(target.approvalStatus || '').toLowerCase() !== 'approved') {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'A BHW role can only be assigned after CHO approval.',
      );
    }
    await targetRef.set({
      role: normalizedRole,
      accessScope: normalizedRole === 'BHW' ? 'barangay' : 'citywide',
      updatedBy: context.auth.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const targetAuth = await admin.auth().getUser(uid);
    await admin.auth().setCustomUserClaims(uid, {
      ...(targetAuth.customClaims || {}),
      role: normalizedRole.toLowerCase(),
    });

    // Update Realtime Database
    await admin.database().ref(`users/${uid}`).update({
      role: normalizedRole,
      claimsSetAt: admin.database.ServerValue.TIMESTAMP,
    });

    return {
      success: true,
      message: `Custom claims set for user ${uid} with role ${normalizedRole}`,
      uid,
      role: normalizedRole,
    };
  } catch (error) {
    console.error('Error setting user role:', error);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to set user role: ${error.message}`
    );
  }
});
