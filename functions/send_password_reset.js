const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const crypto = require('crypto');

// Restrict to the deployed app origins plus localhost for development,
// matching the CORS policy already used by the FastAPI backend
// (backend/app/api.py). "origin: true" previously reflected any caller's
// Origin header, which is inappropriate for an unauthenticated endpoint
// that triggers account-recovery emails.
const ALLOWED_ORIGINS = new Set([
  'https://capstone-c98f9.web.app',
  'https://capstone-c98f9.firebaseapp.com',
]);
const LOCALHOST_ORIGIN_PATTERN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;
const cors = require('cors')({
  origin: (origin, callback) => {
    if (!origin || ALLOWED_ORIGINS.has(origin) || LOCALHOST_ORIGIN_PATTERN.test(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Origin not allowed'));
    }
  },
});

if (!admin.apps.length) {
  admin.initializeApp();
}

// Server-side rate limiting for the password-reset flow. Firestore-backed
// (not in-memory) so the limit holds across concurrent/cold-started
// function instances. Password reset gets a much stricter budget than
// ordinary API endpoints because it is an unauthenticated, account-
// recovery-sensitive surface.
const RESET_REQUEST_COOLDOWN_MS = 60 * 1000; // min gap between codes for one email
const RESET_REQUEST_MAX_PER_WINDOW = 5; // max sends per email per window
const RESET_REQUEST_WINDOW_MS = 60 * 60 * 1000; // 1 hour

/**
 * Returns null if the request is allowed, or a retry-after-seconds number
 * if the caller must wait. Uses a Firestore transaction so concurrent
 * requests for the same email can't race past the limit.
 */
async function checkAndRecordResetRequestRate(email) {
  const limitRef = admin.firestore().collection('password_reset_rate_limits').doc(email);
  const now = Date.now();

  return admin.firestore().runTransaction(async (transaction) => {
    const snap = await transaction.get(limitRef);
    const data = snap.exists ? snap.data() : null;

    if (data && data.lastRequestAt && now - data.lastRequestAt < RESET_REQUEST_COOLDOWN_MS) {
      return Math.ceil((RESET_REQUEST_COOLDOWN_MS - (now - data.lastRequestAt)) / 1000);
    }

    let windowStart = data && data.windowStart ? data.windowStart : now;
    let windowCount = data && data.windowStart && now - data.windowStart < RESET_REQUEST_WINDOW_MS
      ? (data.windowCount || 0)
      : 0;

    if (windowCount >= RESET_REQUEST_MAX_PER_WINDOW) {
      return Math.ceil((windowStart + RESET_REQUEST_WINDOW_MS - now) / 1000);
    }

    if (windowCount === 0) {
      windowStart = now;
    }

    transaction.set(limitRef, {
      lastRequestAt: now,
      windowStart,
      windowCount: windowCount + 1,
    });

    return null;
  });
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

      // Server-side rate limit: strict cooldown + hourly cap per email.
      const retryAfterSeconds = await checkAndRecordResetRequestRate(email);
      if (retryAfterSeconds !== null) {
        res.set('Retry-After', String(retryAfterSeconds));
        return res.status(429).json({
          error: 'Too many reset requests. Please try again later.',
        });
      }

      // Generate verification code (6 digits) using a cryptographically
      // secure generator -- Math.random() is not suitable for a security
      // token, as it is not guaranteed to be a CSPRNG.
      const code = String(crypto.randomInt(100000, 1000000));
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
        // Never log the raw code -- only the failure itself. The account
        // existence check above already ran, so an honest failure response
        // here does not create a new enumeration signal.
        console.error('Error sending password reset email:', emailErr.message || emailErr);
        return res.status(502).json({
          error: 'Could not send the reset email right now. Please try again shortly.',
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

      if (typeof newPassword !== 'string' || newPassword.length < 8) {
        return res.status(400).json({
          error: 'Password must be at least 8 characters long.',
        });
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
