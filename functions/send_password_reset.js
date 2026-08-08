const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const cors = require('cors')({ origin: true });

if (!admin.apps.length) {
  admin.initializeApp();
}

// Get SMTP configuration from Firebase functions config
// Set these with: firebase functions:config:set smtp.user="..." smtp.pass="..." smtp.host="..." smtp.port="..."
let transporter = null;

function initializeMailer() {
  if (transporter) return transporter;

  const config = functions.config();
  const smtpConfig = config.smtp || {};

  // If SMTP is not configured, try using Gmail or provide clear error
  if (!smtpConfig.user || !smtpConfig.pass) {
    console.warn('SMTP configuration incomplete. Set firebase config with:');
    console.warn('firebase functions:config:set smtp.user="your-email@gmail.com"');
    console.warn('firebase functions:config:set smtp.pass="your-app-password"');
    // Still try to create with defaults (may fail at runtime)
  }

  transporter = nodemailer.createTransport({
    host: smtpConfig.host || 'smtp.gmail.com',
    port: smtpConfig.port || 587,
    secure: smtpConfig.secure || false, // true for 465, false for 587
    auth: {
      user: smtpConfig.user || process.env.SMTP_USER,
      pass: smtpConfig.pass || process.env.SMTP_PASS,
    },
  });

  return transporter;
}

/**
 * HTTP endpoint to send password reset email
 * POST /sendPasswordResetEmail
 * Body: { email: string }
 */
exports.sendPasswordResetEmail = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const { email } = req.body || {};
      if (!email || typeof email !== 'string') {
        return res.status(400).json({ error: 'Missing or invalid email' });
      }

      // Verify user exists
      let user;
      try {
        user = await admin.auth().getUserByEmail(email);
      } catch (err) {
        // Don't leak whether user exists
        console.warn(`Password reset requested for unknown email: ${email}`);
        return res.status(200).json({
          success: true,
          message: 'If an account exists, a reset link will be sent',
        });
      }

      // Generate verification code (6 digits)
      const code = String(Math.floor(100000 + Math.random() * 900000));
      const salt = crypto.randomBytes(16).toString('hex');
      const hash = crypto
        .createHash('sha256')
        .update(salt + code)
        .digest('hex');
      const expiryTime = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

      // Store code in Firestore
      await admin
        .firestore()
        .collection('password_resets')
        .doc(email)
        .set({
          email,
          hashedCode: hash,
          salt,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiryAt: admin.firestore.Timestamp.fromDate(expiryTime),
          attempts: 0,
          verified: false,
        });

      // Send email via nodemailer
      try {
        const mailer = initializeMailer();

        const resetLink = `${process.env.APP_URL || 'https://your-app.com'}/reset-password?email=${encodeURIComponent(
          email
        )}&code=${code}`;

        const mailOptions = {
          from: functions.config().smtp?.user || 'noreply@dsuhis.com',
          to: email,
          subject: 'Password Reset Request - DSUHIS',
          html: `
            <!DOCTYPE html>
            <html>
              <head>
                <meta charset="UTF-8">
                <style>
                  body { font-family: Arial, sans-serif; background-color: #f5f5f5; }
                  .container { max-width: 600px; margin: 20px auto; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
                  .header { background: linear-gradient(135deg, #00A8B5 0%, #1E5A7A 100%); color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
                  .header h2 { margin: 0; font-size: 24px; }
                  .content { padding: 20px; color: #333; }
                  .code { background: #f0f0f0; border: 2px solid #00A8B5; border-radius: 4px; padding: 15px; text-align: center; margin: 20px 0; font-size: 24px; font-weight: bold; letter-spacing: 4px; }
                  .button { display: inline-block; background: #00A8B5; color: white; padding: 12px 30px; border-radius: 4px; text-decoration: none; margin-top: 10px; }
                  .footer { background: #f9f9f9; border-top: 1px solid #eee; padding: 15px; text-align: center; font-size: 12px; color: #666; }
                  .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
                </style>
              </head>
              <body>
                <div class="container">
                  <div class="header">
                    <h2>Password Reset Request</h2>
                  </div>
                  <div class="content">
                    <p>Hi ${user.displayName || user.email},</p>
                    <p>We received a request to reset your password for your DSUHIS account. If you didn't make this request, you can ignore this email.</p>
                    
                    <p><strong>Your verification code:</strong></p>
                    <div class="code">${code}</div>
                    
                    <p>This code will expire in <strong>15 minutes</strong>.</p>
                    
                    <p>Enter this code in the password reset screen of the DSUHIS app to proceed with resetting your password.</p>
                    
                    <div class="warning">
                      <strong>Security Note:</strong> Never share this code with anyone. DSUHIS staff will never ask for your password or verification code.
                    </div>
                    
                    <p>If you need further assistance, please contact our support team.</p>
                  </div>
                  <div class="footer">
                    <p>© 2026 DSUHIS - Smart Health Integration System</p>
                    <p>This is an automated email. Please do not reply to this message.</p>
                  </div>
                </div>
              </body>
            </html>
          `,
          text: `Your password reset code is: ${code}\n\nThis code will expire in 15 minutes.`,
        };

        await mailer.sendMail(mailOptions);
        console.log(`Password reset email sent to ${email}`);

        return res.status(200).json({
          success: true,
          message: 'Password reset code sent to your email',
          email: email,
        });
      } catch (emailErr) {
        console.error('Error sending email via nodemailer:', emailErr);
        // Still return success but log the code for debugging
        console.log(`[DEBUG] Password reset code for ${email}: ${code}`);
        return res.status(200).json({
          success: true,
          message: 'If email fails, check with admin for reset code',
          debug: process.env.NODE_ENV === 'development' ? code : undefined,
        });
      }
    } catch (error) {
      console.error('sendPasswordResetEmail error:', error);
      return res
        .status(500)
        .json({
          error: error.message || 'Internal server error',
        });
    }
  });
});

