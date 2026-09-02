const functions = require('firebase-functions');
const admin = require('firebase-admin');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');

if (!admin.apps.length) {
  admin.initializeApp();
}

const FIRESTORE_DATABASE_ID = 'capstone-c98f9';
const db = getFirestore(admin.app(), FIRESTORE_DATABASE_ID);

// These are the permissions exposed to administrators. They intentionally
// describe real portal features and actions, rather than accepting arbitrary
// strings from the browser.
const PERMISSION_DEFINITIONS = [
  {key: 'dashboard.view', label: 'View dashboard', group: 'Portal'},
  {key: 'patients.view', label: 'View patients', group: 'Patients'},
  {key: 'patients.create', label: 'Register patients', group: 'Patients'},
  {key: 'patients.edit', label: 'Edit patient records', group: 'Patients'},
  {key: 'checkups.view', label: 'View check-ups', group: 'Clinical records'},
  {key: 'checkups.create', label: 'Record check-ups', group: 'Clinical records'},
  {key: 'checkups.edit', label: 'Edit check-ups', group: 'Clinical records'},
  {key: 'prenatal.view', label: 'View prenatal records', group: 'Clinical records'},
  {key: 'prenatal.create', label: 'Record prenatal visits', group: 'Clinical records'},
  {key: 'prenatal.edit', label: 'Edit prenatal records', group: 'Clinical records'},
  {key: 'immunization.view', label: 'View immunization records', group: 'Clinical records'},
  {key: 'immunization.create', label: 'Record immunizations', group: 'Clinical records'},
  {key: 'immunization.edit', label: 'Edit immunization records', group: 'Clinical records'},
  {key: 'surveillance.view', label: 'View disease surveillance', group: 'Surveillance'},
  {key: 'surveillance.create', label: 'Record surveillance data', group: 'Surveillance'},
  {key: 'surveillance.edit', label: 'Edit surveillance data', group: 'Surveillance'},
  {key: 'referrals.view', label: 'View referrals', group: 'Referrals'},
  {key: 'referrals.assigned.view', label: 'View assigned doctor referrals', group: 'Referrals'},
  {key: 'referrals.create', label: 'Submit referrals', group: 'Referrals'},
  {key: 'referrals.status.update', label: 'Update referral follow-up status', group: 'Referrals'},
  {key: 'referrals.reassign', label: 'Reassign referrals', group: 'Referrals'},
  {key: 'immunization.vaccine_master.view', label: 'View vaccine master', group: 'Immunization'},
  {key: 'reports.view', label: 'View reports and analytics', group: 'Reports'},
  {key: 'reports.export', label: 'Export reports', group: 'Reports'},
  {key: 'bhw.requests.view', label: 'View BHW registrations', group: 'BHW management'},
  {key: 'bhw.approve', label: 'Approve BHW registrations', group: 'BHW management'},
  {key: 'bhw.reject', label: 'Reject BHW registrations', group: 'BHW management'},
  {key: 'bhw.access.manage', label: 'Enable or disable BHW access', group: 'BHW management'},
  {key: 'cho.users.view', label: 'View CHO users', group: 'CHO access'},
  {key: 'cho.users.create', label: 'Create CHO and doctor accounts', group: 'CHO access'},
  {key: 'cho.users.edit', label: 'Update CHO and doctor access', group: 'CHO access'},
  {key: 'cho.users.disable', label: 'Enable or disable managed accounts', group: 'CHO access'},
  {key: 'doctors.view', label: 'View doctors and workload', group: 'CHO access'},
  {key: 'doctors.manage', label: 'Manage doctor eligibility', group: 'CHO access'},
  {key: 'rbac.view', label: 'View roles and permissions', group: 'RBAC'},
  {key: 'rbac.manage', label: 'Create and edit roles', group: 'RBAC'},
  {key: 'rbac.users.assign', label: 'Assign access roles', group: 'RBAC'},
  {key: 'data_quality.view', label: 'View data quality', group: 'Governance'},
  {key: 'audit.view', label: 'View audit logs', group: 'Governance'},
  {key: 'notifications.view', label: 'View notifications', group: 'Portal'},
  {key: 'profile.view', label: 'View profile', group: 'Portal'},
];

