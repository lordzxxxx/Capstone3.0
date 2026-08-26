const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const nodemailer = require('nodemailer');

if (!admin.apps.length) {
  admin.initializeApp();
}

// Keep this aligned with lib/firebase_helper.dart.
const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);
let assignmentEmailTransporter = null;

function normalizeText(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeRole(value) {
  return String(value || '').trim().toUpperCase();
}

function normalizeBarangayCode(value) {
  return String(value || '').trim().toUpperCase();
}

function isBarangayScopedRole(role) {
  return normalizeRole(role) === 'BHW';
}

function accessScopeForRole(role) {
  return isBarangayScopedRole(role) ? 'barangay' : 'citywide';
}

function barangayDocPath(barangayCode) {
  return `barangays/${normalizeBarangayCode(barangayCode)}`;
}

function barangayUserDocPath(barangayCode, uid) {
  return `${barangayDocPath(barangayCode)}/users/${String(uid || '').trim()}`;
}

function barangayDocRef(barangayCode) {
  return db.doc(barangayDocPath(barangayCode));
}

function barangayUserDocRef(barangayCode, uid) {
  return db.doc(barangayUserDocPath(barangayCode, uid));
}

function isActiveAccount(data) {
  const accountStatus = normalizeText(data.accountStatus || 'active');
  return accountStatus != 'disabled' && accountStatus != 'archived';
}

function maskEmail(email) {
  const raw = String(email || '').trim();
  if (!raw.includes('@')) return raw;
  const [localPart, domain] = raw.split('@');
  if (localPart.length <= 2) {
    return `${localPart[0] || '*'}***@${domain}`;
  }
  return `${localPart.slice(0, 2)}***@${domain}`;
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || '').trim());
}

function serializeError(error) {
  if (!error) {
    return null;
  }

  return {
    code: error.code || null,
    message: error.message || String(error),
    stack: error.stack || null,
  };
}

function smtpConfigValue(config, key, envKeys, fallback = '') {
  const envValue = envKeys
      .map((envKey) => process.env[envKey])
      .find((value) => String(value || '').trim().length > 0);
  if (String(envValue || '').trim().length > 0) {
    return String(envValue).trim();
  }

  const configValue = config?.[key];
  if (String(configValue || '').trim().length > 0) {
    return String(configValue).trim();
  }

  return fallback;
}

function smtpConfigBool(config, key, envKeys, fallback = false) {
  const envValue = envKeys
      .map((envKey) => process.env[envKey])
      .find((value) => value !== undefined && value !== null);
  const rawValue = envValue !== undefined ? envValue : config?.[key];
  if (rawValue === undefined || rawValue === null || rawValue === '') {
    return fallback;
  }
  return String(rawValue).trim().toLowerCase() === 'true';
}

function getAssignmentEmailTransporter() {
  if (assignmentEmailTransporter) {
    return assignmentEmailTransporter;
  }

  let smtpConfig = {};
  try {
    smtpConfig = functions.config().smtp || {};
  } catch (_) {
    smtpConfig = {};
  }

  const smtpHost = smtpConfigValue(
      smtpConfig,
      'host',
      ['SMTP_HOST'],
      'smtp.gmail.com',
  );
  const smtpPortRaw = smtpConfigValue(
      smtpConfig,
      'port',
      ['SMTP_PORT'],
      '587',
  );
  const smtpPort = parseInt(smtpPortRaw, 10) || 587;
  const smtpSecure = smtpConfigBool(
      smtpConfig,
      'secure',
      ['SMTP_SECURE'],
      false,
  );
  const smtpUser = smtpConfigValue(
      smtpConfig,
      'user',
      ['SMTP_USER'],
      '',
  );
  const smtpPass = smtpConfigValue(
      smtpConfig,
      'pass',
      ['SMTP_PASSWORD', 'SMTP_PASS'],
      smtpConfigValue(smtpConfig, 'password', ['SMTP_PASSWORD', 'SMTP_PASS'], ''),
  );

  if (!smtpUser || !smtpPass) {
    console.warn(
        'Assignment email not sent because SMTP credentials are not configured.',
    );
    return null;
  }

  assignmentEmailTransporter = nodemailer.createTransport({
    host: smtpHost,
    port: smtpPort,
    secure: smtpSecure,
    auth: {
      user: smtpUser,
      pass: smtpPass,
    },
  });

  return assignmentEmailTransporter;
}

function htmlEscape(value) {
  return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
}

function safeText(value, fallback = 'Not provided') {
  const text = String(value || '').trim();
  return text.length > 0 ? text : fallback;
}

function timestampText(value) {
  if (value && typeof value.toDate === 'function') {
    return value.toDate().toLocaleString('en-PH', { hour12: true });
  }
  if (value instanceof Date) {
    return value.toLocaleString('en-PH', { hour12: true });
  }
  if (typeof value === 'number') {
    return new Date(value).toLocaleString('en-PH', { hour12: true });
  }
  const text = String(value || '').trim();
  return text || 'Not provided';
}

function referralTypeLabel(referral) {
  const categories = Array.isArray(referral?.referralCategories)
    ? referral.referralCategories
        .map((entry) => String(entry || '').trim())
        .filter(Boolean)
    : [];
  if (categories.length) {
    return categories.join(', ');
  }

  const typeText = String(
      referral?.referralType || referral?.referralCategorySummary || '',
  ).trim();
  return typeText || 'Not specified';
}