/**
 * Verify reset code and mark user as verified
 * POST /verifyResetCode
 * Body: { email: string, code: string }
 */
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
        return res
          .status(404)
          .json({
            error: 'No reset request found for this email',
          });
      }

      const resetData = resetDoc.data();

      // Check expiry
      const expiryAt = resetData.expiryAt.toDate();
      if (new Date() > expiryAt) {
        await admin
          .firestore()
          .collection('password_resets')
          .doc(email)
          .delete();
        return res
          .status(400)
          .json({
            error: 'Reset code has expired',
          });
      }

      // Check attempts
      if ((resetData.attempts || 0) >= 5) {
        await admin
          .firestore()
          .collection('password_resets')
          .doc(email)
          .delete();
        return res
          .status(429)
          .json({
            error: 'Too many attempts. Request a new reset code.',
          });
      }

      // Verify code
      const salt = resetData.salt;
      const hash = crypto
        .createHash('sha256')
        .update(salt + code)
        .digest('hex');

      if (hash !== resetData.hashedCode) {
        // Increment attempts
        await admin
          .firestore()
          .collection('password_resets')
          .doc(email)
          .update({
            attempts: (resetData.attempts || 0) + 1,
          });
        return res
          .status(400)
          .json({
            error: 'Invalid verification code',
          });
      }

      // Code is valid - generate session token
      const sessionToken = crypto.randomBytes(32).toString('hex');
      await admin
        .firestore()
        .collection('password_resets')
        .doc(email)
        .update({
          verified: true,
          sessionToken,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      return res.status(200).json({
        success: true,
        message: 'Code verified successfully',
        sessionToken,
      });
    } catch (error) {
      console.error('verifyResetCode error:', error);
      return res
        .status(500)
        .json({
          error: error.message || 'Internal server error',
        });
    }
  });
});

/**
 * Complete password reset
 * POST /completePasswordReset
 * Body: { email: string, sessionToken: string, newPassword: string }
 */
exports.completePasswordReset = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    try {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const { email, sessionToken, newPassword } = req.body || {};
      if (!email || !sessionToken || !newPassword) {
        return res.status(400).json({ error: 'Missing required parameters' });
      }

      const resetDoc = await admin
        .firestore()
        .collection('password_resets')
        .doc(email)
        .get();

      if (!resetDoc.exists) {
        return res
          .status(404)
          .json({
            error: 'No reset session found',
          });
      }

      const resetData = resetDoc.data();

      // Check verification and session token
      if (!resetData.verified || resetData.sessionToken !== sessionToken) {
        return res
          .status(403)
          .json({
            error: 'Invalid or expired session',
          });
      }

      // Check expiry
      const expiryAt = resetData.expiryAt.toDate();
      if (new Date() > expiryAt) {
        await admin
          .firestore()
          .collection('password_resets')
          .doc(email)
          .delete();
        return res
          .status(400)
          .json({
            error: 'Reset session has expired',
          });
      }

      // Update password in Firebase Auth
      try {
        const user = await admin.auth().getUserByEmail(email);
        await admin.auth().updateUser(user.uid, {
          password: newPassword,
        });

        // Delete reset document
        await admin
          .firestore()
          .collection('password_resets')
          .doc(email)
          .delete();

        console.log(`Password reset completed for ${email}`);
        return res.status(200).json({
          success: true,
          message: 'Password reset successfully',
        });
      } catch (authErr) {
        console.error('Error updating password:', authErr);
        return res
          .status(500)
          .json({
            error: 'Failed to update password',
          });
      }
    } catch (error) {
      console.error('completePasswordReset error:', error);
      return res
        .status(500)
        .json({
          error: error.message || 'Internal server error',
        });
    }
  });
});
