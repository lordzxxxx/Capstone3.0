Password Reset Setup Guide
===========================

This guide explains how to properly set up and deploy the password reset functionality for your DSUHIS application.

## Overview

The password reset flow consists of three main components:

1. **Cloud Functions** - Backend services that send emails and verify codes
2. **Dart/Flutter Client** - Mobile and web interfaces for the reset UI
3. **Firebase Configuration** - SMTP settings for sending emails

## Prerequisites

1. Firebase Project on Blaze (pay-as-you-go) plan
   - The Spark (free) plan doesn't support Cloud Functions deployments
   - Visit: https://console.firebase.google.com/project/capstone-c98f9/usage/details 
   - Click "Upgrade to Blaze"

2. SMTP Email Service
   - Option A: Gmail with App Password
   - Option B: SendGrid, Mailgun, or other SMTP provider

## Step 1: Upgrade Firebase Project to Blaze Plan

1. Go to https://console.firebase.google.com/project/capstone-c98f9/usage/details
2. Click "Upgrade to Blaze"
3. Enter your billing information and confirm
4. Wait for the upgrade to complete (usually instantaneous)

## Step 2: Set Up Email Service (SMTP)

### Option A: Using Gmail (Recommended for Development)

1. Enable 2-Factor Authentication on your Gmail account
2. Generate an App Password:
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" and "Windows Computer"
   - Google will generate a 16-character password
   - Note this password

3. Set Firebase Functions Config:
```powershell
# Windows PowerShell
cd C:\capstone\mycapstone_project
firebase functions:config:set smtp.user="your-email@gmail.com"
firebase functions:config:set smtp.pass="your-16-char-app-password"
firebase functions:config:set smtp.host="smtp.gmail.com"
firebase functions:config:set smtp.port="587"
```

### Option B: Using Environment Variables

You can also set the SMTP configuration via environment variables:

1. Create a `.env.local` file in the `functions` directory:
```
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
```

2. Deploy with environment variables:
```powershell
$env:SMTP_USER="your-email@gmail.com"
$env:SMTP_PASS="your-app-password"
firebase functions:config:set smtp.user="$env:SMTP_USER"
firebase functions:config:set smtp.pass="$env:SMTP_PASS"
firebase deploy --only functions
```

## Step 3: Deploy Cloud Functions

1. Open PowerShell and navigate to the project:
```powershell
cd C:\capstone\mycapstone_project\functions
```

2. Verify dependencies are installed:
```powershell
npm install
```

3. Deploy the functions:
```powershell
npm run deploy
# Or: firebase deploy --only functions
```

4. Verify deployment was successful. You should see:
```
✔ Deploy complete!

Function URL (sendPasswordReset):
https://us-central1-capstone-c98f9.cloudfunctions.net/sendPasswordReset

Function URL (verifyResetCode):
https://us-central1-capstone-c98f9.cloudfunctions.net/verifyResetCode

Function URL (completePasswordReset):
https://us-central1-capstone-c98f9.cloudfunctions.net/completePasswordReset
```

## Step 4: Verify Configuration

The client code already has the correct Cloud Function URLs configured in:
- `lib/app/cloud_functions_config.dart`

These URLs are automatically used by:
- `reset_password_service.dart` (for sending verification codes)
- `forgot.dart` / `verification_code.dart` (forgot password flow)
- `reset_with_code.dart` (web password reset)

If you change the project ID or region in the future, update `cloud_functions_config.dart`:

```dart
class CloudFunctionsConfig {
  static const String projectId = 'capstone-c98f9';  // Change if needed
  static const String region = 'us-central1';         // Change if needed
  
  static const String sendPasswordResetUrl = 
    'https://us-central1-capstone-c98f9.cloudfunctions.net/sendPasswordReset';
  // ... etc
}
```

## Password Reset Flow Sequence

### 1. User Initiates Reset (forgot.dart)
```
User enters email address
                ↓
Calls ResetPasswordService.sendVerificationCode(email)
                ↓
Calls Cloud Function: sendPasswordReset
                ↓
Cloud Function generates 4-digit code and emails it
                ↓
User sees success message and navigates to verification screen
```

### 2. User Verifies Code (verification_code.dart)
```
User enters 4-digit code
                ↓
Calls ResetPasswordService.verifyCode(email, code)
                ↓
Calls Cloud Function: verifyResetCode
                ↓
Cloud Function validates code and checks expiry
                ↓
If valid, user navigates to password entry screen (new_password.dart)
```

### 3. User Sets New Password (new_password.dart / reset_with_code.dart)
```
User enters new password twice
                ↓
Calls ResetPasswordService.completePasswordReset(email, code, newPassword)
                ↓
Calls Cloud Function: completePasswordReset
                ↓
Cloud Function updates password in Firebase Auth
                ↓
User is logged out and redirected to login page
```

## Cloud Functions Explanation

