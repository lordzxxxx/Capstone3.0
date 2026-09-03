const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const crypto = require('crypto');
const {sendSystemEmail} = require('./mailer');
const {buildAccountOnboardingEmail} = require('./email_templates');
const {assertStrongPassword} = require('./password_policy');

if (!admin.apps.length) {
  admin.initializeApp();
}

const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const DOCTOR_SETUP_LINK_TTL_MS = 5 * 60 * 1000;
const DOCTOR_SETUP_REQUEST_COOLDOWN_MS = 60 * 1000;
const DOCTOR_SETUP_REQUEST_MAX_PER_WINDOW = 5;
const DOCTOR_SETUP_REQUEST_WINDOW_MS = 60 * 60 * 1000;
const DOCTOR_SETUP_IP_COOLDOWN_MS = 5 * 1000;
const DOCTOR_SETUP_IP_MAX_PER_WINDOW = 20;
const DOCTOR_SETUP_IP_WINDOW_MS = 60 * 60 * 1000;

const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function isValidEmail(email) {
  return email.length <= 320 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function hashValue(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function hashDoctorSetupToken(token) {
  return hashValue(token);
}

function appUrl() {
  return String(process.env.APP_URL || 'https://www.ai-dsuhis.com').replace(/\/$/, '');
}

function doctorSetupUrl(token) {
  const url = new URL('/auth/doctor-setup', `${appUrl()}/`);
  url.searchParams.set('mode', 'doctorSetup');
  url.searchParams.set('token', token);
  return url.toString();
}

function createRawToken(uid) {
  // The UID is only a lookup hint. The random nonce is the secret, and the
  // complete token is stored only as a one-way hash in Firestore.
  return `${uid}.${crypto.randomBytes(32).toString('hex')}`;
}

function parseRawToken(rawToken) {
  const token = String(rawToken || '').trim();
  const separator = token.indexOf('.');
  if (separator <= 0 || separator === token.length - 1) return null;
  const uid = token.slice(0, separator);
  const nonce = token.slice(separator + 1);
  if (!/^[a-f0-9]{64}$/i.test(nonce) || uid.length > 128) return null;
  return {token, uid};
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return 0;
}

function roleValue(profile, authUser) {
  return String(
      profile?.role || authUser?.customClaims?.role || '',
  ).trim().toLowerCase();
}

function isEligibleDoctor(profile, authUser) {
  const approval = String(profile?.approvalStatus || '').trim().toLowerCase();
  const status = String(
      profile?.accountStatus || profile?.status || '',
  ).trim().toLowerCase();
  const approved = approval === 'approved' || profile?.isApproved === true;
  return roleValue(profile, authUser) === 'doctor' &&
      approved &&
      ['active', 'approved'].includes(status) &&
      authUser?.disabled !== true;
}

function linkError(reason) {
  switch (reason) {
    case 'expired':
      return 'This secure account setup link expired after 5 minutes. Request a new link.';
    case 'used':
      return 'This secure account setup link has already been used. Request a new link if you still need access.';
    case 'replaced':
      return 'This secure account setup link is no longer valid because a newer link was issued. Request a new link.';
    case 'in_progress':
      return 'This secure account setup request is already being processed. Please try again shortly.';
    default:
      return 'This secure account setup link is invalid or unavailable. Request a new link.';
  }
}

function linkState(data, tokenHash, now = Date.now()) {
  if (!data || data.purpose !== 'doctor_account_setup' || data.tokenHash !== tokenHash) {
    return {valid: false, reason: 'replaced'};
  }
  if (data.usedAt) return {valid: false, reason: 'used'};
  if (data.consumingId) return {valid: false, reason: 'in_progress'};
  if (timestampMillis(data.expiresAt) <= now) return {valid: false, reason: 'expired'};
  if (data.revokedAt) return {valid: false, reason: 'replaced'};
  return {valid: true, reason: null};
}

async function findDoctorForEmail(email) {
  let authUser;
  try {
    authUser = await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error?.code === 'auth/user-not-found') return null;
    throw error;
  }

  const profileSnapshot = await db.collection('users').doc(authUser.uid).get();
  const profile = profileSnapshot.exists ? profileSnapshot.data() || {} : {};
  if (!isEligibleDoctor(profile, authUser)) return null;
  return {authUser, profile};
}

async function createDoctorSetupLink({uid, email, source = 'doctor-account'}) {
  const normalizedEmail = normalizeEmail(email);
  if (!uid || !isValidEmail(normalizedEmail)) {
    throw new Error('doctor_setup_link_target_invalid');
  }

  const token = createRawToken(uid);
  const now = Date.now();
  const linkRef = db.collection('doctor_access_links').doc(uid);
  await linkRef.set({
    uid,
    email: normalizedEmail,
    purpose: 'doctor_account_setup',
    tokenHash: hashDoctorSetupToken(token),
    issuedAt: Timestamp.fromMillis(now),
    expiresAt: Timestamp.fromMillis(now + DOCTOR_SETUP_LINK_TTL_MS),
    source: String(source || 'doctor-account').slice(0, 64),
    usedAt: null,
    revokedAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    url: doctorSetupUrl(token),
    expiresAt: now + DOCTOR_SETUP_LINK_TTL_MS,
  };
}

async function sendDoctorAccountSetupEmail({uid, email, fullName, source}) {
  const link = await createDoctorSetupLink({uid, email, source});
  const message = buildAccountOnboardingEmail({
    fullName,
    email,
    role: 'DOCTOR',
    activationUrl: link.url,
    activationExpiresInMinutes: 5,
  });
  const result = await sendSystemEmail({
    to: normalizeEmail(email),
    subject: message.subject,
    text: message.text,
    html: message.html,
  });
  if (!result.sent) {
    console.error('Doctor account setup email failed', {
      uid,
      emailHash: hashValue(normalizeEmail(email)),
      reason: result.reason || 'send_failed',
    });
  }
  return {
    sent: result.sent,
    reason: result.reason,
    message: result.sent
      ? 'A secure Doctor Portal setup email was sent.'
      : 'The doctor account was preserved, but the setup email could not be sent.',
  };
}

function getClientIp(context) {
  const request = context?.rawRequest;
  const forwarded = request?.headers?.['x-forwarded-for'];
  return String(request?.ip || forwarded || 'unknown')
      .split(',')[0]
      .trim()
      .slice(0, 128) || 'unknown';
}

function retryAfterFor(data, now, cooldownMs, maxPerWindow, windowMs) {
  if (!data) return null;
  if (data.lastRequestAt && now - data.lastRequestAt < cooldownMs) {
    return Math.ceil((cooldownMs - (now - data.lastRequestAt)) / 1000);
  }
  const windowStart = data.windowStart || now;
  if (now - windowStart < windowMs && (data.windowCount || 0) >= maxPerWindow) {
    return Math.ceil((windowStart + windowMs - now) / 1000);
  }
  return null;
}

async function checkAndRecordRequestRate(email, clientIp) {
  const emailRef = db.collection('doctor_setup_rate_limits').doc(`email_${hashValue(email)}`);
  const ipRef = db.collection('doctor_setup_rate_limits').doc(`ip_${hashValue(clientIp)}`);
  const now = Date.now();

  return db.runTransaction(async (transaction) => {
    const emailSnapshot = await transaction.get(emailRef);
    const ipSnapshot = await transaction.get(ipRef);
    const emailData = emailSnapshot.exists ? emailSnapshot.data() : null;
    const ipData = ipSnapshot.exists ? ipSnapshot.data() : null;
    const emailRetry = retryAfterFor(
        emailData,
        now,
        DOCTOR_SETUP_REQUEST_COOLDOWN_MS,
        DOCTOR_SETUP_REQUEST_MAX_PER_WINDOW,
        DOCTOR_SETUP_REQUEST_WINDOW_MS,
    );
    const ipRetry = retryAfterFor(
        ipData,
        now,
        DOCTOR_SETUP_IP_COOLDOWN_MS,
        DOCTOR_SETUP_IP_MAX_PER_WINDOW,
        DOCTOR_SETUP_IP_WINDOW_MS,
    );
    if (emailRetry !== null || ipRetry !== null) {
      return Math.max(emailRetry || 0, ipRetry || 0);
    }

    const nextWindow = (data, windowMs) => data?.windowStart &&
        now - data.windowStart < windowMs
        ? {windowStart: data.windowStart, windowCount: data.windowCount || 0}
        : {windowStart: now, windowCount: 0};
    const emailWindow = nextWindow(emailData, DOCTOR_SETUP_REQUEST_WINDOW_MS);
    const ipWindow = nextWindow(ipData, DOCTOR_SETUP_IP_WINDOW_MS);
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

async function loadLinkForToken(rawToken) {
  const parsed = parseRawToken(rawToken);
  if (!parsed) return {parsed: null, snapshot: null, data: null, state: {valid: false, reason: 'invalid'}};
  const snapshot = await db.collection('doctor_access_links').doc(parsed.uid).get();
  const data = snapshot.exists ? snapshot.data() || {} : null;
  const state = linkState(data, hashDoctorSetupToken(parsed.token));
  return {parsed, snapshot, data, state};
}

exports.verifyDoctorSetupLink = functions.https.onCall(async (data) => {
  const loaded = await loadLinkForToken(data?.token);
  if (!loaded.state.valid) {
    return {valid: false, reason: loaded.state.reason, message: linkError(loaded.state.reason)};
  }

  const authUser = await admin.auth().getUser(loaded.parsed.uid);
  const profileSnapshot = await db.collection('users').doc(loaded.parsed.uid).get();
  const profile = profileSnapshot.exists ? profileSnapshot.data() || {} : {};
  if (!isEligibleDoctor(profile, authUser) ||
      normalizeEmail(loaded.data.email) !== normalizeEmail(authUser.email)) {
    return {valid: false, reason: 'invalid', message: linkError('invalid')};
  }
  return {
    valid: true,
    email: normalizeEmail(authUser.email),
    fullName: profile.fullName || profile.displayName || authUser.displayName || 'Doctor',
  };
});

exports.completeDoctorAccountSetup = functions.https.onCall(async (data) => {
  const rawToken = String(data?.token || '').trim();
  const newPassword = data?.newPassword;
  if (typeof newPassword !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'A new password is required.');
  }
  try {
    assertStrongPassword(newPassword);
  } catch (_) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Password must be 8 to 128 characters and include uppercase, lowercase, a number, and a special character.',
    );
  }

  const loaded = await loadLinkForToken(rawToken);
  if (!loaded.state.valid) {
    throw new functions.https.HttpsError(
        loaded.state.reason === 'expired' ? 'deadline-exceeded' : 'failed-precondition',
        linkError(loaded.state.reason),
    );
  }

  const authUser = await admin.auth().getUser(loaded.parsed.uid);
  const profileSnapshot = await db.collection('users').doc(loaded.parsed.uid).get();
  const profile = profileSnapshot.exists ? profileSnapshot.data() || {} : {};
  if (!isEligibleDoctor(profile, authUser) ||
      normalizeEmail(loaded.data.email) !== normalizeEmail(authUser.email)) {
    throw new functions.https.HttpsError('permission-denied', linkError('invalid'));
  }

  const linkRef = db.collection('doctor_access_links').doc(loaded.parsed.uid);
  const reservationId = crypto.randomBytes(16).toString('hex');
  let reserved;
  try {
    reserved = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(linkRef);
      const current = snapshot.exists ? snapshot.data() || {} : null;
      const state = linkState(current, hashDoctorSetupToken(rawToken));
      if (!state.valid) return {valid: false, reason: state.reason};
      transaction.update(linkRef, {
        consumingId: reservationId,
        consumingAt: FieldValue.serverTimestamp(),
      });
      return {valid: true, reason: null};
    });
  } catch (error) {
    console.error('Doctor account setup reservation failed', {
      uid: loaded.parsed.uid,
      code: error?.code || 'unknown',
    });
    throw new functions.https.HttpsError('internal', 'Secure account setup is temporarily unavailable.');
  }
  if (!reserved.valid) {
    throw new functions.https.HttpsError(
        reserved.reason === 'expired' ? 'deadline-exceeded' : 'failed-precondition',
        linkError(reserved.reason),
    );
  }

  let authPasswordUpdated = false;
  try {
    await admin.auth().updateUser(loaded.parsed.uid, {password: newPassword});
    authPasswordUpdated = true;
    await admin.auth().revokeRefreshTokens(loaded.parsed.uid);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(linkRef);
      const current = snapshot.exists ? snapshot.data() || {} : {};
      if (current.consumingId !== reservationId) {
        throw new Error('doctor_setup_reservation_lost');
      }
      transaction.update(linkRef, {
        usedAt: FieldValue.serverTimestamp(),
        setupCompletedAt: FieldValue.serverTimestamp(),
        consumingId: FieldValue.delete(),
        consumingAt: FieldValue.delete(),
      });
      transaction.set(db.collection('users').doc(loaded.parsed.uid), {
        passwordSetupCompletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  } catch (error) {
    console.error('Doctor account setup completion failed', {
      uid: loaded.parsed.uid,
      code: error?.code || 'unknown',
    });
    // If Auth was not changed, release only this request's reservation so the
    // doctor can retry. If Auth was changed but Firestore finalization failed,
    // keep the reservation locked so the one-time token cannot be reused.
    if (!authPasswordUpdated) {
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(linkRef);
        const current = snapshot.exists ? snapshot.data() || {} : {};
        if (current.consumingId === reservationId) {
          transaction.update(linkRef, {
            consumingId: FieldValue.delete(),
            consumingAt: FieldValue.delete(),
          });
        }
      }).catch(() => {});
    }
    throw new functions.https.HttpsError('internal', 'We could not complete account setup. Please try again.');
  }

  return {success: true, email: normalizeEmail(authUser.email)};
});

