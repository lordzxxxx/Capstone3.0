/**
 * Firebase Cloud Functions Index
 * 
 * This file exports all Cloud Functions for the Firebase project.
 */

// Import and export callable functions
const { setUserRole } = require('./set_user_role');
const { processInvitation } = require('./process_invitations');
const {
	sendPasswordResetEmail,
	verifyResetCode,
	completePasswordReset,
} = require('./send_password_reset');
const {
  validateRegistrationPolicy,
  getBarangayAvailability,
  createRegistrationAccount,
  completeRegistration,
	createChoAccount,
	reviewBhwRegistration,
	updateChoAccount,
	assignDoctorToReferral,
	autoAssignReferralOnWrite,
	syncAccountGovernanceLocksV2,
	suggestDoctorAssignment,
} = require('./account_policy');
const {
  listAccessRoles,
  saveAccessRole,
  deleteAccessRole,
} = require('./rbac_policy');

// Export functions
exports.setUserRole = setUserRole;
exports.processInvitation = processInvitation;
exports.sendPasswordResetEmail = sendPasswordResetEmail;
exports.verifyResetCode = verifyResetCode;
exports.completePasswordReset = completePasswordReset;
exports.validateRegistrationPolicy = validateRegistrationPolicy;
exports.getBarangayAvailability = getBarangayAvailability;
exports.createRegistrationAccount = createRegistrationAccount;
exports.completeRegistration = completeRegistration;
exports.createChoAccount = createChoAccount;
exports.reviewBhwRegistration = reviewBhwRegistration;
exports.updateChoAccount = updateChoAccount;
exports.assignDoctorToReferral = assignDoctorToReferral;
exports.autoAssignReferralOnWrite = autoAssignReferralOnWrite;
exports.syncAccountGovernanceLocksV2 = syncAccountGovernanceLocksV2;
exports.suggestDoctorAssignment = suggestDoctorAssignment;
exports.listAccessRoles = listAccessRoles;
exports.saveAccessRole = saveAccessRole;
exports.deleteAccessRole = deleteAccessRole;

// Additional utility functions can be added here as needed
