/**
 * create_cho_user.js
 *
 * Creates a Firebase Auth user (or uses existing), sets custom claim { role: 'CHO' },
 * writes/merges `users/{uid}/role = 'CHO'` in Realtime Database, and optionally generates a
 * password reset link to let the user set their password.
 *
 * Usage examples (from functions/):
 *  node create_cho_user.js cho@example.com --key ./service-account.json --password <StrongPassword> --send-reset
 *  node create_cho_user.js cho@example.com --key ./service-account.json --send-reset
 *  # Or use env var:
 *  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\service-account.json"
 *  node create_cho_user.js cho@example.com --send-reset
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const { assertStrongPassword } = require('./password_policy');

// CLI args: email [--key path] [--password pwd] [--send-reset]
let emailArg = null;
let keyPath = null;
let password = null;
let sendReset = false;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--key' || a === '-k') {
    keyPath = args[i + 1];
    i++;
  } else if (a === '--password' || a === '-p') {
    password = args[i + 1];
    i++;
  } else if (a === '--send-reset' || a === '-r') {
    sendReset = true;
  } else if (!emailArg) {
    emailArg = a;
  }
}

function initAdmin() {
  if (keyPath) {
    const full = path.isAbsolute(keyPath) ? keyPath : path.join(__dirname, keyPath);
    if (!fs.existsSync(full)) {
      console.error('Service account JSON not found at', full);
      process.exit(2);
    }
    const key = require(full);
    admin.initializeApp({
      credential: admin.credential.cert(key),
      projectId: key.project_id,
      databaseURL: process.env.FIREBASE_DATABASE_URL || key.databaseURL || `https://${key.project_id}-default-rtdb.firebaseio.com`,
    });
    console.log('Initialized admin with key', full);
    return;
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp();
    console.log('Initialized admin using GOOGLE_APPLICATION_CREDENTIALS env var');
    return;
  }

  console.error('No credentials provided. Either set GOOGLE_APPLICATION_CREDENTIALS or pass --key <path>');
  process.exit(2);
}

async function createOrUpdateCho(email) {
  if (!email) throw new Error('Email required. Usage: node create_cho_user.js <email> [--password pass] [--key path] [--send-reset]');
  if (password) assertStrongPassword(password);

  // Try to find existing user
  let userRecord = null;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
    console.log('Existing user found:', userRecord.uid);
  } catch (e) {
    // user not found -> create
    console.log('User not found, creating new user for', email);
    const createReq = { email };
    if (password) createReq.password = password;
    userRecord = await admin.auth().createUser(createReq);
    console.log('Created user:', userRecord.uid);
  }

  // Set custom claim for role CHO
  await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'CHO' });
  console.log('Set custom claim role:CHO for', userRecord.uid);

  // Write Realtime Database users node
  await admin.database().ref(`users/${userRecord.uid}`).update({ role: 'CHO', email: email });
  console.log('Wrote users/{uid}/role = CHO in Realtime Database');

  // Optionally generate password reset link
  let resetLink = null;
  if (sendReset) {
    try {
      resetLink = await admin.auth().generatePasswordResetLink(email);
      console.log('Generated password reset link (share securely):');
      console.log(resetLink);
    } catch (e) {
      console.error('Failed to generate password reset link:', e);
    }
  }

  return { uid: userRecord.uid, resetLink };
}

initAdmin();
const email = emailArg;
createOrUpdateCho(email).then((res) => {
  console.log('Done. UID:', res.uid);
  if (res.resetLink) console.log('Reset link:', res.resetLink);
  process.exit(0);
}).catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