const PERMISSION_KEYS = new Set(PERMISSION_DEFINITIONS.map((item) => item.key));
const ADMIN_ROLES = new Set(['CHO_ADMIN', 'CHO_SUPER_ADMIN', 'SUPER_ADMIN', 'ADMIN']);
const BASE_ROLES = new Set(['BHW', 'CHO', 'DOCTOR']);

const BHW_PERMISSIONS = [
  'dashboard.view', 'patients.view', 'patients.create', 'patients.edit',
  'checkups.view', 'checkups.create', 'checkups.edit',
  'prenatal.view', 'prenatal.create', 'prenatal.edit',
  'immunization.view', 'immunization.create', 'immunization.edit',
  'immunization.vaccine_master.view',
  'surveillance.view', 'surveillance.create', 'surveillance.edit',
  'referrals.view', 'referrals.create', 'referrals.status.update',
  'reports.view', 'reports.export', 'notifications.view', 'profile.view',
];

const CHO_PERMISSIONS = [
  'dashboard.view', 'patients.view', 'patients.create', 'patients.edit',
  'checkups.view', 'checkups.create', 'checkups.edit',
  'prenatal.view', 'prenatal.create', 'prenatal.edit',
  'immunization.view', 'immunization.create', 'immunization.edit',
  'immunization.vaccine_master.view',
  'surveillance.view', 'surveillance.create', 'surveillance.edit',
  'referrals.view', 'referrals.status.update', 'reports.view',
  'reports.export', 'data_quality.view', 'audit.view', 'notifications.view', 'profile.view',
];

const DOCTOR_PERMISSIONS = [
  'dashboard.view', 'patients.view', 'checkups.view', 'prenatal.view',
  'immunization.view', 'surveillance.view', 'referrals.view',
  'referrals.assigned.view', 'notifications.view', 'profile.view',
];

const BASE_PERMISSION_MAP = Object.freeze({
  BHW: Object.freeze(BHW_PERMISSIONS),
  CHO: Object.freeze(CHO_PERMISSIONS),
  DOCTOR: Object.freeze(DOCTOR_PERMISSIONS),
});

const ALL_PERMISSIONS = Object.freeze(PERMISSION_DEFINITIONS.map((item) => item.key));

function normalizeRole(value) {
  return String(value || '').trim().toUpperCase();
}

