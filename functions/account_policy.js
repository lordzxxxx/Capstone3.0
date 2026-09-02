const functions = require('firebase-functions');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {ServerValue} = require('firebase-admin/database');
const crypto = require('crypto');
const {sendSystemEmail} = require('./mailer');
const {
  assertStrongPassword,
  generateTemporaryPassword,
} = require('./password_policy');
const {
  defaultPermissionsForRole,
  resolveRoleAssignment,
} = require('./rbac_policy');

if (!admin.apps.length) {
  admin.initializeApp();
}

// Keep this aligned with lib/firebase_helper.dart.
const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);
const REGISTRATION_INTENT_TTL_MS = 30 * 60 * 1000;

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

function isApprovedActiveProfile(data) {
  const approval = normalizeText(data?.approvalStatus || '');
  const status = normalizeText(data?.accountStatus || data?.status || '');
  return ['approved'].includes(approval) &&
    ['active', 'approved'].includes(status);
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

function profileText(value, field, {maxLength = 200, required = false} = {}) {
  if (value !== undefined && value !== null && typeof value !== 'string') {
    throw new functions.https.HttpsError(
        'invalid-argument',
        `${field} must be text.`,
    );
  }
  const text = String(value || '').trim();
  if ((required && !text) || text.length > maxLength ||
      (text.length > 0 && !/\S/.test(text))) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        `${field} is invalid.`,
    );
  }
  return text;
}

function assertBhwRegistrationProfile(profile, {
  assignedBarangay,
  assignedBarangayCode,
}) {
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'The BHW registration profile is required.',
    );
  }

  const firstName = profileText(profile.firstName, 'First name', {
    maxLength: 80,
    required: true,
  });
  const middleName = profileText(profile.middleName, 'Middle name', {
    maxLength: 80,
  });
  const lastName = profileText(profile.lastName, 'Last name', {
    maxLength: 80,
    required: true,
  });
  const suffix = profileText(profile.suffix, 'Suffix', {maxLength: 40});
  const contactNumber = profileText(profile.contactNumber, 'Contact number', {
    maxLength: 20,
    required: true,
  });
  if (!/^(?:\+63|0)\d{10}$/.test(contactNumber)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Contact number is invalid.',
    );
  }

  const dateOfBirth = profile.dateOfBirth;
  if (!dateOfBirth || typeof dateOfBirth.toMillis !== 'function') {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Date of birth is required.',
    );
  }
  const dateOfBirthMillis = dateOfBirth.toMillis();
  if (!Number.isFinite(dateOfBirthMillis) || dateOfBirthMillis > Date.now() ||
      dateOfBirthMillis < Date.now() - (130 * 366 * 24 * 60 * 60 * 1000)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Date of birth is invalid.',
    );
  }

  const sex = profileText(profile.sex, 'Sex', {maxLength: 16, required: true});
  if (!['Male', 'Female'].includes(sex)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Sex is invalid.',
    );
  }
  const civilStatus = profileText(profile.civilStatus, 'Civil status', {
    maxLength: 24,
    required: true,
  });
  if (!['Single', 'Married', 'Widowed', 'Separated'].includes(civilStatus)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Civil status is invalid.',
    );
  }
  const residentialAddress = profileText(
      profile.residentialAddress,
      'Residential address',
      {maxLength: 240, required: true},
  );

  const address = profile.address;
  if (!address || typeof address !== 'object' || Array.isArray(address)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Residential address details are required.',
    );
  }
  const province = profileText(address.province, 'Province', {
    maxLength: 80,
    required: true,
  });
  const municipality = profileText(address.municipality, 'Municipality', {
    maxLength: 120,
    required: true,
  });
  const residentialBarangay = profileText(address.barangay, 'Barangay', {
    maxLength: 120,
    required: true,
  });
  const residentialBarangayCode = normalizeBarangayCode(address.barangayCode);
  if (!residentialBarangayCode || residentialBarangayCode.length > 80) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Residential barangay is invalid.',
    );
  }
  const residentialSitio = profileText(address.sitio, 'Residential sitio', {
    maxLength: 120,
  });

  const bhw = profile.bhw;
  if (!bhw || typeof bhw !== 'object' || Array.isArray(bhw)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'BHW information is required.',
    );
  }
  const bhwId = profileText(bhw.bhwId, 'BHW ID', {maxLength: 64});
  const assignedSitio = profileText(bhw.assignedSitio, 'Assigned sitio', {
    maxLength: 120,
  });
  const yearsOfService = bhw.yearsOfService;
  if (!Number.isInteger(yearsOfService) || yearsOfService < 0 ||
      yearsOfService > 80) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Years of service is invalid.',
    );
  }
  const dateStarted = bhw.dateStarted;
  if (dateStarted !== '' && dateStarted !== null && dateStarted !== undefined &&
      (!dateStarted || typeof dateStarted.toMillis !== 'function' ||
        dateStarted.toMillis() > Date.now())) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Date started is invalid.',
    );
  }
  const employmentStatus = profileText(
      bhw.employmentStatus,
      'Employment status',
      {maxLength: 24, required: true},
  );
  if (!['Active', 'Volunteer', 'Contractual'].includes(employmentStatus)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Employment status is invalid.',
    );
  }

  const declarations = profile.declarations;
  if (!declarations || typeof declarations !== 'object' ||
      declarations.informationCertified !== true ||
      declarations.choReviewAcknowledged !== true ||
      declarations.privacyPolicyAccepted !== true ||
      declarations.dataPrivacyActAccepted !== true) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'All registration declarations must be accepted.',
    );
  }

  const fullName = [firstName, middleName, lastName, suffix]
      .filter(Boolean)
      .join(' ');
  return {
    status: 'Pending Approval',
    firstName,
    middleName,
    lastName,
    suffix,
    fullName,
    dateOfBirth,
    sex,
    civilStatus,
    contactNumber,
    residentialAddress,
    address: {
      province,
      municipality,
      barangay: residentialBarangay,
      barangayCode: residentialBarangayCode,
      sitio: residentialSitio,
    },
    bhw: {
      bhwId,
      assignedBarangay,
      assignedBarangayCode,
      assignedSitio,
      yearsOfService,
      dateStarted: dateStarted || '',
      position: 'Barangay Health Worker',
      employmentStatus,
    },
    declarations: {
      informationCertified: true,
      choReviewAcknowledged: true,
      privacyPolicyAccepted: true,
      dataPrivacyActAccepted: true,
      acceptedAt: FieldValue.serverTimestamp(),
    },
    approvedBy: null,
    approvedAt: null,
    rejectionReason: null,
    lastLogin: null,
  };
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

  const safeDoctorName = safeText(doctorName, 'Doctor');
  const patientName = safeText(
      referral?.patientName || referral?.patientInformation?.fullName,
      'Patient',
  );
  const bhwName = safeText(
      referral?.createdByName || referral?.bhwName || referral?.createdByEmail,
      'Referring BHW',
  );
  const barangay = safeText(
      referral?.barangay || referral?.barangayName,
      'Not provided',
  );
  const referralDate = timestampText(
      referral?.referralDateTime || referral?.referralDate ||
      referral?.createdAt || new Date(),
  );
  const referralReason = safeText(
      referral?.referralReason || referral?.reason ||
      referral?.chiefComplaint,
      'Not provided',
  );
  const priority = safeText(referral?.priority || referral?.referralPriority,
      'Routine');
  const status = safeText(referral?.status, 'assigned');
  const appUrl = String(
      process.env.APP_URL || 'https://www.ai-dsuhis.com',
  ).replace(/\/$/, '');
  const portalLink = `${appUrl}/doctor/referrals?referralId=${encodeURIComponent(referralId)}`;

  const subject = 'New Patient Referral Assigned – AI-DSUHIS';
  const text = [
    `Hello Dr. ${safeDoctorName},`,
    '',
    'A new patient referral has been automatically assigned to you in AI-DSUHIS.',
    '',
    `Doctor: ${safeDoctorName}`,
    `Patient: ${patientName}`,
    `Referral Reference: ${referralId}`,
    `Referral Date and Time: ${referralDate}`,
    `Referred From: ${barangay}`,
    `Referring BHW: ${bhwName}`,
    `Referral Reason: ${referralReason}`,
    `Priority: ${priority}`,
    `Assigned Doctor: ${safeDoctorName}`,
    `Status: ${status}`,
    '',
    `View Referral: ${portalLink}`,
    '',
    'For privacy, clinical diagnosis, history, and AI analysis are available only after secure sign-in.',
  ].join('\n');

  const html = `
    <div style="font-family: Arial, sans-serif; color: #0A1F24; line-height: 1.5;">
      <h2 style="margin-bottom: 8px;">New Referral Assignment</h2>
      <p>Hello Dr. ${htmlEscape(safeDoctorName)},</p>
      <p>A new patient referral has been automatically assigned to you in AI-DSUHIS.</p>
      <table style="border-collapse: collapse; width: 100%; max-width: 640px;">
        <tr><td style="padding: 6px 8px; font-weight: 600;">Doctor</td><td style="padding: 6px 8px;">${htmlEscape(safeDoctorName)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Patient</td><td style="padding: 6px 8px;">${htmlEscape(patientName)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Referral reference</td><td style="padding: 6px 8px;">${htmlEscape(referralId)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Referral date and time</td><td style="padding: 6px 8px;">${htmlEscape(referralDate)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Referred from</td><td style="padding: 6px 8px;">${htmlEscape(barangay)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Referring BHW</td><td style="padding: 6px 8px;">${htmlEscape(bhwName)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Referral reason</td><td style="padding: 6px 8px;">${htmlEscape(referralReason)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Priority</td><td style="padding: 6px 8px;">${htmlEscape(priority)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Assigned doctor</td><td style="padding: 6px 8px;">${htmlEscape(safeDoctorName)}</td></tr>
        <tr><td style="padding: 6px 8px; font-weight: 600;">Status</td><td style="padding: 6px 8px;">${htmlEscape(status)}</td></tr>
      </table>
      <p style="margin-top: 12px;"><a href="${htmlEscape(portalLink)}">Open the secure doctor portal</a></p>
      <p style="font-size: 12px; color: #4B6075;">Clinical diagnosis, history, and AI analysis are available only after secure sign-in.</p>
    </div>
  `;

  const result = await sendSystemEmail({
    to: normalizedEmail,
    subject,
    text,
    html,
  });
  return {
    sent: result.sent,
    reason: result.reason,
    message: result.sent
      ? 'Assignment email sent from the AI-DSUHIS system mailer.'
      : 'Assignment persisted, but the system email could not be sent.',
  };
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
  if (!context.auth || !isApprovedActiveProfile(userData) ||
      !['CHO', 'CHO_ADMIN', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'].includes(role)) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Only CHO operators can use this action.',
    );
  }
}

