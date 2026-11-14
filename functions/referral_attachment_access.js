"use strict";

/**
 * Server-mediated access to referral attachments.
 *
 * Storage Rules cannot inspect the assignment on the named Firestore
 * database. This callable authorizes the caller against the referral first,
 * then returns a short-lived read URL for an attachment that is declared on
 * that referral.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

if (!(typeof admin.getApps === "function" ? admin.getApps() : admin.apps).length) {
  admin.initializeApp();
}

const FIRESTORE_DATABASE_ID = "capstone-c98f9";
const ATTACHMENT_URL_TTL_MS = 10 * 60 * 1000;
const ATTACHMENT_PATH_PATTERN = /^referral_attachments\/([^/]+)\/([^/]+)\/([A-Za-z0-9._-]{1,128})$/;
const db = getFirestore(admin.getApp(), FIRESTORE_DATABASE_ID);

function normalizedRole(value) {
  return String(value || "").trim().toUpperCase();
}

function isApprovedActiveProfile(profile) {
  const approval = String(profile?.approvalStatus || "").trim().toLowerCase();
  const accountStatus = String(
      profile?.accountStatus || profile?.status || "",
  ).trim().toLowerCase();
  return (approval === "approved" || profile?.isApproved === true) &&
    ["active", "approved"].includes(accountStatus);
}

function defaultPermissionsForRole(role) {
  const normalized = normalizedRole(role);
  if (normalized === "DOCTOR") {
    return ["referrals.assigned.view"];
  }
  if (["CHO", "CHO_ADMIN", "CHO_SUPER_ADMIN"].includes(normalized)) {
    return ["referrals.view"];
  }
  return [];
}

function hasPermission(profile, permission) {
  const role = normalizedRole(profile?.role);
  if (["CHO_ADMIN", "CHO_SUPER_ADMIN"].includes(role)) return true;
  const permissions = Array.isArray(profile?.permissions) && profile.permissions.length
    ? profile.permissions
    : defaultPermissionsForRole(role);
  return permissions.includes(permission);
}

function parseReferralAttachmentPath(storagePath) {
  const match = ATTACHMENT_PATH_PATTERN.exec(String(storagePath || "").trim());
  if (!match) return null;
  return {
    ownerUid: match[1],
    referralId: match[2],
    fileName: match[3],
  };
}

function attachmentIsDeclared(attachments, storagePath) {
  return Array.isArray(attachments) && attachments.some((attachment) =>
    attachment && typeof attachment === "object" &&
    String(attachment.storagePath || "").trim() === storagePath,
  );
}

function attachmentAccessAllowed(profile, uid, referral) {
  const role = normalizedRole(profile?.role);
  if (!isApprovedActiveProfile(profile)) return false;
  if (role === "DOCTOR") {
    return hasPermission(profile, "referrals.assigned.view") &&
      String(referral.assignedDoctorUid || "").trim() === uid;
  }
  return ["CHO", "CHO_ADMIN", "CHO_SUPER_ADMIN"].includes(role) &&
    hasPermission(profile, "referrals.view");
}

exports.getReferralAttachmentDownloadUrl = functions.runWith({
  enforceAppCheck: true,
}).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in to access a referral attachment.",
    );
  }

  const storagePath = String(data?.storagePath || "").trim();
  const referralId = String(data?.referralId || "").trim();
  const parsedPath = parseReferralAttachmentPath(storagePath);
  if (!referralId || !parsedPath || parsedPath.referralId !== referralId) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid referral attachment is required.",
    );
  }

  const [profileSnapshot, referralSnapshot] = await Promise.all([
    db.collection("users").doc(context.auth.uid).get(),
    db.collection("referrals").doc(referralId).get(),
  ]);
  if (!referralSnapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Referral was not found.");
  }
  const profile = profileSnapshot.exists ? profileSnapshot.data() || {} : {};
  const referral = referralSnapshot.data() || {};
  if (!attachmentAccessAllowed(profile, context.auth.uid, referral)) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "You are not authorized to access this referral attachment.",
    );
  }

  const ownerUid = String(referral.createdByUid || "").trim();
  if (parsedPath.ownerUid !== ownerUid ||
      !attachmentIsDeclared(referral.attachments, storagePath)) {
    throw new functions.https.HttpsError("not-found", "Referral attachment was not found.");
  }

  try {
    const bucket = getStorage(admin.getApp()).bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
      throw new functions.https.HttpsError("not-found", "Referral attachment was not found.");
    }
    const expiresAt = Date.now() + ATTACHMENT_URL_TTL_MS;
    const [url] = await file.getSignedUrl({
      version: "v4",
      action: "read",
      expires: expiresAt,
    });
    return {
      url,
      expiresAt,
      fileName: parsedPath.fileName,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Referral attachment URL generation failed", {
      code: error?.code || "unknown",
    });
    throw new functions.https.HttpsError(
        "unavailable",
        "The referral attachment is temporarily unavailable.",
    );
  }
});

module.exports.parseReferralAttachmentPath = parseReferralAttachmentPath;
module.exports.attachmentIsDeclared = attachmentIsDeclared;
module.exports.attachmentAccessAllowed = attachmentAccessAllowed;