function normalizeRoleKey(value) {
  return normalizeRole(value).replace(/[^A-Z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

function isAdminRole(role) {
  return ADMIN_ROLES.has(normalizeRole(role));
}

function defaultPermissionsForRole(role) {
  const normalized = normalizeRole(role);
  return isAdminRole(normalized)
    ? [...ALL_PERMISSIONS]
    : [...(BASE_PERMISSION_MAP[normalized] || [])];
}

function permissionsForProfile(profile = {}) {
  const role = normalizeRole(profile.role);
  if (isAdminRole(role)) return [...ALL_PERMISSIONS];
  if (Array.isArray(profile.permissions)) {
    return [...new Set(profile.permissions
        .map((permission) => String(permission || '').trim())
        .filter((permission) => PERMISSION_KEYS.has(permission)))];
  }
  return defaultPermissionsForRole(role);
}

function hasPermission(profile, permission) {
  const normalizedPermission = String(permission || '').trim();
  return permissionsForProfile(profile).includes(normalizedPermission);
}

function sanitizePermissions(baseRole, permissions) {
  const allowed = new Set(defaultPermissionsForRole(baseRole));
  const requested = Array.isArray(permissions) ? permissions : [...allowed];
  return [...new Set(requested
      .map((permission) => String(permission || '').trim())
      .filter((permission) => PERMISSION_KEYS.has(permission) && allowed.has(permission)))];
}

function systemRoleDefinition(roleKey) {
  const key = normalizeRoleKey(roleKey);
  const baseRole = BASE_ROLES.has(key) ? key : (isAdminRole(key) ? key : null);
  if (!baseRole) return null;
  return {
    roleKey: key,
    name: key === 'CHO_ADMIN' ? 'CHO Admin' : key === 'DOCTOR' ? 'Doctor' : key === 'BHW' ? 'BHW' : key,
    description: isAdminRole(key) ? 'Protected administrator role.' : `Built-in ${key} access role.`,
    baseRole: BASE_ROLES.has(key) ? key : key,
    permissions: defaultPermissionsForRole(key),
    isSystem: true,
    protected: true,
    active: true,
  };
}

async function resolveRoleAssignment({role, accessRoleKey}) {
  const requestedRole = normalizeRole(role);
  const requestedKey = normalizeRoleKey(accessRoleKey || requestedRole);
  const system = systemRoleDefinition(requestedKey);
  if (system) {
    if (requestedRole && BASE_ROLES.has(requestedRole) &&
        system.baseRole !== requestedRole) {
      throw new functions.https.HttpsError('invalid-argument', 'The selected access role does not match the account role.');
    }
    if (isAdminRole(system.roleKey)) {
      throw new functions.https.HttpsError('permission-denied', 'Protected administrator roles are not assignable from this workflow.');
    }
    return system;
  }

  if (!requestedKey.startsWith('CUSTOM_')) {
    throw new functions.https.HttpsError('invalid-argument', 'The selected access role is not valid.');
  }
  const snapshot = await db.collection('roles').doc(requestedKey).get();
  if (!snapshot.exists || snapshot.data()?.active === false) {
    throw new functions.https.HttpsError('not-found', 'The selected access role no longer exists.');
  }
  const data = snapshot.data() || {};
  const baseRole = normalizeRole(data.baseRole);
  if (!BASE_ROLES.has(baseRole) ||
      (requestedRole && BASE_ROLES.has(requestedRole) && requestedRole !== baseRole)) {
    throw new functions.https.HttpsError('invalid-argument', 'The selected access role is not compatible with this account.');
  }
  return {
    roleKey: requestedKey,
    name: String(data.name || requestedKey),
    description: String(data.description || ''),
    baseRole,
    permissions: sanitizePermissions(baseRole, data.permissions),
    isSystem: false,
    protected: false,
    active: data.active !== false,
  };
}

async function ensureChoAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be signed in to manage access roles.');
  }
  const snapshot = await db.collection('users').doc(context.auth.uid).get();
  const profile = snapshot.data() || {};
  if (!isAdminRole(profile.role) ||
      String(profile.approvalStatus || '').toLowerCase() !== 'approved' ||
      !['active', 'approved'].includes(String(profile.accountStatus || profile.status || '').toLowerCase())) {
    throw new functions.https.HttpsError('permission-denied', 'Only an approved CHO Admin can manage access roles.');
  }
  return profile;
}

function roleDefinitions() {
  return [...ADMIN_ROLES, ...BASE_ROLES]
      .map(systemRoleDefinition)
      .filter(Boolean);
}

function safeRoleName(value) {
  const name = String(value || '').trim();
  if (name.length < 2 || name.length > 80 || !/\S/.test(name)) {
    throw new functions.https.HttpsError('invalid-argument', 'Role name must be between 2 and 80 characters.');
  }
  return name;
}

exports.db = db;
exports.PERMISSION_DEFINITIONS = PERMISSION_DEFINITIONS;
exports.ALL_PERMISSIONS = ALL_PERMISSIONS;
exports.ADMIN_ROLES = ADMIN_ROLES;
exports.BASE_ROLES = BASE_ROLES;
exports.normalizeRole = normalizeRole;
exports.normalizeRoleKey = normalizeRoleKey;
exports.isAdminRole = isAdminRole;
exports.defaultPermissionsForRole = defaultPermissionsForRole;
exports.permissionsForProfile = permissionsForProfile;
exports.hasPermission = hasPermission;
exports.sanitizePermissions = sanitizePermissions;
exports.resolveRoleAssignment = resolveRoleAssignment;
exports.ensureChoAdmin = ensureChoAdmin;
exports.systemRoleDefinition = systemRoleDefinition;
exports.roleDefinitions = roleDefinitions;
exports.safeRoleName = safeRoleName;

exports.listAccessRoles = functions.https.onCall(async (data, context) => {
  await ensureChoAdmin(context);
  const snapshot = await db.collection('roles').where('active', '!=', false).get();
  const assignedCounts = new Map();
  const users = await db.collection('users').get();
  users.forEach((doc) => {
    const key = normalizeRoleKey(doc.data()?.accessRoleKey || doc.data()?.role);
    assignedCounts.set(key, (assignedCounts.get(key) || 0) + 1);
  });
  const customRoles = snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    const key = normalizeRoleKey(data.roleKey || doc.id);
    const baseRole = normalizeRole(data.baseRole);
    return {
      roleKey: key,
      name: String(data.name || key),
      description: String(data.description || ''),
      baseRole,
      permissions: sanitizePermissions(baseRole, data.permissions),
      isSystem: false,
      protected: false,
      active: data.active !== false,
      assignedUsers: assignedCounts.get(key) || 0,
    };
  });
  return {
    roles: [...roleDefinitions(), ...customRoles].map((role) => ({
      ...role,
      assignedUsers: role.assignedUsers || assignedCounts.get(role.roleKey) || 0,
    })),
    permissions: PERMISSION_DEFINITIONS,
  };
});

