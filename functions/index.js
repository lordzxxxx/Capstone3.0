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
	registerDoctorAccount,
	assignDoctorToReferral,
	sendDoctorReferralAssignmentEmail,
	syncAccountGovernanceLocksV2,
	suggestDoctorAssignment,
} = require('./account_policy');

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
exports.registerDoctorAccount = registerDoctorAccount;
exports.assignDoctorToReferral = assignDoctorToReferral;
exports.sendDoctorReferralAssignmentEmail = sendDoctorReferralAssignmentEmail;
exports.syncAccountGovernanceLocksV2 = syncAccountGovernanceLocksV2;
exports.suggestDoctorAssignment = suggestDoctorAssignment;

// Additional utility functions can be added here as needed