### 1. sendPasswordReset
**Location:** `functions/password_reset.js`

**Purpose:** Handles initial password reset request

**Flow:**
1. Receives email address
2. Verifies user exists in Firebase Auth
3. Generates random 4-digit code
4. Hashes code with salt using SHA-256
5. Stores hashed code in Firestore with 15-minute expiry
6. Sends email with code via nodemailer
7. Returns success response

**Security Features:**
- Code is hashed before storage (not stored in plain text)
- 15-minute expiry prevents brute force attacks
- Email address must exist in Firebase Auth
- Hashed code prevents anyone with Firestore access from seeing the actual code

### 2. verifyResetCode
**Location:** `functions/password_reset.js`

**Purpose:** Verifies the code entered by the user

**Flow:**
1. Receives email and code
2. Retrieves hashed code from Firestore
3. Checks if code has expired
4. Hashes the submitted code and compares with stored hash
5. Returns success if valid

**Security Features:**
- Prevents invalid code usage
- Prevents replay attacks via expiry
- Hashed comparison prevents timing attacks

### 3. completePasswordReset
**Location:** `functions/password_reset.js`

**Purpose:** Completes the password reset by updating Firebase Auth

**Flow:**
1. Receives email, code, and new password
2. Validates code one more time (defense in depth)
3. Uses Firebase Admin SDK to update user password
4. Deletes password reset record from Firestore
5. Returns success

**Security Features:**
- Double validation of code
- Uses Admin SDK (server-side authentication)
- Cleans up reset record after use
- Password updated in Firebase Auth (encrypted at rest)

## Testing the Setup

### Manual Testing Checklist:

1. **Test Password Reset on Mobile App:**
   - Open app → Forgot Password
   - Enter test email
   - Check email inbox for 4-digit code
   - Enter code on verification screen
   - Enter new password
   - Confirm password reset successful
   - Try logging in with new password

2. **Test Password Reset on Web:**
   - Navigate to forgot password page
   - Follow same steps as mobile

3. **Test Error Cases:**
   - Invalid code → should show error
   - Expired code → request new code
   - Too many attempts (5+) → should lock out
   - Password mismatch → should show error
   - Network timeout → should show friendly error

### Debug Tips:

1. **Check Cloud Function Logs:**
```powershell
firebase functions:log --only sendPasswordReset
firebase functions:log --only verifyResetCode  
firebase functions:log --only completePasswordReset
```

2. **Check SMTP Configuration:**
```powershell
firebase functions:config:get
```

3. **Test Cloud Function Locally:**
```powershell
firebase emulators:start --only functions
```

4. **Check Email Service:**
   - Look for emails in spam/junk folders
   - Verify "from" address is whitelisted
   - Check email provider logs for SMTP errors

## Common Issues & Solutions

### Issue: "Cloud Functions deployment failed"
**Cause:** Firebase project not on Blaze plan
**Solution:** Upgrade to Blaze plan (Step 1 above)

### Issue: "Emails not being sent"
**Cause:** SMTP configuration not set correctly
**Solution:** 
1. Run `firebase functions:config:get` to verify settings
2. Check email provider logs for SMTP failures
3. For Gmail, ensure App Password is used (not regular password)
4. Check if Gmail account has 2FA enabled

### Issue: "Invalid function URL"
**Cause:** Project ID in Cloud Functions Config is outdated
**Solution:** Update `lib/app/cloud_functions_config.dart` with correct URLs

### Issue: "Code expired too quickly"
**Cause:** Server time mismatch with Firestore timestamps
**Solution:** Check that server time is correct; Firestore uses server timestamps

### Issue: "Too many attempts error"
**Cause:** User entered wrong code 5+ times
**Solution:** User must request new code after 5 failed attempts

## Environment Variables for Deployment

To make deployment more secure, use environment variables:

1. Create `.env.production` in `functions` directory
2. Set variables before deploying:
```powershell
$env:SMTP_USER="production-email@gmail.com"
$env:SMTP_PASS="your-production-app-password"
firebase deploy --only functions
```

## Next Steps

1. Upgrade Firebase to Blaze plan
2. Set up SMTP configuration (Gmail or other provider)
3. Run `firebase deploy --only functions`
4. Test password reset flow
5. Monitor Cloud Function logs for any errors
6. Deploy Flutter app build with password reset screens

## Additional Resources

- Firebase Configuration: https://firebase.google.com/docs/functions/config-env
- Nodemailer Documentation: https://nodemailer.com/
- Gmail App Passwords: https://support.google.com/accounts/answer/185833
- Firebase Admin SDK: https://firebase.google.com/docs/admin/setup

## Support

If you encounter issues:
1. Check Cloud Function logs: `firebase functions:log`
2. Verify SMTP configuration: `firebase functions:config:get`
3. Check Firestore password_resets collection for reset records
4. Review this guide's "Common Issues" section
