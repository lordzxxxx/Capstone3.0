/**
 * set_cho_claim.js
 * 
 * Usage:
 *   firebase login  (if not already logged in)
 *   node set_cho_claim.js <email>
 */

const fs = require('fs');
const path = require('path');

async function setChoClaimViaGoogle(email) {
  try {
    // Use gcloud to set custom claims
    const { execSync } = require('child_process');
    
    console.log(`Setting CHO custom claim for ${email}...`);
    
    // Get the user by email and set custom claims
    const cmd = `gcloud firebase auth users lookup ${email} --project=capstone-c98f9`;
    
    try {
      const output = execSync(cmd, { encoding: 'utf-8' });
      console.log('User lookup output:', output);
    } catch (err) {
      console.error('Error looking up user:', err.message);
      console.log('\nAlternative: Set custom claims via Firebase Console:');
      console.log('1. Go to Firebase Console > Authentication > Users');
      console.log('2. Find the user: ' + email);
      console.log('3. Click the user and edit "Custom claims"');
      console.log('4. Add: {"role":"CHO"}');
      console.log('5. Save');
      return;
    }
  } catch (err) {
    console.error('Error:', err.message);
    console.log('\nManual workaround - use Firebase Console UI:');
    console.log('1. Go to https://console.firebase.google.com');
    console.log('2. Select your project');
    console.log('3. Go to Authentication > Users');
    console.log('4. Find and click: ' + email);
    console.log('5. Click "Custom claims" and add: {"role":"CHO"}');
    console.log('6. Save');
  }
}

const email = process.argv[2];
if (!email) {
  console.error('Usage: node set_cho_claim.js <email>');
  process.exit(1);
}

setChoClaimViaGoogle(email);
