/**
 * Firebase Cloud Functions Index
 * 
 * This file exports all Cloud Functions for the Firebase project.
 */

// Import and export callable functions
const { setUserRole } = require('./set_user_role');
const { processInvitationAsiaEast1 } = require('./process_invitations');
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
  archiveChoAccount,
  assignDoctorToReferral,
  sendReferralAssignmentEmail,
  listDoctorTransferTargets,
  doctorReferralAction,
  autoAssignReferralAsiaEast1,
	syncAccountGovernanceLocksAsiaEast1,
	suggestDoctorAssignment,
} = require('./account_policy');
const {
  listAccessRoles,
  saveAccessRole,
  deleteAccessRole,
} = require('./rbac_policy');
const {
  updateOwnBhwProfile,
  updateOwnChoProfile,
  updateOwnDoctorProfile,
} = require('./bhw_profile');
const {
  verifyDoctorSetupLink,
  completeDoctorAccountSetup,
  requestDoctorAccountSetupLink,
} = require('./doctor_access');
const {
  getReferralAttachmentDownloadUrl,
} = require('./referral_attachment_access');

// Export functions
exports.setUserRole = setUserRole;
// Firestore Eventarc functions use a region-qualified name so the repaired
// asia-east1 trigger can coexist with (and be verified before removing) the
// previously broken us-central1 deployment.
exports.processInvitationAsiaEast1 = processInvitationAsiaEast1;
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
exports.archiveChoAccount = archiveChoAccount;
exports.assignDoctorToReferral = assignDoctorToReferral;
exports.sendReferralAssignmentEmail = sendReferralAssignmentEmail;
exports.listDoctorTransferTargets = listDoctorTransferTargets;
exports.doctorReferralAction = doctorReferralAction;
exports.autoAssignReferralAsiaEast1 = autoAssignReferralAsiaEast1;
exports.syncAccountGovernanceLocksAsiaEast1 = syncAccountGovernanceLocksAsiaEast1;
exports.suggestDoctorAssignment = suggestDoctorAssignment;
exports.listAccessRoles = listAccessRoles;
exports.saveAccessRole = saveAccessRole;
exports.deleteAccessRole = deleteAccessRole;
exports.updateOwnBhwProfile = updateOwnBhwProfile;
exports.updateOwnChoProfile = updateOwnChoProfile;
exports.updateOwnDoctorProfile = updateOwnDoctorProfile;
exports.verifyDoctorSetupLink = verifyDoctorSetupLink;
exports.completeDoctorAccountSetup = completeDoctorAccountSetup;
exports.requestDoctorAccountSetupLink = requestDoctorAccountSetupLink;
exports.getReferralAttachmentDownloadUrl = getReferralAttachmentDownloadUrl;

// Additional utility functions can be added here as needed
