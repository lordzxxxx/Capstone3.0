# Password Reset Email Configuration Guide

## Problem
The password reset emails are not being received by users. This is because:
1. Firebase's default email service requires domain verification
2. The SMTP configuration needs to be properly set up
3. The app needs to call the custom Cloud Function instead of Firebase's built-in method

## Solution
This guide sets up proper email sending using **nodemailer** with SMTP (Gmail or custom SMTP server).

---

## Step 1: Configure Firebase Functions with Email Credentials

### Option A: Gmail with App Password (Recommended for Testing)

1. **Enable 2-Factor Authentication on your Gmail account**
   - Go to https://myaccount.google.com/security
   - Enable 2-Step Verification

2. **Generate an App Password**
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" and "Windows/Mac/Linux"
   - Copy the generated 16-character password

3. **Set Firebase Functions Config**

```bash
# Windows PowerShell
firebase functions:config:set smtp.user="your-email@gmail.com" smtp.pass="xxxx xxxx xxxx xxxx"

# macOS/Linux
firebase functions:config:set smtp.user="your-email@gmail.com" smtp.pass="xxxx xxxx xxxx xxxx"
```

### Option B: Custom SMTP Server (SendGrid, AWS SES, etc.)

```bash
firebase functions:config:set \
  smtp.host="smtp.sendgrid.net" \
  smtp.port="587" \
  smtp.user="apikey" \
  smtp.pass="SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Option C: Self-Hosted SMTP Server

```bash
firebase functions:config:set \
  smtp.host="mail.example.com" \
  smtp.port="587" \
  smtp.user="mail@example.com" \
  smtp.pass="your-password" \
  smtp.secure="false"
```

---

## Step 2: Deploy Updated Cloud Functions

```bash
# Navigate to functions folder
cd functions

# Install dependencies
npm install

# Deploy to Firebase
firebase deploy --only functions
```

---

## Step 3: Update Frontend to Use Custom Function

Update [lib/web/forgot.dart](lib/web/forgot.dart):

```dart
// OLD CODE (using Firebase default)
await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

// NEW CODE (using custom Cloud Function)
final response = await http.post(
  Uri.parse('https://YOUR_PROJECT.cloudfunctions.net/sendPasswordResetEmail'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'email': email}),
);

if (response.statusCode != 200) {
  throw Exception('Failed to send reset email');
}
```

---

## Step 4: Update Flutter App Password Reset Flow

The new flow uses verification codes stored in Firestore:

### Frontend (Flutter):
1. User enters email → calls `sendPasswordResetEmail` Cloud Function
2. User receives email with 6-digit code
3. User enters code in app
4. App calls `verifyResetCode` to validate code
5. User enters new password
6. App calls `completePasswordReset` with session token  
7. Password is updated in Firebase Auth

### Backend (Cloud Functions):
- `sendPasswordResetEmail` - Generates code, saves to Firestore, sends email via nodemailer
- `verifyResetCode` - Validates code, generates session token
- `completePasswordReset` - Updates password in Firebase Auth

---

## Configuration Files

### Functions Config Auto-Generated
After running `firebase functions:config:set`, the following files are created:
```
functions/.runtimeconfig.json (local - DO NOT COMMIT)
Firebase Project console (stored securely)
```

### View Current Configuration
```bash
firebase functions:config:get
```

### Unset Configuration
```bash
firebase functions:config:unset smtp.pass
```

---

## Testing the Setup

### 1. Local Testing with Emulator
```bash
# Start Firebase emulator
firebase emulators:start --only functions

# Configure emulator environment variables
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
```

### 2. Test Email Sending
```bash
# Call the function via HTTP
curl -X POST http://localhost:5001/YOUR_PROJECT/us-central1/sendPasswordResetEmail \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'
```

### 3. Check Logs
```bash
# View Cloud Functions logs
firebase functions:log

# Or in Firebase Console
# → Functions → Logs tab
```

---

## Troubleshooting

### Issue: "SMTP configuration incomplete" warning
**Solution**: Set all SMTP config values:
```bash
firebase functions:config:set \
  smtp.user="your-email@gmail.com" \
  smtp.pass="your-app-password" \
  smtp.host="smtp.gmail.com" \
  smtp.port="587"
```

### Issue: "Failed to send email" error
**Solutions**:
1. Verify SMTP credentials are correct
2. Check Gmail: [Allow less secure apps](https://myaccount.google.com/lesssecureapps)
3. Use App Password instead of regular password
4. Check firewall/network isn't blocking port 587
5. Verify sender email address is allowed to send

### Issue: Email goes to spam folder
**Solutions**:
1. Add SPF/DKIM/DMARC records for your domain
2. Use a verified sender domain
3. Include verification link in email
4. Use proper HTML formatting (already included)

### Issue: "user-not-found" error
**Solution**: User must have registered account first
- User must create account before requesting password reset
- Check if email exists in Firebase Auth

### Issue: Verification code still not received after setup
**Solutions**:
1. Check Firebase Console → Functions → Logs for errors
2. Check email spam/filters folder
3. Verify SMTP settings are correctly set:
   ```bash
   firebase functions:config:get
   ```
4. Test with a different email address
5. Check email provider isn't blocking the sender

---

## Email Template Customization

Edit [functions/send_password_reset.js](functions/send_password_reset.js) to customize:
- Email subject
- HTML template
- From address
- Text fallback

Look for the `mailOptions` section in `sendPasswordResetEmail` function.

---

## Security Notes

1. **Never commit `.runtimeconfig.json`** - It contains sensitive credentials
2. **Use environment variables** in production
3. **Rate limit** password reset requests (already implemented - max 5 attempts)
4. **Add CORS verification** - Only allow requests from your domain
5. **Verify email ownership** - Users should verify emails
6. **Hash codes** - Verification codes are hashed before storage

---

## Environment Variables Alternative

Instead of Firebase config, you can use environment variables:

```bash
# Set environment variables
export SMTP_USER="your-email@gmail.com"
export SMTP_PASS="your-app-password"
export APP_URL="https://yourdomain.com"
```

The Cloud Function will check environment variables if Firebase config is not set.

---

## Next Steps

1. ✅ Set up SMTP credentials (Step 1)
2. ✅ Deploy Cloud Functions (Step 2)
3. ⏳ Update Flutter app to use new endpoint (Step 3)
4. ✅ Test password reset flow (Step 4)
5. ✅ Monitor logs in Firebase Console

---

## Support

If password reset emails still aren't received:
1. Check Firebase Console → Functions → Logs
2. Verify SMTP configuration with: `firebase functions:config:get`
3. Test SMTP credentials directly with nodemailer:
   ```bash
   node test-smtp.js
   ```
4. Check email provider's security settings
5. Verify sender domain is not on email blacklist
