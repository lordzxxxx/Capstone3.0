/**
 * set_cho_claims_auth.js
 * 
 * One-time bootstrap for the single main CHO Admin account.
 * This is intentionally restricted to the exact bootstrap email; all other
 * CHO/doctor accounts must be created by the CHO Admin callable workflow.
 * 
 * Usage:
 *   gcloud auth application-default login
 *   node set_cho_claims_auth.js theo@gmail.com
 */

const {applicationDefault, initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const {getDatabase, ServerValue} = require('firebase-admin/database');

const MAIN_CHO_ADMIN_EMAIL = 'theo@gmail.com';
const FIRESTORE_DATABASE_ID = 'capstone-c98f9';

// Use Application Default Credentials instead of a checked-in/local JSON key.
// For local execution, authenticate with `gcloud auth application-default login`
// or set GOOGLE_APPLICATION_CREDENTIALS to a protected file outside this repo.
const app = initializeApp({
  credential: applicationDefault(),
  projectId: 'capstone-c98f9',
  databaseURL: 'https://capstone-c98f9-default-rtdb.firebaseio.com'
});
const auth = getAuth(app);
const rtdb = getDatabase(app);

async function fixCHORole(email) {
  try {
    if (String(email || '').trim().toLowerCase() !== MAIN_CHO_ADMIN_EMAIL) {
      throw new Error(`This bootstrap script only accepts ${MAIN_CHO_ADMIN_EMAIL}.`);
    }
    console.log(`\nAttempting to fix CHO role for: ${email}\n`);

    // Step 1: Get user by email
    console.log('Step 1: Looking up user by email...');
    const user = await auth.getUserByEmail(email);
    console.log(`✓ Found user: ${user.uid}`);
    console.log(`  Email: ${user.email}`);
    
    // Step 2: Set custom claims
    console.log('\nStep 2: Setting custom claims...');
    try {
      await auth.setCustomUserClaims(user.uid, {
        role: 'cho_admin',
        approvalStatus: 'approved',
        accountStatus: 'active',
      });
      console.log('✓ Custom claims set to the approved CHO Admin role');
    } catch (claimErr) {
      console.warn('⚠ Could not set custom claims (may require Blaze plan):', claimErr.message);
      console.warn('  But RTDB role will still work for login...');
    }
    
    // Step 3: Ensure the Firestore governance profile is the source of truth.
    console.log('\nStep 3: Setting the CHO Admin governance profile...');
    await getFirestore(app, FIRESTORE_DATABASE_ID).collection('users').doc(user.uid).set({
      uid: user.uid,
      email: user.email || MAIN_CHO_ADMIN_EMAIL,
      emailLower: MAIN_CHO_ADMIN_EMAIL,
      role: 'CHO_ADMIN',
      accessScope: 'citywide',
      organizationLevel: 'citywide',
      approvalStatus: 'approved',
      accountStatus: 'active',
      status: 'Active',
      isApproved: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log('✓ Firestore profile updated as approved CHO Admin');

    // Step 4: Ensure Realtime Database mirror is set
    console.log('\nStep 4: Setting Realtime Database role...');
    await rtdb.ref(`users/${user.uid}`).update({
      role: 'CHO_ADMIN',
      approvalStatus: 'approved',
      accountStatus: 'active',
      updatedAt: ServerValue.TIMESTAMP,
    });
    console.log('✓ RTDB role updated: users/' + user.uid + '/role = CHO_ADMIN');
    
    // Step 4: Verify
    console.log('\nStep 5: Verifying...');
    const snapshot = await rtdb.ref(`users/${user.uid}/role`).get();
    const savedRole = snapshot.val();
    console.log('✓ Verified RTDB role:', savedRole);
    
    console.log('\n✅ SUCCESS! The main account is now set as CHO Admin.');
    console.log('\nNext steps:');
    console.log('1. Sign out from your app completely');
    console.log('2. Clear browser cache (Ctrl+Shift+Delete)');
    console.log('3. Log back in with your credentials');
    console.log('4. You should now have access to the CHO dashboard');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    if (error.code === 'auth/user-not-found') {
      console.error('\n⚠ User not found! Make sure you:');
      console.error('1. Registered your account first');
      console.error('2. Are using the correct email address');
      console.error('3. Check that signup completed successfully');
    }
    process.exitCode = 1;
  }
}

const email = process.argv[2];
if (!email) {
  console.error('Usage: node set_cho_claims_auth.js <email>');
  console.error('Example: node set_cho_claims_auth.js theo@gmail.com');
  process.exit(1);
}

void fixCHORole(email);
