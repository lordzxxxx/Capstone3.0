# SMTP Configuration Guide for Invitations

Your invitation system now uses **Nodemailer with direct SMTP** - no API keys needed! Choose your preferred email provider below.

---

## **Option 1: Gmail (Recommended for Testing)**

### Step 1: Set Up Gmail App Password
1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable **2-Step Verification** (if not already enabled)
3. Go to **App passwords** → Select "Mail" and "Windows Computer"
4. Google will generate a 16-character password (example: `abcd efgh ijkl mnop`)
5. Copy this password (you'll need it)

### Step 2: Configure Firebase Functions
Run these commands in your terminal:

```bash
cd c:\capstone\mycapstone_project
firebase functions:config:set smtp.host="smtp.gmail.com"
firebase functions:config:set smtp.port="587"
firebase functions:config:set smtp.secure="false"
firebase functions:config:set smtp.user="your-email@gmail.com"
firebase functions:config:set smtp.password="abcd efgh ijkl mnop"
firebase functions:config:set smtp.fromemail="your-email@gmail.com"
```

### Step 3: Install Nodemailer & Deploy
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

✅ **Done!** Test by sending an invitation.

---

## **Option 2: Office 365 / Outlook**

### Step 1: Get SMTP Details
- **Host:** `smtp.office365.com`
- **Port:** `587`
- **Secure:** `false`
- **Username:** Your full email address (example: `user@company.com`)
- **Password:** Your Office 365 password

### Step 2: Configure Firebase Functions
```bash
firebase functions:config:set smtp.host="smtp.office365.com"
firebase functions:config:set smtp.port="587"
firebase functions:config:set smtp.secure="false"
firebase functions:config:set smtp.user="your-email@company.com"
firebase functions:config:set smtp.password="your-password"
firebase functions:config:set smtp.fromemail="your-email@company.com"
```

### Step 3: Deploy
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

---

## **Option 3: Custom SMTP Server (Corporate Email)**

If your organization has a custom email server:

### Step 1: Get SMTP Details from IT
Ask your IT department for:
- SMTP Server hostname
- SMTP port (typically 25, 587, or 465)
- Username
- Password
- Whether to enable TLS/SSL

### Step 2: Configure Firebase Functions
```bash
firebase functions:config:set smtp.host="your-smtp-server.com"
firebase functions:config:set smtp.port="587"
firebase functions:config:set smtp.secure="false"
firebase functions:config:set smtp.user="your-username"
firebase functions:config:set smtp.password="your-password"
firebase functions:config:set smtp.fromemail="noreply@yourdomain.com"
```

### Step 3: Deploy
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

---

## **Option 4: Sendgrid (Alternative to SMTP)**

If you prefer Sendgrid (requires API key):

### Step 1: Get Sendgrid API Key
1. Go to [sendgrid.com](https://sendgrid.com)
2. Create account and verify email
3. Create API key in Settings → API Keys

### Step 2: Edit `process_invitations.js` Manually
Use the SendGrid version instead (we can revert if needed)

---

## **Verify Configuration**

Check that your settings were saved:
```bash
firebase functions:config:get
```

You should see output like:
```
{
  "smtp": {
    "host": "smtp.gmail.com",
    "port": "587",
    "secure": "false",
    "user": "your-email@gmail.com",
    "password": "abcd efgh ijkl mnop",
    "fromemail": "your-email@gmail.com"
  }
}
```

---

## **Test the Invitation**

1. Log into the web app as admin
2. Go to **Settings** → **Manage Roles** (or find Invite button)
3. Enter a test email and send invitation
4. Check your inbox (and spam folder)

### Debug if Email Not Received:

1. **Check Firebase Function Logs:**
   ```bash
   firebase functions:log
   ```

2. **Look for errors starting with:**
   - `Failed to send invitation email via SMTP:`
   - `SMTP transporter not available`

3. **Common Issues:**
   - ❌ Gmail: 2-Step Verification not enabled
   - ❌ Gmail: Using main Gmail password instead of App Password
   - ❌ Outlook: Account locked due to suspicious activity
   - ❌ Custom SMTP: Wrong port or TLS settings
   - ❌ Firewall: Blocking SMTP port (contact IT)

---

## **Email Format**

The invitation email includes:
- Welcome message with user role
- "Set Your Password" button
- Direct password reset link
- Professional formatting

---

## **Change SMTP Provider Later**

To switch to a different email provider:

```bash
firebase functions:config:set \
  smtp.host="new-server.com" \
  smtp.user="new-email@domain.com" \
  smtp.password="new-password"

firebase deploy --only functions
```

---

## **Troubleshooting**

### Email not sent but no error:
- Check that all SMTP settings are configured
- Run: `firebase functions:config:get`

### "Connection timeout" error:
- Check firewall/network settings
- Verify SMTP port is correct (usually 587)
- Try port 465 with `smtp.secure="true"`

### "Authentication failed" error:
- Double-check username and password
- For Gmail, use App Password not regular password
- Check for spaces or special characters

### "Email rejected" error:
- Verify "From" email address is correct
- For Gmail, must match login email
- For Outlook, must match Office 365 account

---

## **Next Steps**

Once configured:
1. Invitations will be sent automatically when you create an admin role
2. Users will receive password reset emails
3. Users can set their password and log in
4. All activity is logged in Firebase

Need help? Check Firebase Function Logs: `firebase functions:log`
