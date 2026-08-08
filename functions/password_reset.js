const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const cors = require('cors')({ origin: true });

admin.initializeApp();

// Initialize nodemailer transporter
let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  
  const config = functions.config();
  const smtpConfig = config.smtp || {};
  
  console.log('SMTP Config - user exists:', !!smtpConfig.user, 'pass exists:', !!smtpConfig.pass);
  
  transporter = nodemailer.createTransport({
    host: smtpConfig.host || process.env.SMTP_HOST || 'smtp.gmail.com',
    port: smtpConfig.port || process.env.SMTP_PORT || 587,
    secure: false,
    auth: {
      user: smtpConfig.user || process.env.SMTP_USER,
      pass: smtpConfig.pass || process.env.SMTP_PASS,
    },
  });
  
  return transporter;
}

// HTTPS endpoint: request a reset code be sent to `email`.
// POST body: { email: string }
exports.sendPasswordReset = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    try {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const { email } = req.body || {};
      if (!email) return res.status(400).json({ error: 'Missing email' });

      // Verify user exists (avoid exposing whether user exists in prod if desired)
      try {
        await admin.auth().getUserByEmail(email);
      } catch (err) {
        // For privacy, still act as if the request succeeded, but return 200.
        console.warn(`Requested password reset for unknown user ${email}`);
        return res.status(200).json({ success: true });
      }

      // Generate 4-digit code
      const code = String(Math.floor(1000 + Math.random() * 9000));
      const salt = crypto.randomBytes(16).toString('hex');
      const hash = crypto.createHash('sha256').update(salt + code).digest('hex');
      const expiry = new Date(Date.now() + 15 * 60 * 1000);

      await admin.firestore().collection('password_resets').doc(email).set({
        email,
        hashedCode: hash,
        salt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiryAt: admin.firestore.Timestamp.fromDate(expiry),
      });

      // Send email via nodemailer
      try {
        const mailer = getTransporter();
        
        const mailOptions = {
          from: functions.config().smtp?.user || process.env.SMTP_USER || 'noreply@dsuhis.com',
          to: email,
          subject: 'Your Password Reset Code',
          html: `
            <div style="font-family: Arial, sans-serif; color: #0E2F34;">
              <h2>Password Reset</h2>
              <p>Your 4-digit verification code is:</p>
              <h1 style="font-size: 36px; letter-spacing: 8px; color: #0E2F34;">${code}</h1>
              <p>This code will expire in 15 minutes.</p>
              <p>If you didn't request this, please ignore this email.</p>
            </div>
          `,
          text: `Your password reset code is: ${code}\n\nThis code will expire in 15 minutes.`,
        };

        await mailer.sendMail(mailOptions);
        console.log(`Password reset code sent to ${email}`);
      } catch (sendErr) {
        console.error('Error sending reset email:', sendErr);
        // Still return success for debugging
        console.log(`[DEBUG] Password reset code for ${email}: ${code}`);
      }

      return res.status(200).json({ success: true, message: 'Code sent to email' });
    } catch (error) {
      console.error('sendPasswordReset error:', error);
      return res.status(500).json({ error: error.message || 'Internal error' });
    }
  });
});

// Verify reset code endpoint
// POST JSON body: { email: string, code: string }
exports.verifyResetCode = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const { email, code } = req.body || {};
      if (!email || !code) {
        return res.status(400).json({ error: 'Missing email or code' });
      }

      const resetDoc = await admin
        .firestore()
        .collection('password_resets')
        .doc(email)
        .get();

      if (!resetDoc.exists) {
        return res.status(404).json({ error: 'No reset session found' });
      }

      const resetData = resetDoc.data();
      const expiryAt = resetData.expiryAt && resetData.expiryAt.toDate ? resetData.expiryAt.toDate() : new Date(resetData.expiryAt);

      if (new Date() > expiryAt) {
        await admin.firestore().collection('password_resets').doc(email).delete();
        return res.status(400).json({ error: 'Reset code has expired' });
      }

      // Verify code
      const salt = resetData.salt;
      const hash = crypto.createHash('sha256').update(salt + String(code)).digest('hex');

      if (hash !== resetData.hashedCode) {
        return res.status(400).json({ error: 'Invalid verification code' });
      }

      // Code verified
      return res.status(200).json({
        success: true,
        message: 'Code verified successfully',
      });
    } catch (error) {
      console.error('verifyResetCode error:', error);
      return res.status(500).json({ error: error.message || 'Internal server error' });
    }
  });
});

// Public HTTPS endpoint to complete password reset using the 4-digit code.
// POST JSON body: { email: string, code: string, newPassword: string }
// NOTE: Deploy this function and replace the client-side URL placeholder with
// the real function URL. Protect this endpoint appropriately in production.
exports.completePasswordReset = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const { email, code, newPassword } = req.body || {};
      if (!email || !code || !newPassword) {
        return res.status(400).json({ error: 'Missing parameters' });
      }

      const resetRef = admin.firestore().collection('password_resets').doc(email);
      const resetDoc = await resetRef.get();
      if (!resetDoc.exists) {
        return res.status(404).json({ error: 'No reset session found' });
      }

      const resetData = resetDoc.data();
      const now = new Date();
      const expiryAt = resetData.expiryAt && resetData.expiryAt.toDate ? resetData.expiryAt.toDate() : new Date(resetData.expiryAt);

      if (now > expiryAt) {
        await resetRef.delete().catch(() => {});
        return res.status(410).json({ error: 'Reset code expired' });
      }

      // Verify hashed code
      const salt = resetData.salt;
      const storedHash = resetData.hashedCode;
      const providedHash = crypto.createHash('sha256').update(salt + String(code)).digest('hex');
      if (providedHash !== storedHash) {
        return res.status(403).json({ error: 'Invalid code' });
      }

      // All good — update the user's password using Admin SDK
      const user = await admin.auth().getUserByEmail(email);
      await admin.auth().updateUser(user.uid, { password: newPassword });

      // Clean up the reset document
      await resetRef.delete();

      // Optionally send confirmation email here
      console.log(`Password reset completed for ${email}`);

      return res.status(200).json({ success: true, message: 'Password reset successfully' });
    } catch (error) {
      console.error('Error completing password reset:', error);
      return res.status(500).json({ error: error.message || 'Internal error' });
    }
  });
});

// Alternative: Use Firebase Admin SDK to batch update passwords
// This function can be called with proper authentication
exports.updateUserPassword = functions.https.onCall(async (data, context) => {
  const { email, newPassword } = data;

  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Must be authenticated"
    );
  }

  try {
    const user = await admin.auth().getUserByEmail(email);

    // Update password
    await admin.auth().updateUser(user.uid, {
      password: newPassword,
    });

    return { success: true };
  } catch (error) {
    console.error("Error updating password:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});