exports.saveAccessRole = functions.https.onCall(async (data, context) => {
  const actor = await ensureChoAdmin(context);
  const existingKey = normalizeRoleKey(data?.roleKey || '');
  const name = safeRoleName(data?.name);
  const description = String(data?.description || '').trim();
  if (description.length > 240) {
    throw new functions.https.HttpsError('invalid-argument', 'Role description cannot exceed 240 characters.');
  }
  const baseRole = normalizeRole(data?.baseRole);
  if (!BASE_ROLES.has(baseRole)) {
    throw new functions.https.HttpsError('invalid-argument', 'Custom roles must be based on BHW, CHO, or DOCTOR.');
  }
  if (existingKey && (!existingKey.startsWith('CUSTOM_') || systemRoleDefinition(existingKey))) {
    throw new functions.https.HttpsError('permission-denied', 'Built-in roles are protected and cannot be edited.');
  }

  const roleKey = existingKey || `CUSTOM_${normalizeRoleKey(name)}`;
  if (!roleKey || roleKey.length > 80 || !roleKey.startsWith('CUSTOM_')) {
    throw new functions.https.HttpsError('invalid-argument', 'Choose a role name that produces a valid access key.');
  }
  const roleRef = db.collection('roles').doc(roleKey);
  const current = await roleRef.get();
  if (current.exists && current.data()?.isSystem === true) {
    throw new functions.https.HttpsError('permission-denied', 'Built-in roles are protected and cannot be edited.');
  }
  const permissions = sanitizePermissions(baseRole, data?.permissions);
  const payload = {
    roleKey,
    name,
    description,
    baseRole,
    permissions,
    isSystem: false,
    protected: false,
    active: true,
    updatedByUid: context.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
    ...(current.exists ? {} : {
      createdByUid: context.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    }),
  };
  await roleRef.set(payload, {merge: true});

  const users = await db.collection('users').where('accessRoleKey', '==', roleKey).get();
  const batch = db.batch();
  users.docs.forEach((doc) => batch.set(doc.ref, {
    role: baseRole,
    accessRoleKey: roleKey,
    permissions,
    updatedBy: context.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true}));
  if (!users.empty) await batch.commit();

  await db.collection('audit_logs').add({
    action: current.exists ? 'access_role_updated' : 'access_role_created',
    actorUid: actor.uid || context.auth.uid,
    roleKey,
    baseRole,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {success: true, roleKey, baseRole, permissions};
});

exports.deleteAccessRole = functions.https.onCall(async (data, context) => {
  await ensureChoAdmin(context);
  const roleKey = normalizeRoleKey(data?.roleKey || '');
  if (!roleKey.startsWith('CUSTOM_') || systemRoleDefinition(roleKey)) {
    throw new functions.https.HttpsError('permission-denied', 'Built-in roles are protected and cannot be deleted.');
  }
  const roleRef = db.collection('roles').doc(roleKey);
  const role = await roleRef.get();
  if (!role.exists) throw new functions.https.HttpsError('not-found', 'The custom role was not found.');
  const assigned = await db.collection('users').where('accessRoleKey', '==', roleKey).limit(1).get();
  if (!assigned.empty) {
    throw new functions.https.HttpsError('failed-precondition', 'Reassign all users before deleting this role.');
  }
  await roleRef.delete();
  await db.collection('audit_logs').add({
    action: 'access_role_deleted',
    actorUid: context.auth.uid,
    roleKey,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {success: true, roleKey};
});