async function sendDoctorAssignmentEmail({
  doctorEmail,
  doctorName,
  referralId,
  referral,
}) {
  const normalizedEmail = normalizeText(doctorEmail);
  if (!normalizedEmail || !isValidEmail(normalizedEmail)) {
    return {
      sent: false,
      reason: 'invalid_email',
      message: 'Assigned doctor email is missing or invalid.',
    };
  }

  const mailer = getAssignmentEmailTransporter();
  if (!mailer) {
    return {
      sent: false,
      reason: 'smtp_not_configured',
      message: 'SMTP is not configured for assignment notifications.',
    };
  }

  let smtpConfig = {};
  try {
    smtpConfig = functions.config().smtp || {};
  } catch (_) {
    smtpConfig = {};
  }

  const fromEmail = smtpConfigValue(
      smtpConfig,
      'fromEmail',
      ['SMTP_FROM_EMAIL'],
      smtpConfigValue(
          smtpConfig,
          'fromemail',
          ['SMTP_FROM_EMAIL'],
          smtpConfigValue(smtpConfig, 'user', ['SMTP_USER'], 'noreply@dsuhis.com'),
      ),
  );

  const safeDoctorName = safeText(doctorName, 'Doctor');
  const assignmentTime = timestampText(
      referral?.assignedAt || referral?.updatedAt || new Date(),
  );
  const appUrl = String(
      process.env.APP_URL || 'https://www.ai-dsuhis.com',
  ).replace(/\/$/, '');
  const portalLink = `${appUrl}/doctor/referrals`;

  const subject = `New Referral Assignment: ${referralId}`;
  const text = [
    `Hello Dr. ${safeDoctorName},`,
    '',
    'You have been assigned a referral case in DSUHIS.',
    '',
    `Referral ID: ${referralId}`,
    `Assigned At: ${assignmentTime}`,
    '',
    `Open the doctor portal: ${portalLink}`,
  ].join('\n');

  const html = `
    <div style="font-family: Arial, sans-serif; color: #0A1F24; line-height: 1.5;">
      <h2 style="margin-bottom: 8px;">New Referral Assignment</h2>
      <p>Hello Dr. ${htmlEscape(safeDoctorName)},</p>
      <p>You have been assigned a referral case in DSUHIS.</p>
      <table style="border-collapse: collapse; width: 100%; max-width: 640px;">
        <tr><td style="padding: 6px 8px; font-weight: 600;">Referral ID</td><td style="padding: 6px 8px;">${htmlEscape(referralId)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Assigned At</td><td style="padding: 6px 8px;">${htmlEscape(assignmentTime)}</td></tr>
      </table>
      <p style="margin-top: 12px;"><a href="${htmlEscape(portalLink)}">Open the doctor portal</a></p>
    </div>
  `;

  try {
    const mailResult = await mailer.sendMail({
      from: fromEmail,
      to: normalizedEmail,
      subject,
      text,
      html,
    });

    return {
      sent: true,
      reason: null,
      message: `Assignment email sent (messageId: ${mailResult.messageId || 'n/a'}).`,
    };
  } catch (error) {
    console.error('sendDoctorAssignmentEmail failed', {
      doctorEmail: normalizedEmail,
      referralId,
      error: serializeError(error),
    });
    return {
      sent: false,
      reason: 'send_failed',
      message: 'Could not send assignment email.',
    };
  }
}

function doctorRegistrationError(error, fallbackMessage) {
  if (error instanceof functions.https.HttpsError) {
    return error;
  }

  switch (error?.code) {
    case 'auth/email-already-exists':
      return new functions.https.HttpsError(
          'already-exists',
          'This email is already linked to another account.',
      );
    case 'auth/invalid-email':
      return new functions.https.HttpsError(
          'invalid-argument',
          'A valid doctor email is required.',
      );
    case 'auth/invalid-password':
    case 'auth/weak-password':
      return new functions.https.HttpsError(
          'invalid-argument',
          'Could not create the doctor account because the temporary password was rejected.',
      );
    case 'auth/insufficient-permission':
    case 'permission-denied':
      return new functions.https.HttpsError(
          'permission-denied',
          'The server is not allowed to create doctor accounts. Check Firebase Admin permissions.',
      );
    case 'not-found':
      return new functions.https.HttpsError(
          'not-found',
          fallbackMessage || 'The requested registration resource was not found.',
      );
    default:
      return new functions.https.HttpsError(
          'internal',
          fallbackMessage || 'Doctor registration failed unexpectedly.',
      );
  }
}

async function findEmailOwner(email) {
  const normalized = normalizeText(email);
  if (!normalized) return null;

  try {
    const authUser = await admin.auth().getUserByEmail(normalized);
    return {
      uid: authUser.uid,
      email: authUser.email || normalized,
      source: 'auth',
    };
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      console.error('findEmailOwner auth lookup failed', error);
    }
  }

  const byLower = await db
      .collection('users')
      .where('emailLower', '==', normalized)
      .limit(1)
      .get();
  if (!byLower.empty) {
    const doc = byLower.docs[0];
    return {
      uid: doc.id,
      email: (doc.data().email || normalized).toString(),
      username: (doc.data().username || '').toString(),
      source: 'firestore',
    };
  }

  return null;
}

async function findUsernameOwner(username) {
  const normalized = normalizeText(username);
  if (!normalized) return null;

  const byLower = await db
      .collection('users')
      .where('usernameLower', '==', normalized)
      .limit(1)
      .get();
  if (!byLower.empty) {
    const doc = byLower.docs[0];
    return {
      uid: doc.id,
      email: (doc.data().email || '').toString(),
      username: (doc.data().username || username).toString(),
    };
  }

  const exact = await db
      .collection('users')
      .where('username', '==', String(username || '').trim())
      .limit(1)
      .get();
  if (!exact.empty) {
    const doc = exact.docs[0];
    return {
      uid: doc.id,
      email: (doc.data().email || '').toString(),
      username: (doc.data().username || username).toString(),
    };
  }

  return null;
}

async function findBarangayOwner(barangayCode) {
  const normalizedCode = normalizeBarangayCode(barangayCode);
  if (!normalizedCode) return null;

  const lockSnap = await db
      .collection('registration_barangay_locks')
      .doc(normalizedCode)
      .get();
  if (lockSnap.exists) {
    const data = lockSnap.data() || {};
    if (isActiveAccount(data)) {
      return {
        uid: (data.uid || '').toString(),
        username: (data.username || '').toString(),
        email: (data.email || '').toString(),
        barangay: (data.barangay || '').toString(),
        barangayCode: normalizedCode,
        approvalStatus: (data.approvalStatus || 'pending').toString(),
        accountStatus: (data.accountStatus || 'active').toString(),
      };
    }
  }

  const snapshot = await db
      .collection('users')
      .where('barangayCode', '==', normalizedCode)
      .limit(10)
      .get();

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (!isBarangayScopedRole(data.role) || !isActiveAccount(data)) {
      continue;
    }
    return {
      uid: doc.id,
      username: (data.username || '').toString(),
      email: (data.email || '').toString(),
      barangay: (data.barangay || '').toString(),
      barangayCode: normalizedCode,
      approvalStatus: (data.approvalStatus || 'pending').toString(),
      accountStatus: (data.accountStatus || 'active').toString(),
    };
  }

  return null;
}

