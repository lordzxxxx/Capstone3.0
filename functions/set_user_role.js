/**
 * set_user_role.js
 * 
 * Cloud Function to set custom claims and role for a newly created user.
 * Called from client-side code after signup.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Callable Cloud Function to set role and custom claims
 * 
 * Usage from client:
 * const functions = firebase.functions();
 * const setUserRole = functions.httpsCallable('setUserRole');
 * 
 * await setUserRole({
 *   uid: userCredential.user.uid,
 *   role: 'CHO' // or 'BHW'
 * });
 */
exports.setUserRole = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to call this function'
    );
  }

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
  const validRoles = ['CHO', 'BHW'];
  if (!validRoles.includes(role.toUpperCase())) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Role must be one of: ${validRoles.join(', ')}`
    );
  }

  try {
    // Set custom claims in Firebase Auth
    await admin.auth().setCustomUserClaims(uid, { role: role.toUpperCase() });

    // Update Realtime Database
    await admin.database().ref(`users/${uid}`).update({
      role: role.toUpperCase(),
      claimsSetAt: admin.database.ServerValue.TIMESTAMP,
    });

    return {
      success: true,
      message: `Custom claims set for user ${uid} with role ${role.toUpperCase()}`,
      uid,
      role: role.toUpperCase(),
    };
  } catch (error) {
    console.error('Error setting user role:', error);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to set user role: ${error.message}`
    );
  }
});