exports.requestDoctorAccountSetupLink = functions.runWith({secrets: ['RESEND_API_KEY']}).https.onCall(async (data, context) => {
  const email = normalizeEmail(data?.email);
  if (!isValidEmail(email)) {
    throw new functions.https.HttpsError('invalid-argument', 'Enter a valid doctor email address.');
  }

  const retryAfterSeconds = await checkAndRecordRequestRate(email, getClientIp(context));
  if (retryAfterSeconds !== null) {
    throw new functions.https.HttpsError(
        'resource-exhausted',
        `Please wait ${retryAfterSeconds} seconds before requesting another link.`,
        {retryAfterSeconds},
    );
  }

  const doctor = await findDoctorForEmail(email);
  if (!doctor) {
    // Keep unknown and ineligible accounts indistinguishable from the normal
    // success response so this endpoint cannot be used for account discovery.
    return {
      success: true,
      message: 'If an eligible doctor account exists, a new secure setup link has been sent. Check your inbox and spam folder.',
    };
  }

  let emailResult;
  try {
    emailResult = await sendDoctorAccountSetupEmail({
      uid: doctor.authUser.uid,
      email,
      fullName: doctor.profile.fullName || doctor.profile.displayName || doctor.authUser.displayName || 'Doctor',
      source: 'doctor-requested-resend',
    });
  } catch (error) {
    console.error('Doctor setup-link request failed', {
      uid: doctor.authUser.uid,
      emailHash: hashValue(email),
      code: error?.code || 'unknown',
    });
    return {
      success: false,
      message: 'We could not send a new secure link right now. Please try again after the resend cooldown.',
    };
  }

  return {
    success: emailResult.sent,
    message: emailResult.sent
      ? 'A new secure setup link has been sent. It expires in 5 minutes.'
      : 'We could not send a new secure link right now. Please try again after the resend cooldown.',
  };
});

module.exports = {
  verifyDoctorSetupLink: exports.verifyDoctorSetupLink,
  completeDoctorAccountSetup: exports.completeDoctorAccountSetup,
  requestDoctorAccountSetupLink: exports.requestDoctorAccountSetupLink,
  createDoctorSetupLink,
  sendDoctorAccountSetupEmail,
  hashDoctorSetupToken,
  DOCTOR_SETUP_LINK_TTL_MS,
};