async function findBarangayOwnerInTransaction(transaction, barangayCode, currentUid) {
  const normalizedCode = normalizeBarangayCode(barangayCode);
  if (!normalizedCode) return null;

  const snapshot = await transaction.get(
      db.collection('users').where('barangayCode', '==', normalizedCode).limit(10),
  );

  for (const doc of snapshot.docs) {
    if (doc.id === currentUid) {
      continue;
    }

    const data = doc.data() || {};
    if (!isBarangayScopedRole(data.role) || !isActiveAccount(data)) {
      continue;
    }

    return {
      uid: doc.id,
      username: (data.username || '').toString(),
      email: (data.email || '').toString(),
      barangay: (data.barangay || '').toString(),
      barangayCode: normalizedCode,
      approvalStatus: (data.approvalStatus || 'pending').toString(),
      accountStatus: (data.accountStatus || 'active').toString(),
    };
  }

  return null;
}

function ensureChoOperator(context, userData) {
  const role = normalizeRole(userData.role || '');
  if (!context.auth || !['CHO', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'].includes(role)) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Only CHO operators can use this action.',
    );
  }
}

function doctorAvailabilityValue(data) {
  return normalizeText(data?.availability || data?.doctorAvailability || 'available') || 'available';
}

function doctorSpecializationValue(data) {
  const specialization = String(
      data?.specialization || data?.doctorSpecialization || data?.specialty || 'General Medicine',
  ).trim();
  return specialization || 'General Medicine';
}

function doctorDisplayName(data) {
  return String(
      data?.username || data?.fullName || data?.displayName || data?.email || 'Doctor',
  ).trim() || 'Doctor';
}

