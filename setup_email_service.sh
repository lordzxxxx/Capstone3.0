#!/bin/bash
# setup_email_service.sh
# Configure Firebase Functions for email service

echo "=========================================="
echo "DSUHIS Password Reset Email Configuration"
echo "=========================================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install it first:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

echo "Choose your email provider:"
echo "1) Gmail (recommended for testing)"
echo "2) SendGrid"
echo "3) AWS SES"
echo "4) Custom SMTP"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        echo ""
        echo "Gmail Setup Instructions:"
        echo "1. Go to https://myaccount.google.com/apppasswords"
        echo "2. Select 'Mail' and 'Windows/Mac/Linux'"
        echo "3. Copy the 16-character password"
        echo ""
        read -p "Enter your Gmail address: " gmail_addr
        read -sp "Enter your Gmail App Password (16 chars): " app_password
        echo ""
        
        firebase functions:config:set smtp.user="$gmail_addr" smtp.pass="$app_password" smtp.host="smtp.gmail.com" smtp.port="587"
        echo "✅ Gmail configured!"
        ;;
    2)
        echo ""
        read -p "Enter SendGrid API Key: " sendgrid_key
        firebase functions:config:set smtp.user="apikey" smtp.pass="$sendgrid_key" smtp.host="smtp.sendgrid.net" smtp.port="587"
        echo "✅ SendGrid configured!"
        ;;
    3)
        echo ""
        read -p "Enter AWS SES SMTP endpoint (e.g. email-smtp.us-east-1.amazonaws.com): " aws_host
        read -p "Enter AWS SES SMTP username: " aws_user
        read -sp "Enter AWS SES SMTP password: " aws_pass
        echo ""
        firebase functions:config:set smtp.user="$aws_user" smtp.pass="$aws_pass" smtp.host="$aws_host" smtp.port="587"
        echo "✅ AWS SES configured!"
        ;;
    4)
        echo ""
        read -p "Enter SMTP host (e.g. mail.example.com): " smtp_host
        read -p "Enter SMTP port (default 587): " smtp_port
        smtp_port=${smtp_port:-587}
        read -p "Enter username: " smtp_user
        read -sp "Enter password: " smtp_pass
        echo ""
        firebase functions:config:set smtp.host="$smtp_host" smtp.port="$smtp_port" smtp.user="$smtp_user" smtp.pass="$smtp_pass"
        echo "✅ Custom SMTP configured!"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "Verifying configuration..."
firebase functions:config:get | grep smtp

echo ""
echo "=========================================="
echo "Next steps:"
echo "1. cd functions"
echo "2. npm install"
echo "3. firebase deploy --only functions"
echo "=========================================="
