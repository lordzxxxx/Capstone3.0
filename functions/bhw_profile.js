const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {ServerValue} = require('firebase-admin/database');

if (!admin.apps.length) {
  admin.initializeApp();
}

const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);

function normalizeText(value) {
  return String(value || '').trim().toLowerCase();
}

function textValue(value, field, {maxLength = 80, required = false} = {}) {
  if (value !== undefined && value !== null && typeof value !== 'string') {
    throw new functions.https.HttpsError(
        'invalid-argument',
        `${field} must be text.`,
    );
  }
  const text = String(value || '').trim();
  if ((required && !text) || text.length > maxLength ||
      (text.length > 0 && !/\S/.test(text))) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        `${field} is invalid.`,
    );
  }
  return text;
}

function isApprovedActiveBhw(profile) {
  const approved = normalizeText(profile?.approvalStatus) === 'approved' ||
    profile?.isApproved === true;
  return normalizeText(profile?.role) === 'bhw' &&
    approved &&
    ['active', 'approved'].includes(
        normalizeText(profile?.accountStatus || profile?.status),
    );
}

function isApprovedActiveCho(profile) {
  const approved = normalizeText(profile?.approvalStatus) === 'approved' ||
    profile?.isApproved === true;
  return [
    'cho',
    'cho_admin',
    'cho_super_admin',
    'super_admin',
    'admin',
  ].includes(normalizeText(profile?.role)) &&
    approved &&
    ['active', 'approved'].includes(
        normalizeText(profile?.accountStatus || profile?.status),
    );
}

exports.updateOwnBhwProfile = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to update your profile.',
    );
  }

  const uid = context.auth.uid;
  const userRef = db.collection('users').doc(uid);
  const userSnapshot = await userRef.get();
  if (!userSnapshot.exists || !isApprovedActiveBhw(userSnapshot.data())) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Only an approved, active BHW can update this profile.',
    );
  }

  const current = userSnapshot.data() || {};
  const fullName = textValue(data?.fullName, 'Full name', {
    maxLength: 120,
    required: true,
  });
  const username = textValue(data?.username, 'Username', {
    maxLength: 80,
    required: true,
  });
  if (username.length < 3) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Username must be at least 3 characters.',
    );
  }

  const contactNumber = textValue(data?.contactNumber, 'Contact number', {
    maxLength: 20,
  });
  if (contactNumber && !/^(?:\+63|0)\d{10}$/.test(contactNumber)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Contact number is invalid. Use a Philippine mobile number.',
    );
  }

  const usernameLower = normalizeText(username);
  const [lowerMatches, exactMatches] = await Promise.all([
    db.collection('users').where('usernameLower', '==', usernameLower)
        .limit(5).get(),
    db.collection('users').where('username', '==', username).limit(5).get(),
  ]);
  const conflictingUser = [...lowerMatches.docs, ...exactMatches.docs]
      .find((doc) => doc.id !== uid);
  if (conflictingUser) {
    throw new functions.https.HttpsError(
        'already-exists',
        'That username is already in use.',
    );
  }

  const updates = {
    fullName,
    displayName: fullName,
    username,
    usernameLower,
    contactNumber,
    phoneNumber: contactNumber,
    updatedBy: uid,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const batch = db.batch();
  batch.set(userRef, updates, {merge: true});

  const barangayCode = String(current.barangayCode || '').trim().toUpperCase();
  if (barangayCode) {
    batch.set(
        db.doc(`barangays/${barangayCode}/users/${uid}`),
        updates,
        {merge: true},
    );
  }
  await batch.commit();

  try {
    await admin.auth().updateUser(uid, {displayName: fullName});
  } catch (error) {
    console.error('updateOwnBhwProfile Auth display name sync failed', {
      uid,
      code: error?.code || 'unknown',
    });
  }

  await admin.database().ref(`users/${uid}`).update({
    fullName,
    displayName: fullName,
    username,
    usernameLower,
    contactNumber,
    phoneNumber: contactNumber,
    updatedAt: ServerValue.TIMESTAMP,
  });

  await db.collection('audit_logs').add({
    action: 'bhw_profile_updated',
    actorUid: uid,
    targetUid: uid,
    updatedFields: ['fullName', 'username', 'contactNumber'],
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    fullName,
    username,
    contactNumber,
  };
});

exports.updateOwnChoProfile = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to update your profile.',
    );
  }

  const uid = context.auth.uid;
  const userRef = db.collection('users').doc(uid);
  const userSnapshot = await userRef.get();
  if (!userSnapshot.exists || !isApprovedActiveCho(userSnapshot.data())) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Only an approved, active CHO account can update this profile.',
    );
  }

  const fullName = textValue(data?.fullName, 'Full name', {
    maxLength: 120,
    required: true,
  });
  const username = textValue(data?.username, 'Username', {
    maxLength: 80,
    required: true,
  });
  if (username.length < 3) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Username must be at least 3 characters.',
    );
  }
  const contactNumber = textValue(data?.contactNumber, 'Contact number', {
    maxLength: 20,
  });
  if (contactNumber && !/^(?:\+63|0)\d{10}$/.test(contactNumber)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Contact number is invalid. Use a Philippine mobile number.',
    );
  }

  const usernameLower = normalizeText(username);
  const [lowerMatches, exactMatches] = await Promise.all([
    db.collection('users').where('usernameLower', '==', usernameLower)
        .limit(5).get(),
    db.collection('users').where('username', '==', username).limit(5).get(),
  ]);
  const conflictingUser = [...lowerMatches.docs, ...exactMatches.docs]
      .find((doc) => doc.id !== uid);
  if (conflictingUser) {
    throw new functions.https.HttpsError(
        'already-exists',
        'That username is already in use.',
    );
  }

  const updates = {
    fullName,
    displayName: fullName,
    username,
    usernameLower,
    contactNumber,
    phoneNumber: contactNumber,
    updatedBy: uid,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await userRef.set(updates, {merge: true});

  try {
    await admin.auth().updateUser(uid, {displayName: fullName});
  } catch (error) {
    console.error('updateOwnChoProfile Auth display name sync failed', {
      uid,
      code: error?.code || 'unknown',
    });
  }
  await admin.database().ref(`users/${uid}`).update({
    fullName,
    displayName: fullName,
    username,
    usernameLower,
    contactNumber,
    phoneNumber: contactNumber,
    updatedAt: ServerValue.TIMESTAMP,
  });
  await db.collection('audit_logs').add({
    action: 'cho_profile_updated',
    actorUid: uid,
    targetUid: uid,
    updatedFields: ['fullName', 'username', 'contactNumber'],
    createdAt: FieldValue.serverTimestamp(),
  });

  return {success: true, fullName, username, contactNumber};
});