async function syncReferralMirror(referralId, payload) {
  const normalizedReferralId = String(referralId || '').trim();
  const barangayCode = normalizeBarangayCode(payload?.barangayCode || '');
  if (!normalizedReferralId || !barangayCode) {
    return;
  }

  await db.doc(`barangays/${barangayCode}/referrals/${normalizedReferralId}`).set({
    ...payload,
    rootReferralPath: `referrals/${normalizedReferralId}`,
    storedUnderBarangay: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

function doctorSpecialtyKeywords() {
  return {
    cardiology: ['heart', 'chest', 'hypertension', 'cardio'],
    pediatrics: ['child', 'infant', 'pediatric', 'newborn'],
    obstetrics: ['pregnan', 'prenatal', 'maternal', 'obstetric'],
    pulmonology: ['asthma', 'lung', 'respiratory', 'breathing', 'cough'],
    infectious: ['fever', 'infection', 'dengue', 'tb', 'tuberculosis'],
    general: ['general', 'family', 'internal'],
  };
}

async function rankDoctorsForReferral(referral) {
  const doctorsSnap = await db
      .collection('users')
      .where('role', 'in', ['DOCTOR', 'doctor'])
      .get();
  if (doctorsSnap.empty) {
    return [];
  }

  const referralsSnap = await db.collection('referrals').get();
  const openCounts = {};
  for (const doc of referralsSnap.docs) {
    const row = doc.data() || {};
    const status = normalizeText(row.status || 'submitted');
    const assignedDoctorUid = String(row.assignedDoctorUid || '').trim();
    if (!assignedDoctorUid) continue;
    if (['completed', 'cancelled', 'closed'].includes(status)) continue;
    openCounts[assignedDoctorUid] = (openCounts[assignedDoctorUid] || 0) + 1;
  }

  return doctorsSnap.docs
      .map((doc) => {
        const row = doc.data() || {};
        const accountStatus = normalizeText(row.accountStatus || 'active');
        const approvalStatus = normalizeText(row.approvalStatus || 'pending');
        const availability = doctorAvailabilityValue(row);
        const specialization = doctorSpecializationValue(row);
        const workload = openCounts[doc.id] || 0;

        const normalizedAccountStatus = accountStatus.replace(/[\s-]+/g, '_');
        const normalizedAvailability = availability.replace(/[\s-]+/g, '_');
        const unavailable = [
          'disabled', 'archived', 'inactive', 'deactivated',
        ].includes(normalizedAccountStatus) || [
          'unavailable', 'on_leave', 'leave', 'off_duty',
        ].includes(normalizedAvailability);
        if (unavailable) return null;

        const score = Math.max(0, 100 - workload * 10);
        const reasons = [
          `${workload} active referral${workload === 1 ? '' : 's'} in workload`,
          approvalStatus === 'approved' ? 'Approved doctor account' : 'Doctor account pending approval',
          `Availability: ${availability}`,
        ];

        return {
          doctorUid: doc.id,
          doctorName: doctorDisplayName(row),
          doctorEmail: String(row.email || '').trim(),
          specialization,
          availability,
          workload,
          score,
          rationale: reasons,
        };
      })
      .filter((doctor) => doctor != null)
      // Workload is the assignment rule. UID is a stable tie-breaker so the
      // same data produces the same result on every invocation.
      .sort((a, b) => a.workload - b.workload ||
        a.doctorUid.localeCompare(b.doctorUid));
}

function buildRootUserPayload({
  uid,
  username,
  email,
  role,
  barangay,
  barangayCode,
  barangayDistrict,
  previousData,
}) {
  const normalizedRole = normalizeRole(role);
  const normalizedBarangayCode = normalizeBarangayCode(barangayCode);
  const isBarangayScoped =
    isBarangayScopedRole(normalizedRole) && !!normalizedBarangayCode;
  const barangayPath = isBarangayScoped ?
    barangayDocPath(normalizedBarangayCode) :
    null;
  const barangayUserPath = isBarangayScoped ?
    barangayUserDocPath(normalizedBarangayCode, uid) :
    null;

  return {
    username,
    usernameLower: normalizeText(username),
    email,
    emailLower: normalizeText(email),
    uid,
    role: normalizedRole,
    accessScope: accessScopeForRole(normalizedRole),
    organizationLevel: isBarangayScoped ? 'barangay' : 'citywide',
    dataVisibilityStartAt:
      previousData?.dataVisibilityStartAt ||
      admin.firestore.FieldValue.serverTimestamp(),
    barangay: isBarangayScoped ?
      barangay :
      admin.firestore.FieldValue.delete(),
    barangayCode: isBarangayScoped ?
      normalizedBarangayCode :
      admin.firestore.FieldValue.delete(),
    barangayDistrict: isBarangayScoped ?
      barangayDistrict :
      admin.firestore.FieldValue.delete(),
    barangayVerified: isBarangayScoped,
    barangayPath: barangayPath || admin.firestore.FieldValue.delete(),
    barangayUserPath: barangayUserPath || admin.firestore.FieldValue.delete(),
    approvalStatus: 'approved',
    accountStatus: previousData?.accountStatus || 'active',
    createdAt:
      previousData?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function buildDoctorUserPayload({
  uid,
  fullName,
  email,
  specialization,
  availability,
  previousData,
  registeredByUid,
}) {
  return {
    uid,
    username: fullName,
    usernameLower: normalizeText(fullName),
    fullName,
    displayName: fullName,
    email,
    emailLower: normalizeText(email),
    role: 'DOCTOR',
    accessScope: 'citywide',
    organizationLevel: 'citywide',
    dataVisibilityStartAt:
      previousData?.dataVisibilityStartAt ||
      admin.firestore.FieldValue.serverTimestamp(),
    specialization,
    doctorSpecialization: specialization,
    specialty: specialization,
    availability,
    doctorAvailability: availability,
    approvalStatus: previousData?.approvalStatus || 'approved',
    accountStatus: previousData?.accountStatus || 'active',
    doctorRegistrySource: 'cho_registry',
    doctorRegisteredByUid: registeredByUid,
    barangay: admin.firestore.FieldValue.delete(),
    barangayCode: admin.firestore.FieldValue.delete(),
    barangayDistrict: admin.firestore.FieldValue.delete(),
    barangayVerified: false,
    barangayPath: admin.firestore.FieldValue.delete(),
    barangayUserPath: admin.firestore.FieldValue.delete(),
    createdAt:
      previousData?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function buildBarangayDirectoryPayload(data) {
  return {
    barangay: String(data?.barangay || '').trim(),
    barangayCode: normalizeBarangayCode(data?.barangayCode || ''),
    barangayDistrict: String(data?.barangayDistrict || '').trim(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastUserSyncAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function buildBarangayUserPayload(uid, data) {
  const normalizedRole = normalizeRole(data?.role || '');
  const normalizedBarangayCode = normalizeBarangayCode(data?.barangayCode || '');

  return {
    uid,
    username: String(data?.username || '').trim(),
    usernameLower: normalizeText(data?.username || ''),
    email: String(data?.email || '').trim(),
    emailLower: normalizeText(data?.email || ''),
    role: normalizedRole,
    accessScope: String(
        data?.accessScope || accessScopeForRole(normalizedRole),
    ).trim(),
    organizationLevel: 'barangay',
    dataVisibilityStartAt:
      data?.dataVisibilityStartAt ||
      data?.createdAt ||
      admin.firestore.FieldValue.serverTimestamp(),
    barangay: String(data?.barangay || '').trim(),
    barangayCode: normalizedBarangayCode,
    barangayDistrict: String(data?.barangayDistrict || '').trim(),
    barangayVerified: true,
    barangayPath: barangayDocPath(normalizedBarangayCode),
    barangayUserPath: barangayUserDocPath(normalizedBarangayCode, uid),
    rootUserPath: `users/${uid}`,
    storedUnderBarangay: true,
    approvalStatus: String(data?.approvalStatus || 'pending').trim(),
    accountStatus: String(data?.accountStatus || 'active').trim(),
    createdAt:
      data?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function buildBarangayRegistrationStatusPayload(data) {
  return {
    uid: String(data?.uid || '').trim(),
    barangay: String(data?.barangay || '').trim(),
    barangayCode: normalizeBarangayCode(data?.barangayCode || ''),
    barangayDistrict: String(data?.barangayDistrict || '').trim(),
    accountStatus: String(data?.accountStatus || 'active').trim(),
    approvalStatus: String(data?.approvalStatus || 'pending').trim(),
    isAvailable: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function buildValidationPolicyResult({
  emailOwner = null,
  usernameOwner = null,
  barangayOwner = null,
} = {}) {
  const duplicateAccountMessage =
    'This account is already registered. Please log in instead.';
  const barangayMessage =
    'This barangay is already registered under another account.';

  return {
    emailExists: !!emailOwner,
    usernameExists: !!usernameOwner,
    barangayUnavailable: !!barangayOwner,
    duplicateAccountMessage,
    barangayMessage,
    emailOwner: emailOwner
      ? {
          uid: emailOwner.uid,
          email: maskEmail(emailOwner.email),
        }
      : null,
    usernameOwner: usernameOwner
      ? {
          uid: usernameOwner.uid,
          username: usernameOwner.username,
          email: maskEmail(usernameOwner.email),
        }
      : null,
    barangayOwner: barangayOwner
      ? {
          uid: barangayOwner.uid,
          username: barangayOwner.username,
          email: maskEmail(barangayOwner.email),
          barangay: barangayOwner.barangay,
          barangayCode: barangayOwner.barangayCode,
          approvalStatus: barangayOwner.approvalStatus,
          accountStatus: barangayOwner.accountStatus,
        }
      : null,
  };
}

async function syncBarangayLock(uid, beforeData, afterData) {
  const beforeCode = normalizeBarangayCode(beforeData?.barangayCode || '');
  const afterCode = normalizeBarangayCode(afterData?.barangayCode || '');
  const beforeActive = beforeData && isBarangayScopedRole(beforeData.role) && isActiveAccount(beforeData);
  const afterActive = afterData && isBarangayScopedRole(afterData.role) && isActiveAccount(afterData);

  if (beforeCode && (!afterActive || beforeCode !== afterCode)) {
    const beforeRef = db.collection('registration_barangay_locks').doc(beforeCode);
    const beforeSnap = await beforeRef.get();
    if (beforeSnap.exists && beforeSnap.data().uid === uid) {
      await beforeRef.delete();
    }
  }

  if (afterActive && afterCode) {
    await db.collection('registration_barangay_locks').doc(afterCode).set({
      uid,
      barangayCode: afterCode,
      barangay: (afterData.barangay || '').toString(),
      barangayDistrict: (afterData.barangayDistrict || '').toString(),
      username: (afterData.username || '').toString(),
      email: (afterData.email || '').toString(),
      accountStatus: (afterData.accountStatus || 'active').toString(),
      approvalStatus: (afterData.approvalStatus || 'pending').toString(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: 'users-sync',
    }, { merge: true });
  }
}

async function syncBarangayUserMirror(uid, beforeData, afterData) {
  const beforeCode = normalizeBarangayCode(beforeData?.barangayCode || '');
  const afterCode = normalizeBarangayCode(afterData?.barangayCode || '');
  const hadBarangayMirror =
    !!beforeData && isBarangayScopedRole(beforeData.role) && !!beforeCode;
  const needsBarangayMirror =
    !!afterData && isBarangayScopedRole(afterData.role) && !!afterCode;

  let hasWrites = false;
  const batch = db.batch();

  if (hadBarangayMirror && (!needsBarangayMirror || beforeCode !== afterCode)) {
    batch.delete(barangayUserDocRef(beforeCode, uid));
    hasWrites = true;
  }

  if (needsBarangayMirror) {
    batch.set(
        barangayDocRef(afterCode),
        buildBarangayDirectoryPayload(afterData),
        { merge: true },
    );
    batch.set(
        barangayUserDocRef(afterCode, uid),
        buildBarangayUserPayload(uid, afterData),
        { merge: true },
    );
    hasWrites = true;
  }

  if (hasWrites) {
    await batch.commit();
  }
}

async function syncBarangayRegistrationStatus(beforeData, afterData) {
  const touchedCodes = Array.from(
      new Set([
        normalizeBarangayCode(beforeData?.barangayCode || ''),
        normalizeBarangayCode(afterData?.barangayCode || ''),
      ].filter(Boolean)),
  );

  for (const barangayCode of touchedCodes) {
    const statusRef = db.collection('barangay_registration_status').doc(barangayCode);
    const owner = await findBarangayOwner(barangayCode);
    if (!owner) {
      await statusRef.delete();
      continue;
    }

    await statusRef.set(
        buildBarangayRegistrationStatusPayload(owner),
        { merge: true },
    );
  }
}

exports.validateRegistrationPolicy = functions.https.onCall(async (data) => {
  const email = String(data?.email || '').trim();
  const username = String(data?.username || '').trim();
  const role = normalizeRole(data?.role || '');
  const barangayCode = normalizeBarangayCode(data?.barangayCode || '');

  try {
    const [emailOwner, usernameOwner, barangayOwner] = await Promise.all([
      email ? findEmailOwner(email) : null,
      username ? findUsernameOwner(username) : null,
      isBarangayScopedRole(role) && barangayCode ?
        findBarangayOwner(barangayCode) :
        null,
    ]);

    return buildValidationPolicyResult({
      emailOwner,
      usernameOwner,
      barangayOwner,
    });
  } catch (error) {
    console.error('validateRegistrationPolicy failed; returning safe fallback', {
      email,
      username,
      role,
      barangayCode,
      error,
    });
    return buildValidationPolicyResult();
  }
});

exports.getBarangayAvailability = functions.https.onCall(async () => {
  try {
    const snapshot = await db.collection('registration_barangay_locks').get();

    const items = [];
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (!data.barangayCode || !isActiveAccount(data)) {
        continue;
      }

      items.push({
        uid: doc.id,
        barangayCode: normalizeBarangayCode(data.barangayCode),
        barangay: (data.barangay || '').toString(),
        username: (data.username || '').toString(),
        email: maskEmail(data.email || ''),
        accountStatus: (data.accountStatus || 'active').toString(),
        approvalStatus: (data.approvalStatus || 'pending').toString(),
        isAvailable: false,
      });
    }

    return { items };
  } catch (error) {
    console.error('getBarangayAvailability failed; returning empty fallback', error);
    return { items: [] };
  }
});

exports.completeRegistration = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to complete registration.',
    );
  }

  const uid = String(data?.uid || '').trim();
  const username = String(data?.username || '').trim();
  const email = String(data?.email || '').trim();
  const role = normalizeRole(data?.role || '');
  const barangay = String(data?.barangay || '').trim();
  const barangayCode = normalizeBarangayCode(data?.barangayCode || '');
  const barangayDistrict = String(data?.barangayDistrict || '').trim();

  if (!uid || uid !== context.auth.uid) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Registration can only be completed for the authenticated user.',
    );
  }

  if (!email || !username || !role) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Email, username, and role are required.',
    );
  }

  if (!['CHO', 'BHW'].includes(role)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Unsupported role value.',
    );
  }

  if (role === 'BHW') {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'BHW accounts must use the pending registration request workflow and require CHO approval.',
    );
  }

  if (isBarangayScopedRole(role) && !barangayCode) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Barangay assignment is required for BHW accounts.',
    );
  }

  const userRef = db.collection('users').doc(uid);
  const emailLockRef = db.collection('registration_email_locks').doc(normalizeText(email));
  const usernameLockRef = db.collection('registration_username_locks').doc(normalizeText(username));
  const barangayLockRef = barangayCode
      ? db.collection('registration_barangay_locks').doc(barangayCode)
      : null;
  const barangayStatusRef = barangayCode
      ? db.collection('barangay_registration_status').doc(barangayCode)
      : null;

  let previousData = null;
  await db.runTransaction(async (transaction) => {
    const [userSnap, emailLockSnap, usernameLockSnap, barangayLockSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(emailLockRef),
      transaction.get(usernameLockRef),
      barangayLockRef ? transaction.get(barangayLockRef) : Promise.resolve(null),
    ]);

    previousData = userSnap.exists ? userSnap.data() : null;
    const previousBarangayCode = normalizeBarangayCode(previousData?.barangayCode || '');
    const hadBarangayMirror =
      !!previousData &&
      isBarangayScopedRole(previousData.role) &&
      !!previousBarangayCode;

    if (emailLockSnap.exists && emailLockSnap.data().uid !== uid) {
      throw new functions.https.HttpsError(
          'already-exists',
          'This account is already registered. Please log in instead.',
      );
    }

    if (usernameLockSnap.exists && usernameLockSnap.data().uid !== uid) {
      throw new functions.https.HttpsError(
          'already-exists',
          'This account is already registered. Please log in instead.',
      );
    }

    if (barangayLockSnap && barangayLockSnap.exists && barangayLockSnap.data().uid !== uid) {
      throw new functions.https.HttpsError(
          'already-exists',
          'This barangay is already registered under another account.',
      );
    }

    const existingBarangayOwner = isBarangayScopedRole(role) && barangayCode ?
      await findBarangayOwnerInTransaction(transaction, barangayCode, uid) :
      null;
    if (existingBarangayOwner) {
      throw new functions.https.HttpsError(
          'already-exists',
          'This barangay is already registered under another account.',
      );
    }

    const payload = buildRootUserPayload({
      uid,
      username,
      email,
      role,
      barangay,
      barangayCode,
      barangayDistrict,
      previousData,
    });

    transaction.set(userRef, payload, { merge: true });
    transaction.set(emailLockRef, {
      uid,
      email,
      emailLower: normalizeText(email),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(usernameLockRef, {
      uid,
      username,
      usernameLower: normalizeText(username),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    if (barangayLockRef && isBarangayScopedRole(role)) {
      transaction.set(barangayLockRef, {
        uid,
        barangay,
        barangayCode,
        barangayDistrict,
        username,
        email,
        accountStatus: previousData?.accountStatus || 'active',
        approvalStatus: 'approved',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: 'registration-complete',
      }, { merge: true });
    }

    if (barangayStatusRef && isBarangayScopedRole(role)) {
      transaction.set(barangayStatusRef, buildBarangayRegistrationStatusPayload({
        uid,
        barangay,
        barangayCode,
        barangayDistrict,
        accountStatus: previousData?.accountStatus || 'active',
        approvalStatus: 'approved',
      }), { merge: true });
    }

    if (hadBarangayMirror && (!isBarangayScopedRole(role) || previousBarangayCode !== barangayCode)) {
      transaction.delete(barangayUserDocRef(previousBarangayCode, uid));
    }

    if (isBarangayScopedRole(role)) {
      transaction.set(
          barangayDocRef(barangayCode),
          buildBarangayDirectoryPayload({
            barangay,
            barangayCode,
            barangayDistrict,
          }),
          { merge: true },
      );
      transaction.set(
          barangayUserDocRef(barangayCode, uid),
          buildBarangayUserPayload(uid, payload),
          { merge: true },
      );
    }
  });

  const existingAuthUser = await admin.auth().getUser(uid);
  const existingClaims = existingAuthUser.customClaims || {};
  await admin.auth().setCustomUserClaims(uid, {
    ...existingClaims,
    role,
  });

  try {
    await admin.database().ref(`users/${uid}`).update({
      uid,
      username,
      email,
      role,
      accessScope: accessScopeForRole(role),
      barangay: isBarangayScopedRole(role) ? barangay : null,
      barangayCode: isBarangayScopedRole(role) ? barangayCode : null,
      barangayDistrict: isBarangayScopedRole(role) ? barangayDistrict : null,
      approvalStatus: 'approved',
      accountStatus: previousData?.accountStatus || 'active',
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    });
  } catch (error) {
    console.error('RTDB mirror update failed after completeRegistration', error);
  }

  return {
    success: true,
    duplicateAccountMessage:
      'This account is already registered. Please log in instead.',
    barangayMessage:
      'This barangay is already registered under another account.',
  };
});

exports.syncAccountGovernanceLocks = functions.firestore
    .database(FIRESTORE_DATABASE_ID)
    .document('users/{uid}')
    .onWrite(async (change, context) => {
      const uid = context.params.uid;
      const beforeData = change.before.exists ? change.before.data() : null;
      const afterData = change.after.exists ? change.after.data() : null;

      if (!afterData) {
        await syncBarangayLock(uid, beforeData, null);
        await syncBarangayUserMirror(uid, beforeData, null);
        await syncBarangayRegistrationStatus(beforeData, null);
        return null;
      }

      const email = String(afterData.email || '').trim();
      const username = String(afterData.username || '').trim();

      if (email) {
        await db.collection('registration_email_locks').doc(normalizeText(email)).set({
          uid,
          email,
          emailLower: normalizeText(email),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: 'users-sync',
        }, { merge: true });
      }

      if (username) {
        await db.collection('registration_username_locks').doc(normalizeText(username)).set({
          uid,
          username,
          usernameLower: normalizeText(username),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: 'users-sync',
        }, { merge: true });
      }

      await syncBarangayLock(uid, beforeData, afterData);
      await syncBarangayUserMirror(uid, beforeData, afterData);
      await syncBarangayRegistrationStatus(beforeData, afterData);
      return null;
    });

exports.registerDoctorAccount = functions.https.onCall(async (data, context) => {
  const fullName = String(data?.fullName || '').trim();
  const email = String(data?.email || '').trim().toLowerCase();
  const specialization = doctorSpecializationValue(data || {});
  const availability = doctorAvailabilityValue(data || {});

  console.log('registerDoctorAccount started', {
    callerUid: context.auth?.uid || null,
    email,
    specialization,
    availability,
  });

  let userRecord = null;
  let created = false;

  try {
    if (!context.auth) {
      throw new functions.https.HttpsError(
          'unauthenticated',
          'You must be signed in to register a doctor.',
      );
    }

    const callerDoc = await db.collection('users').doc(context.auth.uid).get();
    ensureChoOperator(context, callerDoc.data() || {});

    if (!fullName || !email || !specialization) {
      throw new functions.https.HttpsError(
          'invalid-argument',
          'Doctor name, email, and specialization are required.',
      );
    }

    if (!isValidEmail(email)) {
      throw new functions.https.HttpsError(
          'invalid-argument',
          'A valid doctor email is required.',
      );
    }

    if (!['available', 'busy', 'limited', 'unavailable'].includes(availability)) {
      throw new functions.https.HttpsError(
          'invalid-argument',
          'Availability must be available, busy, limited, or unavailable.',
      );
    }

    try {
      userRecord = await admin.auth().getUserByEmail(email);
      console.log('registerDoctorAccount found existing auth user', {
        email,
        doctorUid: userRecord.uid,
      });
    } catch (error) {
      if (error.code !== 'auth/user-not-found') {
        throw doctorRegistrationError(error, 'Failed to check whether the doctor account already exists.');
      }

      const tempPassword = `${Math.random().toString(36).slice(-8)}A1!`;
      try {
        userRecord = await admin.auth().createUser({
          email,
          password: tempPassword,
          displayName: fullName,
        });
        created = true;
        console.log('registerDoctorAccount created auth user', {
          email,
          doctorUid: userRecord.uid,
        });
      } catch (error) {
        throw doctorRegistrationError(error, 'Failed to create the doctor account in Firebase Authentication.');
      }
    }

    const userRef = db.collection('users').doc(userRecord.uid);
    const emailLockRef = db.collection('registration_email_locks').doc(normalizeText(email));
    const usernameLockRef = db.collection('registration_username_locks').doc(normalizeText(fullName));
    const existingSnap = await userRef.get();
    const existingData = existingSnap.data() || {};
    const existingRole = normalizeRole(existingData.role || '');

    if (existingSnap.exists && existingRole && existingRole !== 'DOCTOR') {
      throw new functions.https.HttpsError(
          'already-exists',
          'This email is already linked to a non-doctor account.',
      );
    }

    const conflictingEmailLock = await emailLockRef.get();
    if (conflictingEmailLock.exists) {
      const lockUid = String(conflictingEmailLock.data()?.uid || '').trim();
      if (lockUid && lockUid !== userRecord.uid) {
        throw new functions.https.HttpsError(
            'already-exists',
            'This email is already linked to another account.',
        );
      }
    }

    const conflictingUsernameLock = await usernameLockRef.get();
    if (conflictingUsernameLock.exists) {
      const lockUid = String(conflictingUsernameLock.data()?.uid || '').trim();
      if (lockUid && lockUid !== userRecord.uid) {
        throw new functions.https.HttpsError(
            'already-exists',
            'This doctor name is already linked to another account.',
        );
      }
    }

    try {
      await db.runTransaction(async (transaction) => {
        const latestUserSnap = await transaction.get(userRef);
        const latestData = latestUserSnap.exists ? latestUserSnap.data() : existingData;
        const payload = buildDoctorUserPayload({
          uid: userRecord.uid,
          fullName,
          email,
          specialization,
          availability,
          previousData: latestData,
          registeredByUid: context.auth.uid,
        });

        transaction.set(userRef, payload, { merge: true });
        transaction.set(emailLockRef, {
          uid: userRecord.uid,
          email,
          emailLower: normalizeText(email),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: 'doctor-registration',
        }, { merge: true });
        transaction.set(usernameLockRef, {
          uid: userRecord.uid,
          username: fullName,
          usernameLower: normalizeText(fullName),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: 'doctor-registration',
        }, { merge: true });
      });
      console.log('registerDoctorAccount wrote Firestore documents', {
        email,
        doctorUid: userRecord.uid,
        userPath: `users/${userRecord.uid}`,
      });
    } catch (error) {
      console.error('registerDoctorAccount Firestore transaction failed', {
        doctorUid: userRecord.uid,
        email,
        error: serializeError(error),
      });

      if (created) {
        try {
          await admin.auth().deleteUser(userRecord.uid);
        } catch (rollbackError) {
          console.error('registerDoctorAccount auth rollback failed', {
            doctorUid: userRecord.uid,
            email,
            rollbackError: serializeError(rollbackError),
          });
        }
      }

      throw doctorRegistrationError(
          error,
          'Doctor account creation reached Auth but failed to persist in Firestore.',
      );
    }

    let claimsSynced = true;
    try {
      const refreshedUserRecord = await admin.auth().getUser(userRecord.uid);
      const existingClaims = refreshedUserRecord.customClaims || {};
      await admin.auth().setCustomUserClaims(userRecord.uid, {
        ...existingClaims,
        role: 'DOCTOR',
      });
    } catch (error) {
      claimsSynced = false;
      console.error('registerDoctorAccount custom claims sync failed', {
        doctorUid: userRecord.uid,
        email,
        error: serializeError(error),
      });
    }

    try {
      await admin.database().ref(`users/${userRecord.uid}`).update({
        uid: userRecord.uid,
        username: fullName,
        email,
        role: 'DOCTOR',
        specialization,
        doctorSpecialization: specialization,
        availability,
        doctorAvailability: availability,
        accessScope: 'citywide',
        updatedAt: admin.database.ServerValue.TIMESTAMP,
      });
    } catch (error) {
      console.error('RTDB mirror update failed after registerDoctorAccount', {
        doctorUid: userRecord.uid,
        email,
        error: serializeError(error),
      });
    }

    let resetLink = null;
    try {
      resetLink = await admin.auth().generatePasswordResetLink(email);
    } catch (error) {
      console.error('Password reset link generation failed for doctor account', {
        doctorUid: userRecord.uid,
        email,
        error: serializeError(error),
      });
    }

    console.log('registerDoctorAccount completed', {
      email,
      doctorUid: userRecord.uid,
      created,
      claimsSynced,
    });

    return {
      success: true,
      created,
      uid: userRecord.uid,
      doctorName: fullName,
      email,
      specialization,
      availability,
      claimsSynced,
      resetLink,
    };
  } catch (error) {
    console.error('registerDoctorAccount failed', {
      callerUid: context.auth?.uid || null,
      email,
      fullName,
      specialization,
      availability,
      created,
      doctorUid: userRecord?.uid || null,
      error: serializeError(error),
    });
    throw doctorRegistrationError(error, 'Doctor registration failed.');
  }
});

exports.assignDoctorToReferral = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to assign a doctor.',
    );
  }

  const referralId = String(data?.referralId || '').trim();
  const preferredDoctorUid = String(data?.preferredDoctorUid || '').trim();
  if (!referralId) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Referral ID is required.',
    );
  }

  const [callerDoc, referralDoc] = await Promise.all([
    db.collection('users').doc(context.auth.uid).get(),
    db.collection('referrals').doc(referralId).get(),
  ]);

  if (!referralDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Referral was not found.');
  }

  const callerData = callerDoc.data() || {};
  const callerRole = normalizeRole(callerData.role || '');
  const isChoOperator = ['CHO', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'].includes(callerRole);
  const referral = referralDoc.data() || {};
  const createdByUid = String(referral.createdByUid || '').trim();

  if (!isChoOperator && createdByUid !== context.auth.uid) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Only the referring BHW or a CHO operator can assign this referral.',
    );
  }

  const rankedDoctors = await rankDoctorsForReferral(referral);
  if (!rankedDoctors.length) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'No eligible doctor is currently available for assignment.',
    );
  }

  let assignedDoctor = rankedDoctors[0];
  let assignmentMode = 'smart';
  let assignmentSource = isChoOperator ? 'cho_auto' : 'bhw_auto';

  if (preferredDoctorUid) {
    const preferredDoctor = rankedDoctors.find((doctor) => doctor.doctorUid === preferredDoctorUid);
    if (!preferredDoctor) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'The selected doctor is not eligible for assignment right now.',
      );
    }
    assignedDoctor = preferredDoctor;
    assignmentMode = 'manual';
    assignmentSource = isChoOperator ? 'cho_selected' : 'bhw_selected';
  }

  const assignmentRationale = assignedDoctor.rationale.join(' | ');
  // Keep the event key stable across callable retries so a transient client
  // retry cannot send a second email for the same referral/doctor assignment.
  const assignmentEventId = `${referralId}:${assignedDoctor.doctorUid}`;
  const updatePayload = {
    assignedDoctorUid: assignedDoctor.doctorUid,
    assignedDoctorName: assignedDoctor.doctorName,
    assignedDoctorEmail: assignedDoctor.doctorEmail,
    assignedDoctorSpecialization: assignedDoctor.specialization,
    assignedDoctorAvailability: assignedDoctor.availability,
    referredTo: assignedDoctor.doctorName,
    assignmentMode,
    assignmentSource,
    assignmentRationale: assignmentRationale || (assignmentMode === 'smart' ?
      'Automatically assigned to the eligible doctor with the lowest active referral workload.' :
      'Requested explicitly by the referring user.'),
    assignmentScore: assignedDoctor.score,
    assignmentEventId,
    assignedByUid: context.auth.uid,
    assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'assigned',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await referralDoc.ref.set(updatePayload, { merge: true });
  await syncReferralMirror(referralId, {
    ...referral,
    ...updatePayload,
    barangayCode: referral.barangayCode || '',
  });

  const assignmentEmail = await sendDoctorAssignmentEmail({
    doctorEmail: assignedDoctor.doctorEmail,
    doctorName: assignedDoctor.doctorName,
    referralId,
    referral: {
      ...referral,
      ...updatePayload,
    },
  });
  if (assignmentEmail.sent) {
    await referralDoc.ref.update({
      assignmentNotificationSentFor: assignmentEventId,
      assignmentNotificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return {
    success: true,
    recommendation: assignedDoctor,
    rankedDoctors: rankedDoctors.slice(0, 5),
    assignmentMode,
    assignmentSource,
    assignmentEmailSent: assignmentEmail.sent,
    assignmentEmailReason: assignmentEmail.reason,
    assignmentEmailMessage: assignmentEmail.message,
  };
});

exports.sendDoctorReferralAssignmentEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to send assignment notifications.',
    );
  }

  const referralId = String(data?.referralId || '').trim();
  if (!referralId) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Referral ID is required.',
    );
  }

  const [callerDoc, referralDoc] = await Promise.all([
    db.collection('users').doc(context.auth.uid).get(),
    db.collection('referrals').doc(referralId).get(),
  ]);

  ensureChoOperator(context, callerDoc.data() || {});

  if (!referralDoc.exists) {
    throw new functions.https.HttpsError(
        'not-found',
        'Referral was not found.',
    );
  }

  const referral = referralDoc.data() || {};
  const assignmentEventId = String(
      referral.assignmentEventId ||
      `legacy:${referralId}:${referral.assignedDoctorUid || 'unassigned'}`,
  );
  if (referral.assignmentNotificationSentFor === assignmentEventId) {
    return {
      success: true,
      sent: true,
      reason: 'already_sent',
      message: 'The assignment notification was already sent for this assignment.',
    };
  }
  const doctorEmail = normalizeText(
      data?.doctorEmail || referral.assignedDoctorEmail || '',
  );
  const doctorName = String(
      data?.doctorName ||
      referral.assignedDoctorName ||
      referral.referredTo ||
      'Doctor',
  ).trim() || 'Doctor';

  const assignmentEmail = await sendDoctorAssignmentEmail({
    doctorEmail,
    doctorName,
    referralId,
    referral,
  });
  if (assignmentEmail.sent) {
    await referralDoc.ref.update({
      assignmentNotificationSentFor: assignmentEventId,
      assignmentNotificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return {
    success: assignmentEmail.sent,
    sent: assignmentEmail.sent,
    reason: assignmentEmail.reason,
    message: assignmentEmail.message,
  };
});

exports.suggestDoctorAssignment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to request doctor assignment suggestions.',
    );
  }

  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  ensureChoOperator(context, callerDoc.data() || {});

  const referralId = String(data?.referralId || '').trim();
  if (!referralId) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Referral ID is required.',
    );
  }

  const referralDoc = await db.collection('referrals').doc(referralId).get();
  if (!referralDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Referral was not found.');
  }

  const referral = referralDoc.data() || {};
  const rankedDoctors = await rankDoctorsForReferral(referral);
  if (!rankedDoctors.length) {
    return { recommendation: null, rankedDoctors: [] };
  }

  const recommendation = rankedDoctors.length > 0 ? rankedDoctors[0] : null;
  return {
    recommendation,
    rankedDoctors: rankedDoctors.slice(0, 5),
  };
});
