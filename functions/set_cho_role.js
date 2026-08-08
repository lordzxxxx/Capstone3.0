/**
 * set_cho_role.js
 *
 * Usage:
 * 1) Ensure you have a service account JSON and set:
 *    setx GOOGLE_APPLICATION_CREDENTIALS "C:\path\to\serviceAccount.json"
 *    (or on mac/linux: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json)
 * 2) From this folder run:
 *    node set_cho_role.js user@example.com
 *
 * The script will set a custom claim { role: 'CHO' } and write a `role` field
 * to Realtime Database path `users/{uid}` for easier client-side checks.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Simple CLI parsing: accepts email and optional --key <path-to-service-account.json>
let emailArg = null;
let keyPath = null;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--key' || a === '-k') {
    keyPath = args[i + 1];
    i++; // skip next
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

  // If GOOGLE_APPLICATION_CREDENTIALS is set, admin.initializeApp() will use it.
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp();
    console.log('Initialized admin using GOOGLE_APPLICATION_CREDENTIALS env var');
    return;
  }

  console.error('No credentials provided. Either set GOOGLE_APPLICATION_CREDENTIALS or pass --key <path>');
  process.exit(2);
}

async function setChoRoleByEmail(email) {
  if (!email) throw new Error('Email required. Usage: node set_cho_role.js <email> [--key path]');

  const user = await admin.auth().getUserByEmail(email);
  console.log('Found user:', user.uid, user.email);

  // Set custom claim
  await admin.auth().setCustomUserClaims(user.uid, { role: 'CHO' });
  console.log('Set custom claim role:CHO for', user.uid);

  // Also set Realtime Database users node
  await admin.database().ref(`users/${user.uid}`).update({ role: 'CHO' });
  console.log('Wrote users/{uid}/role = CHO in Realtime Database');
}

initAdmin();
const email = emailArg;
setChoRoleByEmail(email).then(() => {
  console.log('Done');
  process.exit(0);
}).catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
