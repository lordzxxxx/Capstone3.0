# 6-Digit Password Reset Flow Implementation

This document explains the new password reset flow that uses 6-digit verification codes instead of reset links.

## Flow Overview

1. **Email Entry Screen** (`forgot.dart`)
   - User enters their email address
   - System sends verification code to email
   - User is directed to verification screen

2. **Verification Code Screen** (`verification_code.dart`)
   - User enters 6-digit code received via email
   - Code is validated against stored code in Firestore
   - Code expires after 15 minutes
   - Maximum 5 attempts allowed
   - User can resend code (30-second cooldown)

3. **New Password Screen** (`new_password.dart`)
   - User enters new password
   - Password strength requirements enforced:
     - At least 8 characters
     - One uppercase letter
     - One lowercase letter
     - One number
     - One special character (!@#$%^&*)
   - User confirms password
   - Password is reset
   - User redirected to login

## Key Components

### 1. `reset_password_service.dart`
Central service handling all password reset operations:
- **sendVerificationCode()** - Generates 6-digit code and stores in Firestore
- **verifyCode()** - Validates user-entered code
- **resetPassword()** - Prepares password reset in Firestore
- **completePasswordReset()** - Finalizes the reset
- **resendVerificationCode()** - Allows user to request new code

### 2. `forgot.dart` (Modified)
Updated to:
- Call `ResetPasswordService.sendVerificationCode()`
- Navigate to `VerificationCode` screen instead of showing login
- Display new messaging about verification codes

### 3. `verification_code.dart` (New)
6-digit code input interface:
- Individual input fields for each digit
- Auto-focus between fields
- Error handling and display
- Resend code functionality with 30-second cooldown
- Redirects to password reset screen on successful verification

### 4. `new_password.dart` (New)
Password creation interface:
- Real-time password strength indicator
- Requirements validation
- Password match confirmation
- Redirects to login on successful reset

### 5. `functions/password_reset.js` (Cloud Function)
Server-side functionality:
- Triggered on new password reset document creation
- Sends verification code email
- Handles password update via Firebase Admin SDK

## Firestore Data Structure

### Collection: `password_resets`
```
{
  email: "user@example.com",
  code: "123456",
  createdAt: Timestamp,
  expiryAt: Timestamp (15 minutes from creation),
  verified: false,
  attempts: 0,
  sessionToken: "random_token_string",
  newPassword: "hashed_password",
  readyToReset: false
}
```

## Setup Instructions

### 1. Enable Firestore
Ensure Cloud Firestore is enabled in your Firebase project.

### 2. Create Firestore Security Rules
Update your `firestore.rules`:

```rules
match /password_resets/{email} {
  allow create: if request.size < 1KB;
  allow read, update, delete: if false; // Handled by Cloud Functions
}
```

### 3. Deploy Cloud Function
```bash
cd functions
npm install
firebase deploy --only functions:sendPasswordResetCode
firebase deploy --only functions:completePasswordReset
firebase deploy --only functions:updateUserPassword
```

### 4. Configure Email Service

Choose one of the following email services:

#### Option A: SendGrid (Recommended)
1. Install SendGrid in Firebase Functions:
   ```bash
   npm install @sendgrid/mail
   ```

2. Add SendGrid API key to Firebase Secrets:
   ```bash
   firebase functions:config:set sendgrid.key="your-sendgrid-api-key"
   ```

3. Update `functions/password_reset.js` to uncomment SendGrid section

#### Option B: Firebase Extensions
Install "Trigger Email from Cloud Storage" or similar extension

#### Option C: Gmail API
Configure OAuth2 credentials for sending emails programmatically

### 5. Test the Flow
1. Go to Forgot Password screen
2. Enter email address
3. Check Firestore for generated code
4. Enter code in verification screen
5. Set new password
6. Verify password changed successfully

## Security Considerations

✅ **Implemented:**
- 15-minute code expiry
- 5-attempt limit before lockout
- Email verification before password change
- Password strength requirements
- Temporary session tokens

⚠️ **Additional Recommendations:**
- Rate limiting on email sends (prevent spam)
- Account lockout after multiple failed attempts
- Require re-authentication before allowing password change
- Audit logging for password resets
- Send confirmation email after successful reset
- Consider CAPTCHA for repeated failed attempts

## Error Handling

The implementation handles:
- Non-existent email addresses
- Expired codes
- Invalid codes
- Too many attempts
- Session expiry
- Database connectivity issues

## Troubleshooting

### Code not received
- Check email spam/junk folder
- Verify SendGrid/email service configuration
- Check Cloud Functions logs in Firebase Console
- Enable debug logging in `reset_password_service.dart`

### Code verification fails
- Ensure code matches exactly (case-sensitive if applicable)
- Check code hasn't expired (15-minute limit)
- Verify Firestore document exists and is valid
- Check for database permission issues

### Password not updating
- Verify Cloud Function `updateUserPassword` is deployed
- Check user exists in Firebase Authentication
- Verify password meets requirements
- Check Cloud Function logs for errors

## Future Enhancements

- [ ] SMS code delivery option
- [ ] Biometric verification
- [ ] Password reset via security questions
- [ ] Backup email/phone for recovery
- [ ] Account recovery checklist
- [ ] Integration with identity verification services

## Testing

### Manual Testing
1. Test with valid email
2. Test with non-existent email
3. Test code expiry (wait 15+ minutes)
4. Test max attempts (enter wrong code 5 times)
5. Test resend cooldown (try resend within 30 seconds)
6. Test password strength validation
7. Test weak password rejection

### Automated Testing (Recommended)
Create unit tests for:
- Code generation
- Code verification
- Code expiry logic
- Password requirements validation
- Session token generation
