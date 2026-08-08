# Password Reset Email Fix - Quick Start

## The Problem
Password reset emails are not being received because:
- Firebase's default `sendPasswordResetEmail()` doesn't send emails via SMTP
- SMTP is partially configured but not being used
- The app needs to call the custom Cloud Function

## The Solution (3 Steps)

### Step 1: Configure SMTP Email Service
**Choose one:**

**Option A: Gmail (Easiest)**
```bash
# First, get an App Password from https://myaccount.google.com/apppasswords
firebase functions:config:set smtp.user="your-email@gmail.com" smtp.pass="xxxx xxxx xxxx xxxx"
```

**Option B: Use Setup Script**
```bash
# Windows PowerShell
.\setup_email_service.ps1

# macOS/Linux
bash setup_email_service.sh
```

### Step 2: Deploy Updated Cloud Functions
```bash
cd functions
npm install
firebase deploy --only functions
```

### Step 3: Update Frontend (Edit Flutter Code)
**File:** `lib/web/forgot.dart` (line ~42)

Replace:
```dart
await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
```

With:
```dart
final response = await http.post(
  Uri.parse('https://YOUR_PROJECT_ID.cloudfunctions.net/sendPasswordResetEmail'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'email': emailController.text.trim()}),
);

if (response.statusCode != 200) {
  throw Exception('Failed to send reset email: ${response.body}');
}
```

Also add at top:
```dart
import 'package:http/http.dart' as http;
import 'dart:convert' show jsonEncode;
```

---

## What Was Created

1. **Cloud Function**: `functions/send_password_reset.js`
   - Sends emails via nodemailer with SMTP
   - Generates verification codes
   - Validates codes with rate limiting
   - Updates passwords securely

2. **Configuration Scripts**:
   - `setup_email_service.sh` (for Mac/Linux)
   - `setup_email_service.ps1` (for Windows)
   - Both automate SMTP configuration

3. **Documentation**:
   - `PASSWORD_RESET_EMAIL_FIX.md` - Complete setup guide
   - `PASSWORD_RESET_QUICK_REFERENCE.md` - Reference docs

---

## Verify It's Working

### Check Configuration
```bash
firebase functions:config:get
```
Should show your SMTP settings (password masked).

### Check Logs
```bash
firebase functions:log
```
Look for: `Password reset email sent to [user@email.com]`

### Test Email
1. Go to forgot password page
2. Enter test email address
3. Check inbox (and spam folder)
4. Should receive email with verification code

---

## Email Flow (New)

```
User clicks "Forgot Password"
        ↓
Enters email address
        ↓
Frontend calls Cloud Function (sendPasswordResetEmail)
        ↓
Function generates 6-digit code
        ↓
Code is hashed and stored in Firestore (15 min expiry)
        ↓
Email sent via SMTP with code
        ↓
User receives email ✅
        ↓
User enters code in app
        ↓
Frontend validates code (verifyResetCode function)
        ↓
User enters new password
        ↓
Frontend calls (completePasswordReset) with session token
        ↓
Password updated in Firebase Auth
        ↓
User can log in with new password ✅
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Email not received | Check spam folder, verify SMTP config is set |
| SMTP config error | Run `firebase functions:config:get` |
| Gmail app password rejected | Use 16-character password without spaces |
| Function deployment fails | Run `npm install` in functions folder first |
| "user-not-found" error | User must register account before reset Password |

---

## Gmail App Password Setup (5 minutes)

1. Go to https://myaccount.google.com/security
2. Enable 2-Step Verification (if not already)
3. Go to https://myaccount.google.com/apppasswords
4. Select "Mail" and "Windows/Mac/Linux"
5. Click Generate
6. Copy the 16-character password (with spaces)
7. Use in command:
   ```bash
   firebase functions:config:set smtp.user="your-email@gmail.com" smtp.pass="xxxx xxxx xxxx xxxx"
   ```

---

## Security Features Included

✅ Rate limiting (5 attempts max)
✅ Code hashing before storage
✅ 15-minute expiration
✅ Session tokens for password reset
✅ CORS protection
✅ Input validation
✅ Secure password updates

---

## Files Modified/Created

| File | Change | Purpose |
|------|--------|---------|
| `functions/send_password_reset.js` | ✨ NEW | Custom email sending function |
| `functions/package.json` | ✏️ UPDATED | Added cors dependency |
| `setup_email_service.ps1` | ✨ NEW | Windows setup automation |
| `setup_email_service.sh` | ✨ NEW | Mac/Linux setup automation |
| `PASSWORD_RESET_EMAIL_FIX.md` | ✨ NEW | Complete documentation |

---

## Next: Update the App

The last step is updating your Flutter app to call the new Cloud Function. You'll need to:

1. Add HTTP import
2. Replace Firebase email method with HTTP call to Cloud Function
3. Update frontend to use new verification code flow

**See:** `PASSWORD_RESET_EMAIL_FIX.md` → "Step 3: Update Frontend"

---

## Questions?

- Check logs: `firebase functions:log`
- Verify config: `firebase functions:config:get`
- Test SMTP manually with nodemailer
- Review function code: `functions/send_password_reset.js`
