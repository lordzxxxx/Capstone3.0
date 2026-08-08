# setup_email_service.ps1
# Configure Firebase Functions for email service (Windows PowerShell)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "DSUHIS Password Reset Email Configuration" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Firebase CLI is installed
$firebase = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebase) {
    Write-Host "ERROR: Firebase CLI not found." -ForegroundColor Red
    Write-Host "Install it with: npm install -g firebase-tools" -ForegroundColor Yellow
    exit 1
}

Write-Host "Choose your email provider:" -ForegroundColor Green
Write-Host "1) Gmail (recommended for testing)"
Write-Host "2) SendGrid"
Write-Host "3) AWS SES"
Write-Host "4) Custom SMTP"
Write-Host ""

$choice = Read-Host "Enter your choice (1-4)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "Gmail Setup Instructions:" -ForegroundColor Yellow
        Write-Host "1. Go to https://myaccount.google.com/apppasswords"
        Write-Host "2. Select 'Mail' and 'Windows/Mac/Linux'"
        Write-Host "3. Copy the 16-character password"
        Write-Host ""
        
        $gmail_addr = Read-Host "Enter your Gmail address"
        $app_password = Read-Host "Enter your Gmail App Password (16 chars)" -AsSecureString
        $app_password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($app_password))
        
        firebase functions:config:set smtp.user="$gmail_addr" smtp.pass="$app_password" smtp.host="smtp.gmail.com" smtp.port="587"
        Write-Host "SUCCESS: Gmail configured!" -ForegroundColor Green
    }
    "2" {
        Write-Host ""
        $sendgrid_key = Read-Host "Enter SendGrid API Key" -AsSecureString
        $sendgrid_key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($sendgrid_key))
        
        firebase functions:config:set smtp.user="apikey" smtp.pass="$sendgrid_key" smtp.host="smtp.sendgrid.net" smtp.port="587"
        Write-Host "SUCCESS: SendGrid configured!" -ForegroundColor Green
    }
    "3" {
        Write-Host ""
        $aws_host = Read-Host "Enter AWS SES SMTP endpoint (e.g. email-smtp.us-east-1.amazonaws.com)"
        $aws_user = Read-Host "Enter AWS SES SMTP username"
        $aws_pass = Read-Host "Enter AWS SES SMTP password" -AsSecureString
        $aws_pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($aws_pass))
        
        firebase functions:config:set smtp.user="$aws_user" smtp.pass="$aws_pass" smtp.host="$aws_host" smtp.port="587"
        Write-Host "SUCCESS: AWS SES configured!" -ForegroundColor Green
    }
    "4" {
        Write-Host ""
        $smtp_host = Read-Host "Enter SMTP host (e.g. mail.example.com)"
        $smtp_port = Read-Host "Enter SMTP port (default 587)"
        if ([string]::IsNullOrEmpty($smtp_port)) { $smtp_port = "587" }
        
        $smtp_user = Read-Host "Enter username"
        $smtp_pass = Read-Host "Enter password" -AsSecureString
        $smtp_pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($smtp_pass))
        
        firebase functions:config:set smtp.host="$smtp_host" smtp.port="$smtp_port" smtp.user="$smtp_user" smtp.pass="$smtp_pass"
        Write-Host "SUCCESS: Custom SMTP configured!" -ForegroundColor Green
    }
    default {
        Write-Host "ERROR: Invalid choice" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Verifying configuration..." -ForegroundColor Yellow
firebase functions:config:get | Select-String "smtp"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "1. cd functions"
Write-Host "2. npm install"
Write-Host "3. firebase deploy --only functions"
Write-Host "=========================================" -ForegroundColor Cyan
