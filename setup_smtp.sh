#!/bin/bash

# SMTP Configuration Script for Firebase Functions
# This script helps you set up SMTP configuration for the invitation system

echo "=========================================="
echo "SMTP Configuration Setup"
echo "=========================================="
echo ""
echo "Choose your email provider:"
echo "1) Gmail (Recommended for testing)"
echo "2) Outlook / Office 365"
echo "3) Custom SMTP Server"
echo ""

read -p "Enter your choice (1-3): " choice

case $choice in
  1)
    echo ""
    echo "Gmail Setup:"
    echo "1. Go to https://myaccount.google.com/security"
    echo "2. Enable 2-Step Verification"
    echo "3. Go to App passwords → Select 'Mail' and 'Windows Computer'"
    echo "4. Copy the 16-character password generated"
    echo ""
    read -p "Enter your Gmail address: " gmail
    read -sp "Enter your App Password (16 chars): " app_pass
    echo ""
    
    firebase functions:config:set smtp.host="smtp.gmail.com"
    firebase functions:config:set smtp.port="587"
    firebase functions:config:set smtp.secure="false"
    firebase functions:config:set smtp.user="$gmail"
    firebase functions:config:set smtp.password="$app_pass"
    firebase functions:config:set smtp.fromEmail="$gmail"
    echo "✅ Gmail SMTP configured!"
    ;;
  2)
    echo ""
    echo "Outlook / Office 365 Setup:"
    read -p "Enter your email address: " email
    read -sp "Enter your password: " password
    echo ""
    
    firebase functions:config:set smtp.host="smtp.office365.com"
    firebase functions:config:set smtp.port="587"
    firebase functions:config:set smtp.secure="false"
    firebase functions:config:set smtp.user="$email"
    firebase functions:config:set smtp.password="$password"
    firebase functions:config:set smtp.fromEmail="$email"
    echo "✅ Outlook SMTP configured!"
    ;;
  3)
    echo ""
    echo "Custom SMTP Server Setup:"
    read -p "Enter SMTP server hostname: " host
    read -p "Enter SMTP port (usually 587): " port
    read -p "Enter username: " user
    read -sp "Enter password: " pass
    echo ""
    read -p "Enable TLS/SSL? (true/false): " secure
    read -p "Enter From email address: " fromEmail
    echo ""
    
    firebase functions:config:set smtp.host="$host"
    firebase functions:config:set smtp.port="$port"
    firebase functions:config:set smtp.secure="$secure"
    firebase functions:config:set smtp.user="$user"
    firebase functions:config:set smtp.password="$pass"
    firebase functions:config:set smtp.fromEmail="$fromEmail"
    echo "✅ Custom SMTP configured!"
    ;;
  *)
    echo "Invalid choice!"
    exit 1
    ;;
esac

echo ""
echo "Verifying configuration..."
firebase functions:config:get

echo ""
echo "Deploying functions..."
firebase deploy --only functions

echo ""
echo "✅ Setup complete! Invitations will now be sent via SMTP."
echo ""
echo "Next steps:"
echo "1. Test by sending an invitation from the admin panel"
echo "2. Check inbox (and spam folder)"
echo "3. View logs if there are issues: firebase functions:log"
