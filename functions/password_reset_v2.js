const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// Send verification code email - triggered when password_resets doc is created
exports.sendPasswordResetCode = functions.firestore
  .document("password_resets/{email}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const email = data.email;
    const code = data.code;

    try {
      // TODO: Configure your email service here
      // Option 1: SendGrid (recommended)
      // const sgMail = require("@sendgrid/mail");
      // sgMail.setApiKey(functions.config().sendgrid.key);
      // await sgMail.send({
      //   to: email,
      //   from: functions.config().sendgrid.email,
      //   subject: "Your Password Reset Code",
      //   html: `<h2>Password Reset</h2><p>Code: ${code}</p><p>Expires in 15 minutes</p>`
      // });

      // For development, log it
      console.log(`[PASSWORD_RESET] Code for ${email}: ${code}`);

      return { success: true };
    } catch (error) {
      console.error("Error sending email:", error);
      throw new functions.https.HttpsError("internal", "Failed to send email");
    }
  });

// Callable function to update password
// This must be called from the client after code verification
exports.updatePasswordWithToken = functions.https.onCall(
  async (data, context) => {
    const { email, sessionToken, newPassword } = data;

    try {
      // Validate input
      if (!email || !sessionToken || !newPassword) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Missing required parameters"
        );
      }

      // Get the password reset document
      const resetDoc = await admin
        .firestore()
        .collection("password_resets")
        .doc(email)
        .get();

      if (!resetDoc.exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "No reset session found"
        );
      }

      const resetData = resetDoc.data();

      // Verify session is ready
      if (!resetData.readyToReset) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Reset session not ready. Code not verified."
        );
      }

      if (!resetData.verified) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Email not verified"
        );
      }

      // Verify session token
      if (resetData.sessionToken !== sessionToken) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Invalid session token"
        );
      }

      // Check session hasn't expired
      const expiryAt = resetData.expiryAt.toDate();
      if (new Date() > expiryAt) {
        // Clean up expired document
        await admin
          .firestore()
          .collection("password_resets")
          .doc(email)
          .delete();

        throw new functions.https.HttpsError(
          "deadline-exceeded",
          "Session has expired. Please request a new code."
        );
      }

      // Get user by email
      let user;
      try {
        user = await admin.auth().getUserByEmail(email);
      } catch (error) {
        throw new functions.https.HttpsError(
          "not-found",
          "User not found with this email"
        );
      }

      // Update the password using Admin SDK
      try {
        await admin.auth().updateUser(user.uid, {
          password: newPassword,
        });
      } catch (authError) {
        console.error("Auth update error:", authError);
        throw new functions.https.HttpsError(
          "internal",
          "Failed to update password"
        );
      }

      // Clean up the password reset document
      await admin
        .firestore()
        .collection("password_resets")
        .doc(email)
        .delete();

      // Log the security event
      console.log(`[SECURITY] Password reset completed for ${email}`);

      // TODO: Send confirmation email to user

      return {
        success: true,
        message:
          "Password updated successfully. Please log in with your new password.",
      };
    } catch (error) {
      console.error("Error updating password:", error);
      throw error instanceof functions.https.HttpsError
        ? error
        : new functions.https.HttpsError("internal", "An error occurred");
    }
  }
);

// Monitor password reset events (for security logging)
exports.logPasswordResetEvent = functions.firestore
  .document("password_resets/{email}")
  .onWrite(async (change, context) => {
    const email = context.params.email;
    const newData = change.after.data();
    const oldData = change.before.data();

    // New reset request
    if (!oldData && newData) {
      console.log(`[AUDIT] Password reset initiated: ${email}`);
    }
    // Code verified
    else if (newData && newData.verified && oldData && !oldData.verified) {
      console.log(`[AUDIT] Verification code confirmed: ${email}`);
    }
  });

// Daily cleanup of expired password reset sessions
exports.cleanupExpiredResets = functions.pubsub
  .schedule("every day 00:00")
  .timeZone("America/New_York")
  .onRun(async (context) => {
    const now = new Date();

    try {
      const query = await admin
        .firestore()
        .collection("password_resets")
        .where("expiryAt", "<", now)
        .get();

      if (query.empty) {
        console.log("[CLEANUP] No expired resets to clean up");
        return null;
      }

      const batch = admin.firestore().batch();
      query.docs.forEach((doc) => {
        batch.delete(doc.ref);
        console.log(`[CLEANUP] Removing expired reset: ${doc.id}`);
      });

      await batch.commit();
      console.log(
        `[CLEANUP] Deleted ${query.docs.length} expired password resets`
      );

      return null;
    } catch (error) {
      console.error("[CLEANUP] Error during cleanup:", error);
      return null;
    }
  });
