/**
 * create_cho_user.js
 *
 * Bootstraps the single CHO Admin account. Ordinary CHO and doctor accounts
 * must be created by the callable CHO Admin workflow in account_policy.js.
 *
 * Usage examples (from functions/):
 *  node create_cho_user.js theo@gmail.com --key ./service-account.json --send-reset
 *  # Or use env var:
 *  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\service-account.json"
 *  node create_cho_user.js theo@gmail.com --send-reset
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// CLI args: theo@gmail.com [--key path] [--send-reset]
let emailArg = null;
let keyPath = null;
let sendReset = false;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--key' || a === '-k') {
    keyPath = args[i + 1];
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
  if (email !== 'theo@gmail.com') {
    throw new Error('This bootstrap utility only provisions theo@gmail.com.');
  }

  // Try to find existing user
  let userRecord = null;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
    console.log('Existing user found:', userRecord.uid);
  } catch (e) {
    // user not found -> create
    console.log('User not found, creating new user for', email);
    userRecord = await admin.auth().createUser({ email, disabled: false });
    console.log('Created user:', userRecord.uid);
  }

  await admin.auth().setCustomUserClaims(userRecord.uid, {
    role: 'CHO_ADMIN',
    approvalStatus: 'approved',
    accountStatus: 'active',
  });
  console.log('Set custom claim role:CHO_ADMIN for', userRecord.uid);

  // Write Realtime Database users node
  await admin.database().ref(`users/${userRecord.uid}`).update({
    role: 'CHO_ADMIN',
    email,
    approvalStatus: 'approved',
    accountStatus: 'active',
  });
  console.log('Wrote the approved CHO Admin mirror');

  // Optionally generate password reset link
  let resetLink = null;
  if (sendReset) {
    try {
      resetLink = await admin.auth().generatePasswordResetLink(email);
      const { sendSystemEmail } = require('./mailer');
      await sendSystemEmail({
        to: email,
        subject: 'Your AI-DSUHIS Account Is Ready',
        text: `Your AI-DSUHIS CHO Admin account is ready. Set your password securely: ${resetLink}`,
        html: `<p>Your AI-DSUHIS CHO Admin account is ready.</p><p><a href="${resetLink}">Set your password securely</a></p>`,
      });
      console.log('Sent a secure password-setup email from the system mailer');
    } catch (e) {
      console.error('Failed to generate password reset link:', e);
    }
  }

  return { uid: userRecord.uid };
}

initAdmin();
const email = emailArg;
createOrUpdateCho(email).then((res) => {
  console.log('Done. UID:', res.uid);
  process.exit(0);
}).catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
