# Email Service Integration Guide

This guide explains how to set up email sending for the 6-digit verification codes.

## Quick Setup: SendGrid (Easiest)

### 1. Create SendGrid Account
- Go to [sendgrid.com](https://sendgrid.com)
- Sign up for free account (includes 100 emails/day)
- Verify sender email address

### 2. Get API Key
- Login to SendGrid dashboard
- Navigate to Settings → API Keys
- Create new API Key with "Full Access" permission
- Copy the key (you won't see it again!)

### 3. Add to Firebase Project
```bash
firebase functions:config:set sendgrid.key="SG.xxxxxxxxxxxxx"
firebase functions:config:set sendgrid.email="noreply@yourdomain.com"
```

### 4. Update `functions/password_reset.js`

Replace the sendPasswordResetCode function with:

```javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");

admin.initializeApp();

exports.sendPasswordResetCode = functions.firestore
  .document("password_resets/{email}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const email = data.email;
    const code = data.code;

    try {
      sgMail.setApiKey(functions.config().sendgrid.key);

      const msg = {
        to: email,
        from: functions.config().sendgrid.email || "noreply@example.com",
        subject: "Your Password Reset Code",
        html: `
          <div style="font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px;">
            <div style="background-color: white; padding: 30px; border-radius: 10px; max-width: 500px; margin: 0 auto;">
              <h2 style="color: #0E2F34; margin-top: 0;">Password Reset Request</h2>
              <p style="color: #555; font-size: 16px;">
                We received a request to reset your password. Enter this 6-digit code in the app:
              </p>
              <div style="background-color: #f0f0f0; padding: 20px; border-radius: 5px; text-align: center; margin: 30px 0;">
                <span style="font-size: 48px; font-weight: bold; letter-spacing: 8px; color: #0E2F34; font-family: 'Courier New', monospace;">
                  ${code}
                </span>
              </div>
              <p style="color: #999; font-size: 14px;">
                <strong>⏱️ This code expires in 15 minutes</strong>
              </p>
              <p style="color: #555; font-size: 14px;">
                If you didn't request a password reset, please ignore this email or contact support.
              </p>
              <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">
              <p style="color: #999; font-size: 12px; text-align: center;">
                © 2024 Your App Name. All rights reserved.
              </p>
            </div>
          </div>
        `,
        text: `Your password reset code is: ${code}\n\nThis code expires in 15 minutes.`,
      };

      await sgMail.send(msg);
      console.log(`Password reset email sent to ${email}`);

      return { success: true };
    } catch (error) {
      console.error("Error sending email:", error);
      throw new functions.https.HttpsError("internal", "Failed to send email");
    }
  });
```

### 5. Install SendGrid Package
```bash
cd functions
npm install @sendgrid/mail
cd ..
```

### 6. Deploy
```bash
firebase deploy --only functions
```

---

## Alternative: Firebase Email Extension

### 1. Install Extension
```bash
firebase ext:install firebase/firestore-send-email
```

### 2. Configure During Installation
- Select your database
- Use collection: `mail` (or your preference)
- Configure SMTP settings or SendGrid

### 3. Update Function
In `functions/password_reset.js`, send email via Firestore:

```javascript
exports.sendPasswordResetCode = functions.firestore
  .document("password_resets/{email}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const email = data.email;
    const code = data.code;

    try {
      // Write to mail collection
      await admin.firestore().collection("mail").add({
        to: email,
        message: {
          subject: "Your Password Reset Code",
          html: generateEmailHtml(code),
          text: `Your password reset code is: ${code}`,
        },
      });

      console.log(`Email queued for ${email}`);
      return { success: true };
    } catch (error) {
      console.error("Error queuing email:", error);
      throw new functions.https.HttpsError("internal", "Failed to send email");
    }
  });

function generateEmailHtml(code) {
  return `
    <div style="font-family: Arial, sans-serif; padding: 20px;">
      <h2>Password Reset Code</h2>
      <p>Your 6-digit verification code is:</p>
      <h1 style="font-size: 48px; letter-spacing: 8px; color: #0E2F34;">
        ${code}
      </h1>
      <p>This code expires in 15 minutes.</p>
    </div>
  `;
}
```

---

## Testing Email Sending

### 1. Test in Emulator (Local Development)
```bash
firebase emulators:start
# In another terminal:
firebase functions:config:clone --project=YOUR_PROJECT_ID
# Edit .runtimeconfig.json with your test values
```

### 2. Test in Production
1. Go to Forgot Password screen
2. Enter test email
3. Check email inbox (including spam)
4. Verify code is received

### 3. Monitor Cloud Functions Logs
```bash
firebase functions:log --project=YOUR_PROJECT_ID
```

Look for:
- Email sending confirmation
- Error messages
- API rate limits

---

## Troubleshooting Email Issues

### Email not received
- ✅ Check spam/junk folder
- ✅ Verify email address is correct
- ✅ Check SendGrid sending quota
- ✅ Review Cloud Functions logs for errors
- ✅ Verify sender email is verified in SendGrid

### Email delayed
- SendGrid may take 1-2 minutes
- Check SendGrid dashboard for delivery status
- Review email queue in SendGrid Activity Feed

### Authentication error
- Verify API key is current (not expired)
- Check Firebase Functions config:
  ```bash
  firebase functions:config:get
  ```
- Ensure API key has "Full Access" or "Mail Send" permission

### Rate limiting
- SendGrid free tier allows 100 emails/day
- Upgrade for higher limits
- Implement client-side rate limiting

### Invalid recipient
- Verify email format in code
- Firestore rules might block unverified addresses
- Check for typos in `password_resets` document

---

## Production Checklist

- [ ] Upgrade SendGrid to paid plan for production
- [ ] Verify all sender email addresses in SendGrid
- [ ] Set up email templates in SendGrid (optional but recommended)
- [ ] Configure DKIM and SPF records for better deliverability
- [ ] Set up bounce/complaint webhooks to handle invalid emails
- [ ] Monitor daily email sends vs. quota
- [ ] Test with real email addresses before launch
- [ ] Set up error alerts in Firebase Functions
- [ ] Document support email for users who don't receive codes
- [ ] Consider adding SMS as backup verification method

---

## Cost Estimates

| Service | Free Tier | Pro Tier |
|---------|-----------|----------|
| SendGrid | 100 emails/day | $20+/month |
| Firebase | Included | Pay-per-use |
| Google Cloud | Free tier available | Varies |

Total monthly cost typically: **$0 - $50** depending on volume
