## Password Reset - Quick Troubleshooting Guide

### Step-by-Step Testing

#### Pre-Flight Checklist
```powershell
# 1. Check Firebase Configuration
firebase functions:config:get

# Expected output should show:
# smtp:
#   host: smtp.gmail.com
#   pass: your-app-password
#   port: 587
#   user: your-email@gmail.com
```

#### Test Cloud Functions Locally
```powershell
cd C:\capstone\mycapstone_project
firebase emulators:start --only functions

# In another PowerShell window, test sending code:
$body = @{email="test@gmail.com"} | ConvertTo-Json
Invoke-WebRequest -Uri "http://localhost:5001/capstone-c98f9/us-central1/sendPasswordReset" `
  -Method POST `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

#### Check Cloud Function Logs After Deployment
```powershell
# View real-time logs
firebase functions:log --follow

# Filter by specific function
firebase functions:log --only sendPasswordReset
firebase functions:log --only verifyResetCode
firebase functions:log --only completePasswordReset

# Show last N lines
firebase functions:log | Select-Object -Last 50
```

#### Verify Firestore Setup
1. Go to https://console.firebase.google.com/project/capstone-c98f9/firestore
2. Navigate to Collections
3. Check if `password_resets` collection exists
4. Look for test documents with structure:
```json
{
  "email": "user@example.com",
  "hashedCode": "...",
  "salt": "...",
  "createdAt": "...",
  "expiryAt": "..."
}
```

### Common Error Messages

| Error | Cause | Fix |
|-------|-------|-----|
| "Missing required API cloudbuild.googleapis.com" | Project on Spark plan | Upgrade to Blaze plan |
| "Failed to send email" | SMTP not configured | Run: `firebase functions:config:set smtp.user="..." smtp.pass="..."` |
| "[nodemailer] Error: Invalid login" | Wrong Gmail password | Use 16-character App Password, not regular password |
| "Reset code has expired" | Code older than 15 minutes | Allow user to request new code |
| "Too many attempts" | User entered code wrong 5+ times | User must request new code |
| "Invalid verification code" | Wrong code submitted | Check code in email vs entered value |

### Testing Scenarios

#### Scenario 1: Complete Success Flow
```
1. User email: test@example.com
2. User requests password reset
3. Cloud Function sends email with code
4. User receives email with 4-digit code
5. User enters code → verified
6. User enters new password
7. Password updated successfully
8. User logs in with new password ✓
```

#### Scenario 2: Invalid Code
```
1. User enters wrong code
2. System should show: "Invalid verification code"
3. Attempts counter increments
4. After 5 attempts: "Too many attempts. Request a new code."
5. User requests new code ✓
```

#### Scenario 3: Code Expiry
```
1. Code generated at 12:00pm
2. User waits 15+ minutes
3. User tries to verify code
4. System should show: "Reset code has expired"
5. User can click "Send new code" ✓
```

### Network Testing

#### Test Cloud Function URLs
```powershell
# Test sendPasswordReset endpoint
$body = @{email="test@example.com"} | ConvertTo-Json
Invoke-WebRequest -Uri "https://us-central1-capstone-c98f9.cloudfunctions.net/sendPasswordReset" `
  -Method POST `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body

# Should return:
# {"success":true,"message":"Code sent to email"}

# Test verifyResetCode endpoint
$body = @{email="test@example.com"; code="1234"} | ConvertTo-Json
Invoke-WebRequest -Uri "https://us-central1-capstone-c98f9.cloudfunctions.net/verifyResetCode" `
  -Method POST `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body

# Test completePasswordReset endpoint
$body = @{
  email="test@example.com"
  code="1234"
  newPassword="NewPassword123"
} | ConvertTo-Json
Invoke-WebRequest -Uri "https://us-central1-capstone-c98f9.cloudfunctions.net/completePasswordReset" `
  -Method POST `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

### Email Debugging

#### Check Gmail App Passwords
1. Go to https://myaccount.google.com/apppasswords
2. Select the app password you created
3. Verify it matches the one in Firebase config
4. If wrong, delete and create a new one

#### Check SMTP Settings
```powershell
$smtpConfig = firebase functions:config:get | ConvertFrom-Json
$smtpConfig.smtp | Format-Table -AutoSize
```

#### Test SMTP Connection Manually
```powershell
# Using Test-NetConnection to verify SMTP port is open
Test-NetConnection -ComputerName smtp.gmail.com -Port 587

# Should show: "TcpTestSucceeded: True"
```

### Dart/Flutter Debugging

#### Enable HTTP Logging
Add to your Dart code temporarily:
```dart
import 'package:http/http.dart' as http;

// Wrap HTTP calls with logging
Future<http.Response> sendWithLogging(Uri url, {required Map body}) {
  print('Sending to: $url');
  print('Body: $body');
  return http.post(url, body: jsonEncode(body))
    .then((response) {
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
      return response;
    });
}
```

#### Check Cloud Functions Config in App
```dart
import 'package:mycapstone_project/app/cloud_functions_config.dart';

// Print the URLs to verify they're correct
print('sendPasswordReset URL: ${CloudFunctionsConfig.sendPasswordResetUrl}');
print('verifyResetCode URL: ${CloudFunctionsConfig.verifyResetCodeUrl}');
print('completePasswordReset URL: ${CloudFunctionsConfig.completePasswordResetUrl}');
```

### Package Verification

#### Verify npm dependencies
```powershell
cd C:\capstone\mycapstone_project\functions
npm list

# Should show:
# ├── cors@2.8.6
# ├── firebase-admin@12.7.0
# ├── firebase-functions@4.9.0
# └── nodemailer@6.10.1
```

#### Verify Flutter dependencies
```bash
flutter pub get
# or in project root
dart pub get
```

### After Making Changes

#### Redeployment Steps
```powershell
# 1. Update code in functions/password_reset.js
# 2. Test locally with emulator
firebase emulators:start --only functions

# 3. Deploy to production
firebase deploy --only functions

# 4. Verify deployment
firebase functions:log | Select-Object -Last 20
```

#### Rebuilding Flutter App
```bash
flutter clean
flutter pub get
flutter run
```

### Still Having Issues?

1. **Check Cloud Function Code:**
   - Verify `functions/password_reset.js` has no syntax errors
   - Check for missing dependencies

2. **Check Firestore Rules:**
   - Go to https://console.firebase.google.com/project/capstone-c98f9/firestore/rules
   - Verify password_resets collection is accessible from Cloud Functions

3. **Check Firebase Console:**
   - https://console.firebase.google.com/project/capstone-c98f9
   - View any error notifications
   - Check function executions in Monitoring tab

4. **Check Email Service:**
   - Is email being received in spam folder?
   - Is sender address whitelisted?
   - Check email provider's SMTP logs

5. **Enable Debug Mode:**
   - Set environment variable: `DEBUG=*`
   - Run: `firebase functions:log --follow`
   - Perform test reset to see detailed logs
