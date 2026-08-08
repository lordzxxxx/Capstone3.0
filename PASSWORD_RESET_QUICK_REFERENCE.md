# 6-Digit Password Reset Implementation - Quick Reference

## What Changed

✅ **Old Flow:** Email → Link → Password Reset Form → Done
✅ **New Flow:** Email → 6-Digit Code → Verify Code → New Password → Done

## Files Created/Modified

| File | Status | Purpose |
|------|--------|---------|
| `lib/app/forgot.dart` | Modified | Email entry screen (sends code) |
| `lib/app/verification_code.dart` | New | 6-digit code input screen |
| `lib/app/new_password.dart` | New | New password creation screen |
| `lib/app/reset_password_service.dart` | New | Service layer for all operations |
| `functions/password_reset.js` | New | Cloud Functions for email & password update |
| `functions/password_reset_v2.js` | New | Enhanced Cloud Function version |

## Step-by-Step Implementation

### 1. Update pubspec.yaml
Add this if not already present:
```yaml
dependencies:
  cloud_firestore: ^latest_version
  firebase_auth: ^latest_version
  get: ^latest_version
```

### 2. Create Firestore Collection Rules
Update your `firestore.rules`:
```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Password reset documents - temporary
    match /password_resets/{email} {
      allow create: if request.size < 2KB;
      allow read, update, delete: if false; // Cloud Functions handle these
    }
  }
}
```

### 3. Deploy Cloud Functions
```bash
cd functions
npm install
firebase deploy --only functions:sendPasswordResetCode
firebase deploy --only functions:cleanupExpiredResets
firebase deploy --only functions:logPasswordResetEvent
```

### 4. Update Navigation
In your main.dart or login screen, ensure the ForgotPassword route is accessible:
```dart
onTap: () => Get.to(() => const ForgotPassword()),
```

### 5. Test the Flow
1. Navigate to Forgot Password
2. Enter email address
3. Check Firebase Firestore for generated code
4. Enter code (from console logs in development)
5. Enter new password
6. Verify login works with new password

## Security Features Implemented

✅ 15-minute code expiry  
✅ 5-attempt lockout  
✅ 30-second resend cooldown  
✅ Password strength requirements  
✅ Session tokens  
✅ Automatic cleanup of expired sessions  
✅ Audit logging of security events  

## Testing Checklist

### Email Entry
- [ ] Empty email rejected
- [ ] Invalid email rejected  
- [ ] Non-existent user rejected
- [ ] Valid email proceeds to code screen

### Code Verification
- [ ] Wrong code rejected with attempt counter
- [ ] 5 attempts triggers lockout
- [ ] Code expires after 15 minutes
- [ ] Resend available after 30 seconds
- [ ] Correct code proceeds to password screen

### Password Reset
- [ ] Password strength validated in real-time
- [ ] Weak password rejected
- [ ] Password match required
- [ ] Strong password accepted
- [ ] Success redirects to login
- [ ] New password works for login

## Development: View Generated Code

During development, codes are logged. To see them:

**Option 1: Firebase Console**
- Go to Cloud Functions logs
- Filter by `password_reset`
- Look for: `[PASSWORD_RESET] Code for...`

**Option 2: Console Output (Local)**
```bash
firebase emulators:start
```
Codes will print in terminal

## Production: Send Real Emails

### Configure SendGrid
1. Set up SendGrid API key (see EMAIL_SERVICE_SETUP.md)
2. Uncomment email sending code in `functions/password_reset.js`
3. Deploy functions

### Test Email Sending
```bash
firebase functions:config:set sendgrid.key="SG.xxx"
firebase deploy --only functions:sendPasswordResetCode
```

## Troubleshooting

### Code not working?
```
Error: FirebaseAuth not initialized
→ Solution: Ensure Firebase is initialized before app startup
```

### Firestore errors?
```
Error: Missing or insufficient permissions
→ Solution: Check firestore.rules allows password_resets collection
```

### Code not sent?
```
Check: functions/password_reset.js - is email service configured?
Check: Firebase Functions logs for errors
Check: User email exists in Firebase Auth
```

### Cloud Function call failing?
```
Add to pubspec.yaml:
dependencies:
  cloud_functions: ^latest
```

## Architecture

```
forgot.dart
    ↓ (sendVerificationCode)
reset_password_service.dart
    ↓ (stores code in Firestore)
Firestore password_resets collection
    ↓ (triggers)
Cloud Function (sendPasswordResetCode)
    ↓ (sends email)
verification_code.dart
    ↓ (verifyCode)
reset_password_service.dart
    ↓ (marks verified)
new_password.dart
    ↓ (resetPassword)
reset_password_service.dart
    ↓ (calls updatePasswordWithToken Cloud Function)
Cloud Function (updatePasswordWithToken)
    ↓ (updates Firebase Auth)
login.dart
```

## Key Methods

### ResetPasswordService
- `sendVerificationCode(email)` - Initial email send
- `verifyCode(email, code)` - Code validation  
- `resetPassword(email, password)` - Prepare password change
- `completePasswordReset(email)` - Finalize password update
- `resendVerificationCode(email)` - Resend with cooldown

### VerificationCode Widget
- `_verifyCode()` - Submit entered code
- `_resendCode()` - Request new code
- `_onCodeInputChange()` - Auto-focus between digits
- `_startResendCountdown()` - 30-second cooldown

### NewPassword Widget
- `_resetPassword()` - Submit new password
- `_getPasswordRequirements()` - Check requirements
- `_updatePasswordStrength()` - Real-time strength indicator

## Common Customizations

### Change Code Expiry Time
In `reset_password_service.dart`:
```dart
// Change from 15 to 30 minutes
final expiryTime = DateTime.now().add(const Duration(minutes: 30));
```

### Change Max Attempts
```dart
// Change from 5 to 10 attempts
if (attempts >= 10) {
  throw Exception('Too many attempts...');
}
```

### Add SMS Instead of Email
Create `sendVerificationCodeViaSMS()` function using Twilio or similar

### Customize Password Requirements
In `new_password.dart`, update `_getPasswordRequirements()`:
```dart
// Add/remove requirements as needed
if (password.length < 10) unmet.add('At least 10 characters');
```

## Next Steps

1. ✅ Set up email service (SendGrid recommended)
2. ✅ Deploy Cloud Functions  
3. ✅ Test locally with emulator
4. ✅ Test in staging environment
5. ✅ Deploy to production
6. ✅ Monitor logs for issues
7. ✅ Gather user feedback

## Support

For detailed setup instructions, see:
- `PASSWORD_RESET_README.md` - Full documentation
- `EMAIL_SERVICE_SETUP.md` - Email configuration guide