function ensureChoAdmin(context, userData) {
  const role = normalizeRole(userData.role || '');
  if (!context.auth || !isApprovedActiveProfile(userData) ||
      !['CHO_ADMIN', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'].includes(role)) {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Only the CHO Admin can manage accounts, approvals, or assignments.',
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
    updatedAt: FieldValue.serverTimestamp(),
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
        if (unavailable || approvalStatus !== 'approved' ||
            !['active', 'approved'].includes(accountStatus)) return null;

        const score = Math.max(0, 100 - workload * 10);
        const reasons = [
          `${workload} active referral${workload === 1 ? '' : 's'} in workload`,
          'Approved and active doctor account',
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
  const approvalStatus = isBarangayScoped
    ? (previousData?.approvalStatus || 'pending')
    : 'approved';
  const accountStatus = isBarangayScoped
    ? (previousData?.accountStatus || 'pending_approval')
    : (previousData?.accountStatus || 'active');
  const accessRoleKey = previousData?.accessRoleKey || normalizedRole;

  return {
    username,
    usernameLower: normalizeText(username),
    email,
    emailLower: normalizeText(email),
    uid,
    role: normalizedRole,
    accessRoleKey,
    permissions: previousData?.permissions || defaultPermissionsForRole(normalizedRole),
    accessScope: accessScopeForRole(normalizedRole),
    organizationLevel: isBarangayScoped ? 'barangay' : 'citywide',
    dataVisibilityStartAt:
      previousData?.dataVisibilityStartAt ||
      FieldValue.serverTimestamp(),
    barangay: isBarangayScoped ?
      barangay :
      FieldValue.delete(),
    barangayCode: isBarangayScoped ?
      normalizedBarangayCode :
      FieldValue.delete(),
    barangayDistrict: isBarangayScoped ?
      barangayDistrict :
      FieldValue.delete(),
    barangayVerified: isBarangayScoped,
    barangayPath: barangayPath || FieldValue.delete(),
    barangayUserPath: barangayUserPath || FieldValue.delete(),
    approvalStatus,
    accountStatus,
    isApproved: approvalStatus.toLowerCase() === 'approved',
    createdAt:
      previousData?.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
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
      FieldValue.serverTimestamp(),
    specialization,
    doctorSpecialization: specialization,
    specialty: specialization,
    availability,
    doctorAvailability: availability,
    approvalStatus: previousData?.approvalStatus || 'approved',
    accountStatus: previousData?.accountStatus || 'active',
    doctorRegistrySource: 'cho_registry',
    doctorRegisteredByUid: registeredByUid,
    barangay: FieldValue.delete(),
    barangayCode: FieldValue.delete(),
    barangayDistrict: FieldValue.delete(),
    barangayVerified: false,
    barangayPath: FieldValue.delete(),
    barangayUserPath: FieldValue.delete(),
    createdAt:
      previousData?.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function buildBarangayDirectoryPayload(data) {
  return {
    barangay: String(data?.barangay || '').trim(),
    barangayCode: normalizeBarangayCode(data?.barangayCode || ''),
    barangayDistrict: String(data?.barangayDistrict || '').trim(),
    updatedAt: FieldValue.serverTimestamp(),
    lastUserSyncAt: FieldValue.serverTimestamp(),
  };
}

function buildBarangayUserPayload(uid, data) {
  const normalizedRole = normalizeRole(data?.role || '');
  const normalizedBarangayCode = normalizeBarangayCode(data?.barangayCode || '');
  const mirroredProfile = {};
  for (const field of [
    'status', 'firstName', 'middleName', 'lastName', 'suffix', 'fullName',
    'dateOfBirth', 'sex', 'civilStatus', 'contactNumber',
    'residentialAddress', 'address', 'bhw', 'declarations', 'approvedBy',
    'approvedAt', 'rejectionReason', 'lastLogin',
  ]) {
    if (data?.[field] !== undefined) {
      mirroredProfile[field] = data[field];
    }
  }

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
      FieldValue.serverTimestamp(),
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
      data?.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...mirroredProfile,
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
    updatedAt: FieldValue.serverTimestamp(),
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
      updatedAt: FieldValue.serverTimestamp(),
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
  const email = String(data?.email || '').trim().toLowerCase();
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

// Public registration must create the Firebase Auth account on the trusted
// backend. Creating it directly from the client would make the stronger
// password policy advisory: a caller could bypass the UI and use the Auth SDK
// with a weak password. The short-lived intent binds the subsequent profile
// completion to this validated registration attempt.
exports.createRegistrationAccount = functions.https.onCall(async (data, context) => {
  if (context.auth) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'Sign out before starting a new registration.',
    );
  }

  const email = String(data?.email || '').trim().toLowerCase();
  const username = String(data?.username || '').trim();
  const role = normalizeRole(data?.role || '');
  const barangayCode = normalizeBarangayCode(data?.barangayCode || '');
  const password = data?.password;

  if (!isValidEmail(email) || email.length > 320) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'A valid email address is required.',
    );
  }
  if (username.length < 3 || username.length > 80 || !/\S/.test(username)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Username must be between 3 and 80 characters.',
    );
  }
  if (role !== 'BHW') {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'CHO accounts are created by the CHO Admin. Submit a BHW registration request here.',
    );
  }
  if (role === 'BHW' && !barangayCode) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Barangay assignment is required for BHW accounts.',
    );
  }
  try {
    assertStrongPassword(password);
  } catch (_) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Password must be 8 to 128 characters and include uppercase, lowercase, a number, and a special character.',
    );
  }

  let userRecord;
  try {
    userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: username,
    });
  } catch (error) {
    if (error?.code === 'auth/email-already-exists') {
      throw new functions.https.HttpsError(
          'already-exists',
          'This account is already registered. Please log in instead.',
      );
    }
    if (error?.code === 'auth/invalid-email') {
      throw new functions.https.HttpsError(
          'invalid-argument',
          'A valid email address is required.',
      );
    }
    console.error('createRegistrationAccount Auth creation failed', {
      code: error?.code || 'unknown',
    });
    throw new functions.https.HttpsError(
        'internal',
        'Unable to create the account right now. Please try again.',
    );
  }

  const registrationNonce = crypto.randomBytes(32).toString('hex');
  try {
    await db.collection('registration_intents').doc(userRecord.uid).set({
      uid: userRecord.uid,
      email,
      emailLower: email,
      username,
      usernameLower: normalizeText(username),
      role,
      barangayCode,
      registrationNonce,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + REGISTRATION_INTENT_TTL_MS,
      ),
    });
  } catch (error) {
    try {
      await admin.auth().deleteUser(userRecord.uid);
    } catch (rollbackError) {
      console.error('createRegistrationAccount Auth rollback failed', {
        uid: userRecord.uid,
        code: rollbackError?.code || 'unknown',
      });
    }
    console.error('createRegistrationAccount intent write failed', {
      uid: userRecord.uid,
      code: error?.code || 'unknown',
    });
    throw new functions.https.HttpsError(
        'internal',
        'Unable to complete registration right now. Please try again.',
    );
  }

  let customToken;
  try {
    customToken = await admin.auth().createCustomToken(userRecord.uid);
  } catch (error) {
    await db.collection('registration_intents').doc(userRecord.uid).delete();
    try {
      await admin.auth().deleteUser(userRecord.uid);
    } catch (rollbackError) {
      console.error('createRegistrationAccount token rollback failed', {
        uid: userRecord.uid,
        code: rollbackError?.code || 'unknown',
      });
    }
    console.error('createRegistrationAccount token creation failed', {
      uid: userRecord.uid,
      code: error?.code || 'unknown',
    });
    throw new functions.https.HttpsError(
        'internal',
        'Unable to complete registration right now. Please try again.',
    );
  }

  return {
    success: true,
    uid: userRecord.uid,
    registrationNonce,
    customToken,
  };
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
  const email = String(data?.email || '').trim().toLowerCase();
  const role = normalizeRole(data?.role || '');
  const barangay = String(data?.barangay || '').trim();
  const barangayCode = normalizeBarangayCode(data?.barangayCode || '');
  const barangayDistrict = String(data?.barangayDistrict || '').trim();
  const registrationNonce = String(data?.registrationNonce || '').trim();

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

  if (!/^[a-f0-9]{64}$/i.test(registrationNonce)) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'Registration has expired. Please start again.',
    );
  }

  if (!isValidEmail(email) || email.length > 320) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'A valid email address is required.',
    );
  }

  if (username.length < 3 || username.length > 80) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Username must be between 3 and 80 characters.',
    );
  }

  if (role !== 'BHW') {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'CHO accounts are created by the CHO Admin. Submit a BHW registration request here.',
    );
  }

  if (isBarangayScopedRole(role) && !barangayCode) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Barangay assignment is required for BHW accounts.',
    );
  }

  if (data?.profile !== undefined && role !== 'BHW') {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Detailed registration profiles are only supported for BHW accounts.',
    );
  }
  const detailedBhwProfile = data?.profile === undefined
    ? null
    : assertBhwRegistrationProfile(data.profile, {
      assignedBarangay: barangay,
      assignedBarangayCode: barangayCode,
    });

  const userRef = db.collection('users').doc(uid);
  const emailLockRef = db.collection('registration_email_locks').doc(normalizeText(email));
  const usernameLockRef = db.collection('registration_username_locks').doc(normalizeText(username));
  const barangayLockRef = barangayCode
      ? db.collection('registration_barangay_locks').doc(barangayCode)
      : null;
  const barangayStatusRef = barangayCode
      ? db.collection('barangay_registration_status').doc(barangayCode)
      : null;
  const registrationIntentRef = db.collection('registration_intents').doc(uid);

  let previousData = null;
  let completedPayload = null;
  await db.runTransaction(async (transaction) => {
    const [intentSnap, userSnap, emailLockSnap, usernameLockSnap, barangayLockSnap] = await Promise.all([
      transaction.get(registrationIntentRef),
      transaction.get(userRef),
      transaction.get(emailLockRef),
      transaction.get(usernameLockRef),
      barangayLockRef ? transaction.get(barangayLockRef) : Promise.resolve(null),
    ]);

    const intent = intentSnap.exists ? intentSnap.data() : null;
    const intentExpiry = intent?.expiresAt;
    if (!intent ||
        intent.registrationNonce !== registrationNonce ||
        intent.uid !== uid ||
        intent.emailLower !== normalizeText(email) ||
        intent.usernameLower !== normalizeText(username) ||
        intent.role !== role ||
        normalizeBarangayCode(intent.barangayCode || '') !== barangayCode ||
        !intentExpiry ||
        intentExpiry.toMillis() <= Date.now()) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'Registration has expired. Please start again.',
      );
    }

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

    const basePayload = buildRootUserPayload({
      uid,
      username,
      email,
      role,
      barangay,
      barangayCode,
      barangayDistrict,
      previousData,
    });
    const payload = detailedBhwProfile
      ? {...basePayload, ...detailedBhwProfile}
      : basePayload;
    completedPayload = payload;

    transaction.set(userRef, payload, { merge: true });
    transaction.delete(registrationIntentRef);
    transaction.set(emailLockRef, {
      uid,
      email,
      emailLower: normalizeText(email),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(usernameLockRef, {
      uid,
      username,
      usernameLower: normalizeText(username),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    if (barangayLockRef && isBarangayScopedRole(role)) {
      transaction.set(barangayLockRef, {
        uid,
        barangay,
        barangayCode,
        barangayDistrict,
        username,
        email,
        accountStatus: payload.accountStatus,
        approvalStatus: payload.approvalStatus,
        updatedAt: FieldValue.serverTimestamp(),
        source: 'registration-complete',
      }, { merge: true });
    }

    if (barangayStatusRef && isBarangayScopedRole(role)) {
      transaction.set(barangayStatusRef, buildBarangayRegistrationStatusPayload({
        uid,
        barangay,
        barangayCode,
        barangayDistrict,
        accountStatus: payload.accountStatus,
        approvalStatus: payload.approvalStatus,
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

    if (detailedBhwProfile) {
      transaction.set(
          db.collection('bhw_registration_requests').doc(uid),
          {
            ...payload,
            requestId: uid,
            applicantUid: uid,
            requestType: 'BHW_ACCOUNT_REGISTRATION',
            submissionStatus: 'submitted',
            submittedAt: FieldValue.serverTimestamp(),
            profilePath: userRef.path,
            barangayProfilePath: barangayUserDocRef(barangayCode, uid).path,
            source: 'public-bhw-registration',
          },
      );
    }
  });

  const existingAuthUser = await admin.auth().getUser(uid);
  const updatedClaims = {...(existingAuthUser.customClaims || {})};
  const isApprovedAccount =
    completedPayload.approvalStatus.toLowerCase() === 'approved' &&
    ['active', 'approved'].includes(completedPayload.accountStatus.toLowerCase());
  if (isApprovedAccount) {
    updatedClaims.role = role;
  } else {
    delete updatedClaims.role;
    if (Array.isArray(updatedClaims.roles)) {
      updatedClaims.roles = updatedClaims.roles.filter((claimRole) =>
        normalizeRole(claimRole) !== role,
      );
      if (updatedClaims.roles.length === 0) {
        delete updatedClaims.roles;
      }
    }
  }
  await admin.auth().setCustomUserClaims(uid, updatedClaims);

  try {
    await admin.database().ref(`users/${uid}`).update({
      uid,
      username,
      email,
      role: completedPayload.role,
      accessScope: accessScopeForRole(role),
      barangay: isBarangayScopedRole(role) ? barangay : null,
      barangayCode: isBarangayScopedRole(role) ? barangayCode : null,
      barangayDistrict: isBarangayScopedRole(role) ? barangayDistrict : null,
      approvalStatus: completedPayload.approvalStatus,
      accountStatus: completedPayload.accountStatus,
      updatedAt: ServerValue.TIMESTAMP,
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

// Firestore Enterprise requires Eventarc/2nd-gen triggers. This uses a new
// export name because Firebase does not support upgrading an existing 1st-gen
// function in place; the old trigger is removed after this replacement is live.
exports.syncAccountGovernanceLocksV2 = onDocumentWritten({
  document: 'users/{uid}',
  database: FIRESTORE_DATABASE_ID,
  region: 'us-central1',
}, async (event) => {
  const change = event.data;
  const uid = event.params.uid;
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
      updatedAt: FieldValue.serverTimestamp(),
      source: 'users-sync',
    }, { merge: true });
  }

  if (username) {
    await db.collection('registration_username_locks').doc(normalizeText(username)).set({
      uid,
      username,
      usernameLower: normalizeText(username),
      updatedAt: FieldValue.serverTimestamp(),
      source: 'users-sync',
    }, { merge: true });
  }

  await syncBarangayLock(uid, beforeData, afterData);
  await syncBarangayUserMirror(uid, beforeData, afterData);
  await syncBarangayRegistrationStatus(beforeData, afterData);
  return null;
});

async function provisionManagedAccount(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to create a managed account.',
    );
  }

  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  ensureChoAdmin(context, callerDoc.data() || {});

  const role = normalizeRole(data?.role || '');
  const fullName = profileText(data?.fullName || data?.displayName, 'Full name', {
    maxLength: 160,
    required: true,
  });
  const email = String(data?.email || '').trim().toLowerCase();
  if (!isValidEmail(email)) {
    throw new functions.https.HttpsError('invalid-argument', 'A valid email address is required.');
  }
  if (!['CHO', 'DOCTOR'].includes(role)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Managed accounts can only be CHO or DOCTOR accounts. The main CHO Admin is not self-created.',
    );
  }
  const accessRole = await resolveRoleAssignment({
    role,
    accessRoleKey: data?.accessRoleKey || role,
  });

  const specialization = role === 'DOCTOR'
    ? doctorSpecializationValue(data || {})
    : '';
  const availability = role === 'DOCTOR'
    ? doctorAvailabilityValue(data || {})
    : 'available';
  if (!['available', 'busy', 'limited', 'unavailable'].includes(availability)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Availability must be available, busy, limited, or unavailable.',
    );
  }
  const accountStatus = normalizeText(data?.accountStatus || 'active');
  if (!['active', 'disabled'].includes(accountStatus)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Account status must be active or disabled.',
    );
  }

  let userRecord;
  let created = false;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw doctorRegistrationError(error, 'Failed to find the account.');
    // The random password is only used to satisfy Auth account creation. It
    // is never returned, logged, or stored; the activation link is the only
    // onboarding path shown to the new user.
    userRecord = await admin.auth().createUser({
      email,
      password: generateTemporaryPassword(),
      displayName: fullName,
      disabled: accountStatus === 'disabled',
    });
    created = true;
  }

  const userRef = db.collection('users').doc(userRecord.uid);
  const emailLockRef = db.collection('registration_email_locks').doc(normalizeText(email));
  const usernameLockRef = db.collection('registration_username_locks').doc(normalizeText(fullName));
  const existingSnap = await userRef.get();
  const existingData = existingSnap.data() || {};
  const existingRole = normalizeRole(existingData.role || '');
  if (existingRole && existingRole !== role) {
    throw new functions.https.HttpsError(
        'already-exists',
        'This email is already linked to a different account role.',
    );
  }

  for (const [lockRef, field, message] of [
    [emailLockRef, 'email', 'This email is already linked to another account.'],
    [usernameLockRef, 'username', 'This name is already linked to another account.'],
  ]) {
    const lockSnap = await lockRef.get();
    if (lockSnap.exists && String(lockSnap.data()?.uid || '') !== userRecord.uid) {
      throw new functions.https.HttpsError('already-exists', message);
    }
  }

  const payload = {
    uid: userRecord.uid,
    username: fullName,
    usernameLower: normalizeText(fullName),
    fullName,
    displayName: fullName,
    email,
    emailLower: normalizeText(email),
    role,
    accessRoleKey: accessRole.roleKey,
    permissions: accessRole.permissions,
    accessScope: 'citywide',
    organizationLevel: 'citywide',
    approvalStatus: 'approved',
    accountStatus,
    status: accountStatus === 'active' ? 'Active' : 'Disabled',
    isApproved: true,
    dataVisibilityStartAt: existingData.dataVisibilityStartAt || FieldValue.serverTimestamp(),
    ...(role === 'DOCTOR' ? {
      specialization,
      doctorSpecialization: specialization,
      specialty: specialization,
      availability,
      doctorAvailability: availability,
      doctorRegistrySource: 'cho_admin',
    } : {}),
    createdByUid: existingData.createdByUid || context.auth.uid,
    createdAt: existingData.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  try {
    await db.runTransaction(async (transaction) => {
      transaction.set(userRef, payload, {merge: true});
      transaction.set(emailLockRef, {
        uid: userRecord.uid,
        email,
        emailLower: normalizeText(email),
        updatedAt: FieldValue.serverTimestamp(),
        source: 'cho-admin',
      }, {merge: true});
      transaction.set(usernameLockRef, {
        uid: userRecord.uid,
        username: fullName,
        usernameLower: normalizeText(fullName),
        updatedAt: FieldValue.serverTimestamp(),
        source: 'cho-admin',
      }, {merge: true});
    });

    await admin.auth().updateUser(userRecord.uid, {
      displayName: fullName,
      disabled: accountStatus === 'disabled',
    });
    const freshAuth = await admin.auth().getUser(userRecord.uid);
    await admin.auth().setCustomUserClaims(userRecord.uid, {
      ...(freshAuth.customClaims || {}),
      role: role.toLowerCase(),
      approvalStatus: 'approved',
      accountStatus,
    });
    await admin.database().ref(`users/${userRecord.uid}`).update({
      uid: userRecord.uid,
      username: fullName,
      fullName,
      email,
      role,
      accessRoleKey: accessRole.roleKey,
      permissions: accessRole.permissions,
      accessScope: 'citywide',
      approvalStatus: 'approved',
      accountStatus,
      ...(role === 'DOCTOR' ? {
        specialization,
        doctorSpecialization: specialization,
        availability,
        doctorAvailability: availability,
      } : {}),
      updatedAt: ServerValue.TIMESTAMP,
    });
  } catch (error) {
    if (created) {
      try { await admin.auth().deleteUser(userRecord.uid); } catch (_) {}
    }
    throw doctorRegistrationError(error, 'Managed account creation failed.');
  }

  let resetLink = null;
  try {
    resetLink = await admin.auth().generatePasswordResetLink(email);
  } catch (error) {
    console.error('Managed account activation link generation failed', {
      uid: userRecord.uid,
      code: error?.code || 'unknown',
    });
  }

  const activationEmail = resetLink
    ? await sendSystemEmail({
      to: email,
      subject: 'Your AI-DSUHIS Account Is Ready',
      text: [
        `Hello ${fullName},`,
        '',
        'An AI-DSUHIS account has been created for you by the City Health Office Administrator.',
        '',
        'Account Details',
        `Email: ${email}`,
        `Role: ${role}`,
        '',
        'Please use the secure link below to activate your account and create your password.',
        `ACTIVATE ACCOUNT / SET PASSWORD: ${resetLink}`,
        '',
        'After setting your password, you can sign in to AI-DSUHIS using your registered email.',
        'For security, do not share your account credentials.',
        '',
        'Thank you,',
        'AI-DSUHIS',
        'City Health Office',
        '',
        'This is an automated system notification.',
      ].join('\n'),
      html: `<p>Hello ${htmlEscape(fullName)},</p><p>An AI-DSUHIS account has been created for you by the City Health Office Administrator.</p><h3>Account Details</h3><p>Email: ${htmlEscape(email)}<br>Role: ${htmlEscape(role)}</p><p>Please use the secure link below to activate your account and create your password.</p><p><a href="${htmlEscape(resetLink)}">ACTIVATE ACCOUNT / SET PASSWORD</a></p><p>After setting your password, you can sign in to AI-DSUHIS using your registered email.</p><p>For security, do not share your account credentials.</p><p>Thank you,<br>AI-DSUHIS<br>City Health Office</p><p>This is an automated system notification.</p>`,
    })
    : {sent: false, reason: 'activation_link_unavailable'};

  await db.collection('audit_logs').add({
    action: 'managed_account_created',
    actorUid: context.auth.uid,
    targetUid: userRecord.uid,
    role,
    accessRoleKey: accessRole.roleKey,
    accountStatus,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    created,
    uid: userRecord.uid,
    fullName,
    email,
    role,
    accessRoleKey: accessRole.roleKey,
    specialization,
    availability,
    accountStatus,
    approvalStatus: 'approved',
    activationEmailSent: activationEmail.sent,
    activationEmailReason: activationEmail.reason,
  };
}

exports.createChoAccount = functions.https.onCall(async (data, context) => {
  try {
    return await provisionManagedAccount(data || {}, context);
  } catch (error) {
    throw doctorRegistrationError(error, 'Managed account creation failed.');
  }
});

exports.reviewBhwRegistration = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be signed in to review registrations.');
  }
  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  ensureChoAdmin(context, callerDoc.data() || {});

  const uid = String(data?.uid || '').trim();
  const approved = data?.approved === true;
  const rejectionReason = String(data?.rejectionReason || '').trim();
  if (!uid) throw new functions.https.HttpsError('invalid-argument', 'Applicant UID is required.');
  if (!approved && !rejectionReason) {
    throw new functions.https.HttpsError('invalid-argument', 'A rejection reason is required.');
  }

  const userRef = db.collection('users').doc(uid);
  const requestRef = db.collection('bhw_registration_requests').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw new functions.https.HttpsError('not-found', 'The BHW account was not found.');
  const userData = userSnap.data() || {};
  if (normalizeRole(userData.role || '') !== 'BHW') {
    throw new functions.https.HttpsError('failed-precondition', 'Only BHW registrations can be reviewed here.');
  }

  const nextApproval = approved ? 'approved' : 'rejected';
  const nextAccount = approved ? 'active' : 'rejected';
  const nextStatus = approved ? 'Active' : 'Rejected';
  const updatePayload = {
    accessRoleKey: 'BHW',
    permissions: defaultPermissionsForRole('BHW'),
    approvalStatus: nextApproval,
    accountStatus: nextAccount,
    status: nextStatus,
    isApproved: approved,
    ...(approved ? {
      approvedBy: context.auth.uid,
      approvedAt: FieldValue.serverTimestamp(),
    } : {
      reviewedBy: context.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      rejectionReason,
    }),
    updatedBy: context.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(userRef, updatePayload, {merge: true});
  batch.set(requestRef, {
    ...updatePayload,
    reviewStatus: nextApproval,
    reviewCompletedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  const barangayCode = normalizeBarangayCode(userData.barangayCode || '');
  if (barangayCode) {
    batch.set(barangayUserDocRef(barangayCode, uid), {
      ...updatePayload,
      approvalStatus: nextApproval,
      accountStatus: nextAccount,
      barangayCode,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();

  const authUser = await admin.auth().getUser(uid);
  const claims = {...(authUser.customClaims || {})};
  if (approved) {
    claims.role = 'bhw';
    claims.approvalStatus = 'approved';
    claims.accountStatus = 'active';
  } else {
    delete claims.role;
    delete claims.approvalStatus;
    delete claims.accountStatus;
    if (Array.isArray(claims.roles)) {
      claims.roles = claims.roles.filter((role) => normalizeRole(role) !== 'BHW');
      if (!claims.roles.length) delete claims.roles;
    }
  }
  await admin.auth().setCustomUserClaims(uid, claims);
  await admin.auth().updateUser(uid, {disabled: !approved});
  await admin.database().ref(`users/${uid}`).update({
    role: 'BHW',
    accessRoleKey: 'BHW',
    permissions: defaultPermissionsForRole('BHW'),
    status: nextStatus,
    approvalStatus: nextApproval,
    accountStatus: nextAccount,
    isApproved: approved,
    ...(approved ? {approvedBy: context.auth.uid} : {
      reviewedBy: context.auth.uid,
      rejectionReason,
    }),
    updatedAt: ServerValue.TIMESTAMP,
  });

  const applicantEmail = String(userData.email || '').trim().toLowerCase();
  if (approved && isValidEmail(applicantEmail)) {
    await sendSystemEmail({
      to: applicantEmail,
      subject: 'Your AI-DSUHIS BHW registration was approved',
      text: 'Your BHW registration was approved by the CHO Admin. You may now sign in to AI-DSUHIS.',
      html: '<p>Your BHW registration was approved by the CHO Admin.</p><p>You may now sign in to AI-DSUHIS.</p>',
    });
  }

  await db.collection('audit_logs').add({
    action: approved ? 'bhw_registration_approved' : 'bhw_registration_rejected',
    actorUid: context.auth.uid,
    targetUid: uid,
    reason: approved ? null : rejectionReason,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {success: true, uid, approvalStatus: nextApproval, accountStatus: nextAccount};
});

exports.updateChoAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'You must be signed in to manage accounts.');
  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  ensureChoAdmin(context, callerDoc.data() || {});

  const uid = String(data?.uid || '').trim();
  if (!uid) throw new functions.https.HttpsError('invalid-argument', 'Target UID is required.');
  if (uid === context.auth.uid) {
    throw new functions.https.HttpsError('failed-precondition', 'The main CHO Admin account cannot be changed from this screen.');
  }
  const targetRef = db.collection('users').doc(uid);
  const targetSnap = await targetRef.get();
  if (!targetSnap.exists) throw new functions.https.HttpsError('not-found', 'The target account was not found.');
  const current = targetSnap.data() || {};
  const currentRole = normalizeRole(current.role || '');
  if (['CHO_ADMIN', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN'].includes(currentRole)) {
    throw new functions.https.HttpsError('permission-denied', 'Privileged CHO Admin accounts are managed through deployment controls.');
  }

  const nextRole = data?.role === undefined ? currentRole : normalizeRole(data.role);
  if (!['BHW', 'CHO', 'DOCTOR'].includes(nextRole)) {
    throw new functions.https.HttpsError('invalid-argument', 'Role must be BHW, CHO, or DOCTOR.');
  }
  const accessRole = await resolveRoleAssignment({
    role: nextRole,
    accessRoleKey: data?.accessRoleKey || current.accessRoleKey || nextRole,
  });
  const nextAccountStatus = data?.accountStatus === undefined
    ? normalizeText(current.accountStatus || 'active')
    : normalizeText(data.accountStatus);
  if (!['active', 'disabled', 'rejected', 'pending_approval'].includes(nextAccountStatus)) {
    throw new functions.https.HttpsError('invalid-argument', 'Account status is invalid.');
  }
  if (nextRole === 'BHW' && nextAccountStatus === 'active' &&
      normalizeText(current.approvalStatus || '') !== 'approved') {
    throw new functions.https.HttpsError('failed-precondition', 'A BHW must be approved before activation.');
  }

  const barangayCode = data?.barangayCode === null
    ? ''
    : normalizeBarangayCode(data?.barangayCode === undefined ? current.barangayCode : data.barangayCode);
  const barangay = data?.barangay === null
    ? ''
    : String(data?.barangay === undefined ? current.barangay || '' : data.barangay).trim();
  const barangayDistrict = data?.barangayDistrict === null
    ? ''
    : String(data?.barangayDistrict === undefined ? current.barangayDistrict || '' : data.barangayDistrict).trim();
  if (nextRole === 'BHW' && nextAccountStatus === 'active' && !barangayCode) {
    throw new functions.https.HttpsError('failed-precondition', 'An active BHW must have an assigned barangay.');
  }
  const specialization = nextRole === 'DOCTOR'
    ? doctorSpecializationValue({specialization: data?.specialization || current.specialization})
    : '';
  const availability = nextRole === 'DOCTOR'
    ? doctorAvailabilityValue({availability: data?.availability || current.availability})
    : 'available';

  const payload = {
    role: nextRole,
    accessRoleKey: accessRole.roleKey,
    permissions: accessRole.permissions,
    accessScope: nextRole === 'BHW' ? 'barangay' : 'citywide',
    organizationLevel: nextRole === 'BHW' ? 'barangay' : 'citywide',
    accountStatus: nextAccountStatus,
    status: nextAccountStatus === 'active' ? 'Active' : nextAccountStatus,
    isApproved: normalizeText(current.approvalStatus || '') === 'approved',
    barangay: nextRole === 'BHW' ? barangay : FieldValue.delete(),
    barangayCode: nextRole === 'BHW' ? barangayCode : FieldValue.delete(),
    barangayDistrict: nextRole === 'BHW' ? barangayDistrict : FieldValue.delete(),
    barangayVerified: nextRole === 'BHW' && !!barangayCode,
    ...(nextRole === 'DOCTOR' ? {
      specialization,
      doctorSpecialization: specialization,
      specialty: specialization,
      availability,
      doctorAvailability: availability,
    } : {}),
    updatedBy: context.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await targetRef.set(payload, {merge: true});

  const targetAuth = await admin.auth().getUser(uid);
  const claims = {...(targetAuth.customClaims || {})};
  if (nextAccountStatus === 'active' && ['approved', 'active'].includes(normalizeText(current.approvalStatus || ''))) {
    claims.role = nextRole.toLowerCase();
    claims.approvalStatus = 'approved';
    claims.accountStatus = 'active';
  } else {
    delete claims.role;
    delete claims.approvalStatus;
    delete claims.accountStatus;
  }
  await admin.auth().setCustomUserClaims(uid, claims);
  await admin.auth().updateUser(uid, {disabled: nextAccountStatus !== 'active'});
  await admin.database().ref(`users/${uid}`).update({
    role: nextRole,
    accessRoleKey: accessRole.roleKey,
    permissions: accessRole.permissions,
    accessScope: nextRole === 'BHW' ? 'barangay' : 'citywide',
    accountStatus: nextAccountStatus,
    approvalStatus: current.approvalStatus || 'approved',
    ...(nextRole === 'BHW' ? {barangay, barangayCode, barangayDistrict} : {
      barangay: null,
      barangayCode: null,
      barangayDistrict: null,
    }),
    ...(nextRole === 'DOCTOR' ? {specialization, availability} : {}),
    updatedAt: ServerValue.TIMESTAMP,
  });
  await db.collection('audit_logs').add({
    action: 'managed_account_updated',
    actorUid: context.auth.uid,
    targetUid: uid,
    role: nextRole,
    accountStatus: nextAccountStatus,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {
    success: true,
    uid,
    role: nextRole,
    accessRoleKey: accessRole.roleKey,
    accountStatus: nextAccountStatus,
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

// Assignment is performed by the backend after a referral write. Keeping the
// persistence and notification claim in one transaction makes retries and
// browser refreshes idempotent while allowing email failure to remain
// non-blocking for the clinical workflow.
async function performReferralAssignment({
  referralId,
  preferredDoctorUid = '',
  assignmentSource = 'bhw_auto',
  assignedByUid = 'system',
  allowReassignment = false,
}) {
  const normalizedReferralId = String(referralId || '').trim();
  const referralRef = db.collection('referrals').doc(normalizedReferralId);
  const referralDoc = await referralRef.get();
  if (!referralDoc.exists) {
    return {success: false, assigned: false, reason: 'not_found'};
  }

  const referral = referralDoc.data() || {};
  const existingDoctorUid = String(referral.assignedDoctorUid || '').trim();
  if (existingDoctorUid && !allowReassignment) {
    return {
      success: true,
      assigned: true,
      alreadyAssigned: true,
      assignmentEmailSent: referral.assignmentNotificationSentFor ===
        referral.assignmentEventId,
      assignmentEmailReason: 'already_assigned',
      recommendation: {
        doctorUid: existingDoctorUid,
        doctorName: String(referral.assignedDoctorName || referral.referredTo || 'Doctor'),
        doctorEmail: String(referral.assignedDoctorEmail || ''),
        specialization: String(referral.assignedDoctorSpecialization || 'General Medicine'),
        availability: String(referral.assignedDoctorAvailability || 'available'),
        workload: 0,
        score: 0,
        rationale: ['Existing persisted assignment'],
      },
      rankedDoctors: [],
    };
  }

  const rankedDoctors = await rankDoctorsForReferral(referral);
  if (!rankedDoctors.length) {
    if (!existingDoctorUid) {
      const waitingPayload = {
        status: 'awaiting_doctor_assignment',
        assignmentStatus: 'awaiting_doctor_assignment',
        assignmentFailureReason: 'No approved, active, available doctor is currently eligible.',
        assignmentAttemptedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      await referralRef.set(waitingPayload, {merge: true});
      await syncReferralMirror(normalizedReferralId, {...referral, ...waitingPayload});
    }
    return {
      success: false,
      assigned: false,
      reason: 'no_eligible_doctor',
      rankedDoctors: [],
    };
  }

  const normalizedPreferredUid = String(preferredDoctorUid || '').trim();
  let assignedDoctor = rankedDoctors[0];
  let assignmentMode = 'smart';
  if (normalizedPreferredUid) {
    const preferredDoctor = rankedDoctors.find((doctor) =>
      doctor.doctorUid === normalizedPreferredUid);
    if (!preferredDoctor) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'The selected doctor is not eligible for assignment right now.',
      );
    }
    assignedDoctor = preferredDoctor;
    assignmentMode = 'manual';
  }

  const assignmentEventId = `${normalizedReferralId}:${assignedDoctor.doctorUid}`;
  const assignmentRationale = assignedDoctor.rationale.join(' | ');
  const updatePayload = {
    assignedDoctorUid: assignedDoctor.doctorUid,
    assignedDoctorName: assignedDoctor.doctorName,
    assignedDoctorEmail: assignedDoctor.doctorEmail,
    assignedDoctorSpecialization: assignedDoctor.specialization,
    assignedDoctorAvailability: assignedDoctor.availability,
    referredTo: assignedDoctor.doctorName,
    assignmentMode,
    assignmentSource,
    assignmentRationale: assignmentRationale || (assignmentMode === 'smart'
      ? 'Automatically assigned to the eligible doctor with the lowest active referral workload.'
      : 'Reassigned by CHO Admin.'),
    assignmentScore: assignedDoctor.score,
    assignmentEventId,
    assignedByUid,
    assignedAt: FieldValue.serverTimestamp(),
    assignmentStatus: 'assigned',
    status: 'assigned',
    assignmentNotificationStatus: 'pending',
    assignmentNotificationSentFor: FieldValue.delete(),
    assignmentNotificationSentAt: FieldValue.delete(),
    assignmentNotificationFailureReason: FieldValue.delete(),
    assignmentNotificationFailedAt: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  let shouldNotify = false;
  let alreadyHandled = false;
  let latestReferral = referral;
  await db.runTransaction(async (transaction) => {
    const latestSnap = await transaction.get(referralRef);
    latestReferral = latestSnap.data() || {};
    const latestDoctorUid = String(latestReferral.assignedDoctorUid || '').trim();
    const sameAssignment = String(latestReferral.assignmentEventId || '') ===
      assignmentEventId && latestDoctorUid === assignedDoctor.doctorUid;

    if (!allowReassignment && latestDoctorUid) {
      alreadyHandled = true;
      return;
    }
    if (sameAssignment && (
      latestReferral.assignmentNotificationSentFor === assignmentEventId ||
      latestReferral.assignmentNotificationClaimedFor === assignmentEventId)) {
      alreadyHandled = true;
      return;
    }

    transaction.set(referralRef, {
      ...updatePayload,
      assignmentNotificationClaimedFor: assignmentEventId,
    }, {merge: true});
    shouldNotify = true;
  });

  if (alreadyHandled) {
    return {
      success: true,
      assigned: true,
      alreadyHandled: true,
      recommendation: assignedDoctor,
      rankedDoctors: rankedDoctors.slice(0, 5),
      assignmentMode,
      assignmentSource,
      assignmentEmailSent: true,
      assignmentEmailReason: 'already_handled',
    };
  }

  const persistedReferral = {
    ...latestReferral,
    ...updatePayload,
    barangayCode: latestReferral.barangayCode || '',
  };
  await syncReferralMirror(normalizedReferralId, persistedReferral);

  const assignmentEmail = shouldNotify
    ? await sendDoctorAssignmentEmail({
      doctorEmail: assignedDoctor.doctorEmail,
      doctorName: assignedDoctor.doctorName,
      referralId: normalizedReferralId,
      referral: persistedReferral,
    })
    : {sent: false, reason: 'already_handled'};
  if (assignmentEmail.sent) {
    await referralRef.update({
      assignmentNotificationStatus: 'sent',
      assignmentNotificationSentFor: assignmentEventId,
      assignmentNotificationSentAt: FieldValue.serverTimestamp(),
    });
  } else {
    await referralRef.update({
      assignmentNotificationStatus: 'failed',
      assignmentNotificationFailureReason: assignmentEmail.reason || 'send_failed',
      assignmentNotificationFailedAt: FieldValue.serverTimestamp(),
    });
  }

  return {
    success: true,
    assigned: true,
    recommendation: assignedDoctor,
    rankedDoctors: rankedDoctors.slice(0, 5),
    assignmentMode,
    assignmentSource,
    assignmentEmailSent: assignmentEmail.sent,
    assignmentEmailReason: assignmentEmail.reason,
    assignmentEmailMessage: assignmentEmail.message,
  };
}

// The callable is intentionally limited to CHO Admin reassignment. Normal
// BHW referral routing is handled by autoAssignReferralOnWrite below.
exports.assignDoctorToReferral = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated',
        'You must be signed in to reassign a doctor.',
    );
  }
  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  ensureChoAdmin(context, callerDoc.data() || {});

  const referralId = String(data?.referralId || '').trim();
  const preferredDoctorUid = String(data?.preferredDoctorUid || '').trim();
  if (!referralId || !preferredDoctorUid) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Referral ID and an eligible doctor are required.',
    );
  }

  const result = await performReferralAssignment({
    referralId,
    preferredDoctorUid,
    assignmentSource: 'cho_reassign',
    assignedByUid: context.auth.uid,
    allowReassignment: true,
  });
  if (result.reason === 'not_found') {
    throw new functions.https.HttpsError('not-found', 'Referral was not found.');
  }
  return result;
});

exports.autoAssignReferralOnWrite = onDocumentWritten({
  document: 'referrals/{referralId}',
  database: FIRESTORE_DATABASE_ID,
  region: 'us-central1',
}, async (event) => {
  const change = event.data;
  if (!change.after.exists) return null;

  const after = change.after.data() || {};
  const status = normalizeText(after.status || 'submitted');
  const submissionStatus = normalizeText(after.submissionStatus || 'submitted');
  const eligible = submissionStatus === 'submitted' &&
    ['submitted', 'pending_review'].includes(status) &&
    !String(after.assignedDoctorUid || '').trim();
  if (!eligible) return null;

  const before = change.before.exists ? change.before.data() || {} : null;
  if (before) {
    const beforeStatus = normalizeText(before.status || 'submitted');
    const beforeSubmissionStatus = normalizeText(
        before.submissionStatus || 'submitted');
    const wasEligible = beforeSubmissionStatus === 'submitted' &&
      ['submitted', 'pending_review'].includes(beforeStatus) &&
      !String(before.assignedDoctorUid || '').trim();
    if (wasEligible) return null;
  }

  await performReferralAssignment({
    referralId: event.params.referralId,
    assignmentSource: 'bhw_auto',
    assignedByUid: 'system',
  });
  return null;
});
