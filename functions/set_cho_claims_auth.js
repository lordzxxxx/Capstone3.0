/**
 * set_cho_claims_auth.js
 * 
 * Workaround to set custom claims using authenticated Firebase CLI
 * This directly modifies the Realtime Database to ensure role is set
 * 
 * Usage:
 *   firebase login (already done)
 *   node set_cho_claims_auth.js theocaliao@gmail.com
 */

const admin = require('firebase-admin');

// Initialize with default credentials from authenticated Firebase CLI
const serviceAccount = require('./serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'capstone-c98f9',
  databaseURL: 'https://capstone-c98f9-default-rtdb.firebaseio.com'
});

async function fixCHORole(email) {
  console.log(`\nAttempting to fix CHO role for: ${email}\n`);
  
  try {
    // Step 1: Get user by email
    console.log('Step 1: Looking up user by email...');
    const user = await admin.auth().getUserByEmail(email);
    console.log(`✓ Found user: ${user.uid}`);
    console.log(`  Email: ${user.email}`);
    
    // Step 2: Set custom claims
    console.log('\nStep 2: Setting custom claims...');
    try {
      await admin.auth().setCustomUserClaims(user.uid, { role: 'CHO' });
      console.log('✓ Custom claims set to: { role: "CHO" }');
    } catch (claimErr) {
      console.warn('⚠ Could not set custom claims (may require Blaze plan):', claimErr.message);
      console.warn('  But RTDB role will still work for login...');
    }
    
    // Step 3: Ensure Realtime Database role is set
    console.log('\nStep 3: Setting Realtime Database role...');
    await admin.database().ref(`users/${user.uid}`).update({
      role: 'CHO',
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    });
    console.log('✓ RTDB role updated: users/' + user.uid + '/role = CHO');
    
    // Step 4: Verify
    console.log('\nStep 4: Verifying...');
    const snapshot = await admin.database().ref(`users/${user.uid}/role`).get();
    const savedRole = snapshot.val();
    console.log('✓ Verified RTDB role:', savedRole);
    
    console.log('\n✅ SUCCESS! Your account is now set as CHO.');
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
  } finally {
    process.exit(0);
  }
}

const email = process.argv[2];
if (!email) {
  console.error('Usage: node set_cho_claims_auth.js <email>');
  console.error('Example: node set_cho_claims_auth.js theocaliao@gmail.com');
  process.exit(1);
}

fixCHORole(email);
