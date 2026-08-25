const AUTH_ENDPOINT =
  'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts';
const FIRESTORE_ENDPOINT =
  'http://127.0.0.1:8085/v1/projects/capstone-c98f9/databases/capstone-c98f9/documents';

const PASSWORD = 'Browser-QA-Only-123!';

const profiles = [
  {
    key: 'bhw',
    email: 'browser-bhw@example.test',
    role: 'bhw',
    fullName: 'Browser QA BHW',
    barangay: 'Barangay 10',
    barangayCode: 'barangay_10',
    accessScope: 'barangay',
  },
  {
    key: 'cho',
    email: 'browser-cho@example.test',
    role: 'cho',
    fullName: 'Browser QA CHO',
    barangay: '',
    barangayCode: '',
    accessScope: 'citywide',
  },
  {
    key: 'doctor',
    email: 'browser-doctor@example.test',
    role: 'doctor',
    fullName: 'Browser QA Doctor',
    barangay: '',
    barangayCode: '',
    accessScope: 'assigned_referrals',
    availabilityStatus: 'available',
    specialization: 'General Medicine',
  },
  {
    key: 'superAdmin',
    email: 'browser-super-admin@example.test',
    role: 'super_admin',
    fullName: 'Browser QA Super Admin',
    barangay: '',
    barangayCode: '',
    accessScope: 'citywide',
  },
];

function firestoreValue(value) {
  if (value === null) return {nullValue: null};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? {integerValue: String(value)}
      : {doubleValue: value};
  }
  if (Array.isArray(value)) {
    return {arrayValue: {values: value.map(firestoreValue)}};
  }
  if (typeof value === 'object') {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, entry]) => [key, firestoreValue(entry)]),
        ),
      },
    };
  }
  return {stringValue: String(value)};
}

async function authRequest(operation, email) {
  const response = await fetch(`${AUTH_ENDPOINT}:${operation}?key=emulator-key`, {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({email, password: PASSWORD, returnSecureToken: true}),
  });
  const body = await response.json();
  return {response, body};
}

async function ensureAuthUser(email) {
  let result = await authRequest('signUp', email);
  if (!result.response.ok && result.body?.error?.message === 'EMAIL_EXISTS') {
    result = await authRequest('signInWithPassword', email);
  }
  if (!result.response.ok || !result.body.localId) {
    throw new Error(
      `Could not provision browser test identity ${email}: ${JSON.stringify(result.body)}`,
    );
  }
  return result.body.localId;
}

async function seedProfile(uid, profile) {
  const data = {
    uid,
    email: profile.email,
    emailLower: profile.email.toLowerCase(),
    displayName: profile.fullName,
    fullName: profile.fullName,
    role: profile.role,
    approvalStatus: 'approved',
    accountStatus: 'active',
    status: 'Active',
    isApproved: true,
    barangay: profile.barangay,
    barangayCode: profile.barangayCode,
    accessScope: profile.accessScope,
    organizationLevel: profile.role === 'bhw' ? 'barangay' : 'citywide',
    createdAt: '2026-08-25T00:00:00.000Z',
    ...(profile.availabilityStatus
      ? {availabilityStatus: profile.availabilityStatus}
      : {}),
    ...(profile.specialization ? {specialization: profile.specialization} : {}),
  };
  const response = await fetch(`${FIRESTORE_ENDPOINT}/users/${uid}`, {
    method: 'PATCH',
    headers: {
      authorization: 'Bearer owner',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      fields: Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, firestoreValue(value)]),
      ),
    }),
  });
  if (!response.ok) {
    throw new Error(
      `Could not seed browser test profile ${profile.email}: ${await response.text()}`,
    );
  }
  return {...profile, uid, password: PASSWORD};
}

module.exports = async () => {
  const identities = {};
  for (const profile of profiles) {
    const uid = await ensureAuthUser(profile.email);
    identities[profile.key] = await seedProfile(uid, profile);
  }
  process.env.BROWSER_TEST_IDENTITIES = JSON.stringify(identities);
};

module.exports.PASSWORD = PASSWORD;
