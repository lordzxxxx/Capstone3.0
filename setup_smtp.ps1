# SMTP Configuration Script for Firebase Functions (Windows PowerShell)
# This script helps you set up SMTP configuration for the invitation system

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SMTP Configuration Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Choose your email provider:" -ForegroundColor Yellow
Write-Host "1) Gmail (Recommended for testing)"
Write-Host "2) Outlook / Office 365"
Write-Host "3) Custom SMTP Server"
Write-Host ""

$choice = Read-Host "Enter your choice (1-3)"

switch ($choice) {
  "1" {
    Write-Host ""
    Write-Host "Gmail Setup Instructions:" -ForegroundColor Yellow
    Write-Host "1. Go to https://myaccount.google.com/security"
    Write-Host "2. Enable 2-Step Verification (if not already enabled)"
    Write-Host "3. Go to App passwords → Select 'Mail' and 'Windows Computer'"
    Write-Host "4. Copy the 16-character password generated"
    Write-Host ""
    
    $gmail = Read-Host "Enter your Gmail address"
    $appPass = Read-Host "Enter your App Password (16 chars)" -AsSecureString
    $appPassText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($appPass))
    
    Write-Host ""
    Write-Host "Configuring Firebase functions..." -ForegroundColor Green
    
    & firebase functions:config:set smtp.host="smtp.gmail.com"
    & firebase functions:config:set smtp.port="587"
    & firebase functions:config:set smtp.secure="false"
    & firebase functions:config:set smtp.user="$gmail"
    & firebase functions:config:set smtp.password="$appPassText"
    & firebase functions:config:set smtp.fromemail="$gmail"
    
    Write-Host "✅ Gmail SMTP configured!" -ForegroundColor Green
  }
  "2" {
    Write-Host ""
    Write-Host "Outlook / Office 365 Setup:" -ForegroundColor Yellow
    
    $email = Read-Host "Enter your email address"
    $password = Read-Host "Enter your password" -AsSecureString
    $passwordText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($password))
    
    Write-Host ""
    Write-Host "Configuring Firebase functions..." -ForegroundColor Green
    
    & firebase functions:config:set smtp.host="smtp.office365.com"
    & firebase functions:config:set smtp.port="587"
    & firebase functions:config:set smtp.secure="false"
    & firebase functions:config:set smtp.user="$email"
    & firebase functions:config:set smtp.password="$passwordText"
    & firebase functions:config:set smtp.fromemail="$email"
    
    Write-Host "✅ Outlook SMTP configured!" -ForegroundColor Green
  }
  "3" {
    Write-Host ""
    Write-Host "Custom SMTP Server Setup:" -ForegroundColor Yellow
    
    $host = Read-Host "Enter SMTP server hostname"
    $port = Read-Host "Enter SMTP port (usually 587)"
    $user = Read-Host "Enter username"
    $pass = Read-Host "Enter password" -AsSecureString
    $passText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($pass))
    $secure = Read-Host "Enable TLS/SSL? (true/false)"
    $fromEmail = Read-Host "Enter From email address"
    
    Write-Host ""
    Write-Host "Configuring Firebase functions..." -ForegroundColor Green
    
    & firebase functions:config:set smtp.host="$host"
    & firebase functions:config:set smtp.port="$port"
    & firebase functions:config:set smtp.secure="$secure"
    & firebase functions:config:set smtp.user="$user"
    & firebase functions:config:set smtp.password="$passText"
    & firebase functions:config:set smtp.fromemail="$fromEmail"
    
    Write-Host "✅ Custom SMTP configured!" -ForegroundColor Green
  }
  default {
    Write-Host "Invalid choice!" -ForegroundColor Red
    exit 1
  }
}

Write-Host ""
Write-Host "Verifying configuration..." -ForegroundColor Green
& firebase functions:config:get

Write-Host ""
Write-Host "Deploying functions..." -ForegroundColor Green
& firebase deploy --only functions

Write-Host ""
Write-Host "✅ Setup complete! Invitations will now be sent via SMTP." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test by sending an invitation from the admin panel"
Write-Host "2. Check inbox (and spam folder)"
Write-Host "3. View logs if there are issues: firebase functions:log"
