const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const crypto = require('crypto');
const {sendSystemEmail} = require('./mailer');
const {
  assertStrongPassword,
  MAXIMUM_PASSWORD_LENGTH,
} = require('./password_policy');

// Restrict to the deployed app origins plus localhost for development,
// matching the CORS policy already used by the FastAPI backend
// (backend/app/api.py). "origin: true" previously reflected any caller's
// Origin header, which is inappropriate for an unauthenticated endpoint
// that triggers account-recovery emails.
const ALLOWED_ORIGINS = new Set([
  'https://capstone-c98f9.web.app',
  'https://capstone-c98f9.firebaseapp.com',
  ...(process.env.WEB_ALLOWED_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim().replace(/\/$/, ''))
    .filter(Boolean),
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
const FIRESTORE_DATABASE_ID = process.env.FIRESTORE_DATABASE_ID || 'capstone-c98f9';
const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);

// Server-side rate limiting for the password-reset flow. Firestore-backed
// (not in-memory) so the limit holds across concurrent/cold-started
// function instances. Password reset gets a much stricter budget than
// ordinary API endpoints because it is an unauthenticated, account-
// recovery-sensitive surface.
const RESET_REQUEST_COOLDOWN_MS = 60 * 1000; // min gap between codes for one email
const RESET_REQUEST_MAX_PER_WINDOW = 5; // max sends per email per window
const RESET_REQUEST_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RESET_IP_COOLDOWN_MS = 5 * 1000;
const RESET_IP_MAX_PER_WINDOW = 20;
const RESET_IP_WINDOW_MS = 60 * 60 * 1000;
const INVALID_RESET_MESSAGE = 'The reset request is invalid or expired. Request a new code.';

function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

function isValidEmail(email) {
  return email.length <= 320 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function htmlEscape(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function hashRateLimitKey(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function getClientIp(req) {
  return String(req.ip || 'unknown').trim().slice(0, 128);
}

async function writeSecurityEvent(event, details = {}) {
  try {
    await db.collection('audit_logs').add({
      event,
      source: 'password-reset',
      ...details,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    // Audit logging must never turn a valid recovery request into a failure,
    // but the operational log should make the missing audit write visible.
    console.error('Security audit write failed', {
      event,
      error: error.message || String(error),
    });
  }
}

function retryAfterFor(data, now, cooldownMs, maxPerWindow, windowMs) {
  if (!data) return null;
  if (data.lastRequestAt && now - data.lastRequestAt < cooldownMs) {
    return Math.ceil((cooldownMs - (now - data.lastRequestAt)) / 1000);
  }
  const windowStart = data.windowStart || now;
  const windowCount = data.windowCount || 0;
  if (now - windowStart < windowMs && windowCount >= maxPerWindow) {
    return Math.ceil((windowStart + windowMs - now) / 1000);
  }
  return null;
}

/**
 * Returns null if the request is allowed, or a retry-after-seconds number
 * if the caller must wait. Uses a Firestore transaction so concurrent
 * requests for the same email can't race past the limit.
 */
async function checkAndRecordResetRequestRate(email, clientIp) {
  const collection = db.collection('password_reset_rate_limits');
  const emailRef = collection.doc(`email_${hashRateLimitKey(email)}`);
  const ipRef = collection.doc(`ip_${hashRateLimitKey(clientIp)}`);
  const now = Date.now();

  return db.runTransaction(async (transaction) => {
    const emailSnapshot = await transaction.get(emailRef);
    const ipSnapshot = await transaction.get(ipRef);
    const emailData = emailSnapshot.exists ? emailSnapshot.data() : null;
    const ipData = ipSnapshot.exists ? ipSnapshot.data() : null;

    const emailRetry = retryAfterFor(
      emailData,
      now,
      RESET_REQUEST_COOLDOWN_MS,
      RESET_REQUEST_MAX_PER_WINDOW,
      RESET_REQUEST_WINDOW_MS,
    );
    const ipRetry = retryAfterFor(
      ipData,
      now,
      RESET_IP_COOLDOWN_MS,
      RESET_IP_MAX_PER_WINDOW,
      RESET_IP_WINDOW_MS,
    );
    if (emailRetry !== null || ipRetry !== null) {
      return Math.max(emailRetry || 0, ipRetry || 0);
    }

    const nextWindow = (data, windowMs) => (
      data && data.windowStart && now - data.windowStart < windowMs
        ? { windowStart: data.windowStart, windowCount: data.windowCount || 0 }
        : { windowStart: now, windowCount: 0 }
    );
    const emailWindow = nextWindow(emailData, RESET_REQUEST_WINDOW_MS);
    const ipWindow = nextWindow(ipData, RESET_IP_WINDOW_MS);

    transaction.set(emailRef, {
      lastRequestAt: now,
      windowStart: emailWindow.windowStart,
      windowCount: emailWindow.windowCount + 1,
    });
    transaction.set(ipRef, {
      lastRequestAt: now,
      windowStart: ipWindow.windowStart,
      windowCount: ipWindow.windowCount + 1,
    });

    return null;
  });
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

      const { email: rawEmail } = req.body || {};
      if (!rawEmail || typeof rawEmail !== 'string') {
        return res.status(400).json({ error: 'Missing or invalid email' });
      }
      const email = normalizeEmail(rawEmail);
      if (!isValidEmail(email)) {
        return res.status(400).json({ error: 'Missing or invalid email' });
      }

      // Apply both email- and IP-based throttles before checking whether the
      // account exists. This prevents attackers from bypassing the limiter by
      // submitting unknown addresses and makes the endpoint safer to expose.
      const retryAfterSeconds = await checkAndRecordResetRequestRate(
        email,
        getClientIp(req),
      );
      if (retryAfterSeconds !== null) {
        res.set('Retry-After', String(retryAfterSeconds));
        return res.status(429).json({
          error: 'Too many reset requests. Please try again later.',
        });
      }

      // Verify user exists
      let user;
      try {
        user = await admin.auth().getUserByEmail(email);
      } catch (err) {
        // Don't leak whether user exists
        console.warn('Password reset requested for an unknown address', {
          emailHash: hashRateLimitKey(email),
        });
        await writeSecurityEvent('password_reset_requested', {
          emailHash: hashRateLimitKey(email),
          accountFound: false,
        });
        return res.status(200).json({
          success: true,
          message: 'If an account exists, a reset link will be sent.',
        });
      }

      await writeSecurityEvent('password_reset_requested', {
        emailHash: hashRateLimitKey(email),
        accountFound: true,
        uid: user.uid,
      });

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
      await db
        .collection('password_resets')
        .doc(email)
        .set({
          email,
          hashedCode: hash,
          salt,
          createdAt: FieldValue.serverTimestamp(),
          expiryAt: admin.firestore.Timestamp.fromDate(expiryTime),
          attempts: 0,
          verified: false,
        });

      // Send through the fixed AI-DSUHIS system identity. The raw code is
      // never written to logs or returned by the endpoint.
      try {
        const resetLink = `${process.env.APP_URL || 'https://your-app.com'}/reset-password?email=${encodeURIComponent(
          email
        )}&code=${code}`;
        const mailResult = await sendSystemEmail({
          to: email,
          subject: 'Password Reset Request – AI-DSUHIS',
          html: `<p>Hi ${htmlEscape(user.displayName || user.email || 'there')},</p><p>Your AI-DSUHIS password reset code is:</p><p style="font-size:24px;font-weight:700;letter-spacing:4px;">${code}</p><p>This code expires in 15 minutes. Never share it with anyone.</p>`,
          text: `Your AI-DSUHIS password reset code is: ${code}\n\nThis code will expire in 15 minutes. Never share it with anyone.`,
        });
        if (!mailResult.sent) {
          throw new Error(mailResult.reason || 'system_mailer_unavailable');
        }
        console.log('Password reset email sent', {
          emailHash: hashRateLimitKey(email),
        });

        return res.status(200).json({
          success: true,
          message: 'If an account exists, a reset link will be sent.',
        });
      } catch (emailErr) {
        // Never log the raw code -- only the failure itself. The account
        // existence check above already ran, so an honest failure response
        // here does not create a new enumeration signal.
        console.error('Error sending password reset email:', emailErr.message || emailErr);
        // Keep the response indistinguishable from the unknown-account path;
        // otherwise a mailer failure would disclose that the address exists.
        return res.status(200).json({
          success: true,
          message: 'If an account exists, a reset link will be sent.',
        });
      }
    } catch (error) {
      console.error('sendPasswordResetEmail error:', error);
      return res
        .status(500)
        .json({
          error: 'Password reset is temporarily unavailable. Please try again later.',
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

      const { email: rawEmail, code } = req.body || {};
      if (!rawEmail || typeof rawEmail !== 'string' || !code) {
        return res.status(400).json({ error: 'Missing email or code' });
      }
      const email = normalizeEmail(rawEmail);
      if (typeof code !== 'string' || !/^\d{6}$/.test(code)) {
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      const resetDoc = await db
        .collection('password_resets')
        .doc(email)
        .get();

      if (!resetDoc.exists) {
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      const resetData = resetDoc.data();

      // Check expiry
      const expiryAt = resetData.expiryAt.toDate();
      if (new Date() > expiryAt) {
        await db
          .collection('password_resets')
          .doc(email)
          .delete();
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      // Check attempts
      if ((resetData.attempts || 0) >= 5) {
        await db
          .collection('password_resets')
          .doc(email)
          .delete();
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      if (resetData.verified) {
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      // Verify code
      const salt = resetData.salt;
      const hash = crypto
        .createHash('sha256')
        .update(salt + code)
        .digest('hex');

      if (hash !== resetData.hashedCode) {
        // Increment attempts
        await db
          .collection('password_resets')
          .doc(email)
          .update({
            attempts: (resetData.attempts || 0) + 1,
          });
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      // Code is valid - generate session token
      const sessionToken = crypto.randomBytes(32).toString('hex');
      await db
        .collection('password_resets')
        .doc(email)
        .update({
          verified: true,
          sessionToken,
          verifiedAt: FieldValue.serverTimestamp(),
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
          error: 'Password reset is temporarily unavailable. Please try again later.',
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

      const { email: rawEmail, sessionToken, newPassword } = req.body || {};
      if (
        !rawEmail ||
        typeof rawEmail !== 'string' ||
        typeof sessionToken !== 'string' ||
        !newPassword
      ) {
        return res.status(400).json({ error: 'Missing required parameters' });
      }
      const email = normalizeEmail(rawEmail);

      if (!/^[a-f0-9]{64}$/i.test(sessionToken)) {
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }
      if (
        typeof newPassword !== 'string'
      ) {
        return res.status(400).json({
          error: 'Password does not meet the password policy.',
        });
      }
      try {
        assertStrongPassword(newPassword);
      } catch (_) {
        return res.status(400).json({
          error: `Password must be 8 to ${MAXIMUM_PASSWORD_LENGTH} characters and include uppercase, lowercase, a number, and a special character.`,
        });
      }

      const resetDoc = await db
        .collection('password_resets')
        .doc(email)
        .get();

      if (!resetDoc.exists) {
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      const resetData = resetDoc.data();

      // Check verification and session token
      const storedToken = Buffer.from(String(resetData.sessionToken || ''), 'utf8');
      const providedToken = Buffer.from(sessionToken, 'utf8');
      const validToken = storedToken.length === providedToken.length &&
        storedToken.length > 0 &&
        crypto.timingSafeEqual(storedToken, providedToken);
      if (!resetData.verified || !validToken) {
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      // Check expiry
      const expiryAt = resetData.expiryAt.toDate();
      if (new Date() > expiryAt) {
        await db
          .collection('password_resets')
          .doc(email)
          .delete();
        return res.status(400).json({ error: INVALID_RESET_MESSAGE });
      }

      // Update password in Firebase Auth
      try {
        const user = await admin.auth().getUserByEmail(email);
        await admin.auth().updateUser(user.uid, {
          password: newPassword,
        });
        // Invalidate refresh tokens so other devices must authenticate again.
        // The AI API also verifies revoked Firebase ID tokens.
        await admin.auth().revokeRefreshTokens(user.uid);

        await writeSecurityEvent('password_reset_completed', {
          emailHash: hashRateLimitKey(email),
          uid: user.uid,
        });

        // Delete reset document
        await db
          .collection('password_resets')
          .doc(email)
          .delete();

        console.log('Password reset completed', {
          uid: user.uid,
          emailHash: hashRateLimitKey(email),
        });
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
          error: 'Password reset is temporarily unavailable. Please try again later.',
        });
    }
  });
});
