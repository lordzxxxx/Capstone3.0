const functions = require('firebase-functions');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const nodemailer = require('nodemailer');
const { generateTemporaryPassword } = require('./password_policy');

const FIRESTORE_DATABASE_ID = 'capstone-c98f9';

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);

let transporter = null;

// Initialize Nodemailer transporter with SMTP configuration
function initializeTransporter() {
  if (transporter) return transporter;

  try {
    // Get SMTP configuration from Firebase Config or environment variables
    const smtpConfig = {
      host: process.env.SMTP_HOST || (functions.config && functions.config().smtp && functions.config().smtp.host),
      port: parseInt(process.env.SMTP_PORT || (functions.config && functions.config().smtp && functions.config().smtp.port) || '587'),
      secure: (process.env.SMTP_SECURE || (functions.config && functions.config().smtp && functions.config().smtp.secure) || 'false') === 'true', // true for 465, false for other ports
      auth: {
        user: process.env.SMTP_USER || (functions.config && functions.config().smtp && functions.config().smtp.user),
        pass: process.env.SMTP_PASSWORD || (functions.config && functions.config().smtp && functions.config().smtp.password),
      },
    };

    // Validate SMTP configuration
    if (!smtpConfig.auth.user || !smtpConfig.auth.pass) {
      console.warn('SMTP credentials not configured. Email sending will be disabled.');
      return null;
    }

    transporter = nodemailer.createTransport(smtpConfig);
    console.log('Nodemailer transporter initialized successfully');
    return transporter;
  } catch (err) {
    console.error('Failed to initialize Nodemailer transporter:', err);
    return null;
  }
}

/**
 * Firestore trigger: when an admin writes an `invitations` document, this function
 * will create the Auth user if missing, set a custom claim role (e.g., 'CHO'),
 * write the Realtime Database `users/{uid}` node with role/email, and generate a password reset link.
 * The invitation document will be updated with processing status and resetLink.
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
    await snap.ref.update({ status: 'error', error: 'missing email', processedAt: admin.firestore.FieldValue.serverTimestamp() });
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
      accessScope: 'citywide',
      organizationLevel: 'citywide',
      dataVisibilityStartAt: existingUserData.dataVisibilityStartAt || admin.firestore.FieldValue.serverTimestamp(),
      specialization,
      doctorSpecialization: specialization,
      specialty: specialization,
      availability,
      doctorAvailability: availability,
      approvalStatus: existingUserData.approvalStatus || 'approved',
      accountStatus: existingUserData.accountStatus || 'active',
      doctorRegistrySource: 'invitation_trigger',
      doctorRegisteredByUid: createdBy,
      createdAt: existingUserData.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await db.collection('registration_email_locks').doc(email).set({
      uid: userRecord.uid,
      email,
      emailLower: email,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: 'invitation-trigger',
    }, { merge: true });

    if (fullName) {
      await db.collection('registration_username_locks').doc(fullName.toLowerCase()).set({
        uid: userRecord.uid,
        username: fullName,
        usernameLower: fullName.toLowerCase(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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

    // Send email via SMTP/Nodemailer
    let emailSent = false;
    let emailError = null;
    
    const mailTransporter = initializeTransporter();
    if (mailTransporter) {
      try {
        const fromEmail = process.env.SMTP_FROM_EMAIL ||
          (functions.config && functions.config().smtp && (functions.config().smtp.fromEmail || functions.config().smtp.fromemail)) ||
          'noreply@example.com';
        const appName = 'Health Care System';

        const mailOptions = {
          from: fromEmail,
          to: email,
          subject: `You're Invited to ${appName}`,
          html: `
            <div style="font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px;">
              <div style="background-color: white; padding: 30px; border-radius: 10px; max-width: 600px; margin: 0 auto; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
                <h2 style="color: #0E2F34; margin-top: 0;">Welcome to ${appName}</h2>
                <p style="color: #555; font-size: 16px; line-height: 1.6;">
                  You have been invited to join <b>${appName}</b> with the role: <b>${requestedRole}</b>
                </p>
                <p style="color: #555; font-size: 16px; line-height: 1.6;">
                  Please click the button below to set your password and complete your registration:
                </p>
                <div style="text-align: center; margin: 30px 0;">
                  <a href="${resetLink}" style="background-color: #00A8B5; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; display: inline-block; font-weight: bold;">
                    Set Your Password
                  </a>
                </div>
                <p style="color: #999; font-size: 14px;">
                  Or copy and paste this link in your browser:<br>
                  <code style="background-color: #f0f0f0; padding: 2px 6px; border-radius: 3px;">${resetLink}</code>
                </p>
                <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">
                <p style="color: #999; font-size: 12px; text-align: center;">
                  If you did not request this invitation, please ignore this email or contact support.<br>
                  © 2026 ${appName}. All rights reserved.
                </p>
              </div>
            </div>
          `,
          text: `You were invited to ${appName} with role ${requestedRole}.\n\nSet your password using this link: ${resetLink}`,
        };

        // Send email
        const result = await mailTransporter.sendMail(mailOptions);
        emailSent = true;
        emailError = null;
        console.log('Invitation email sent successfully to', email, '- Message ID:', result.messageId);
        
        // Optionally log the response
        await snap.ref.update({ smtpResponse: { messageId: result.messageId, accepted: result.accepted } });
      } catch (sendErr) {
        emailSent = false;
        emailError = sendErr && sendErr.message ? sendErr.message : String(sendErr);
        console.error('Failed to send invitation email via SMTP:', sendErr);
        
        try {
          await snap.ref.update({ smtpError: emailError });
        } catch (updateErr) {
          console.warn('Failed to log SMTP error to invitation doc:', updateErr);
        }
      }
    } else {
      emailError = 'smtp_not_configured';
      console.warn('SMTP transporter not available; email not sent');
    }

    // Update invitation doc with result
    await snap.ref.update({
      status: 'processed',
      uid: userRecord.uid,
      resetLink: resetLink || null,
      emailSent: emailSent,
      emailError: emailError,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log('Processed invitation for', email);
  } catch (err) {
    console.error('processInvitation error:', err);
    await snap.ref.update({ status: 'error', error: err.message || String(err), processedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
});
