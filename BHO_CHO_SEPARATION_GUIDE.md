# BHO & CHO Account Separation Guide

## Overview
The BHO (Block Health Officer) and CHO (Community Health Officer) accounts have been separated into distinct systems with separate login pages, account creation methods, and role management.

## Key Changes

### 1. **Separate Login Pages**

#### BHO Login Page
- **File:** `lib/web/bho_login.dart`
- **Class:** `BHOLogin`
- **Features:** Customized for Block Health Officer portal
- **Subtitle:** "Block-Level Analytics" and "Team Management"

#### CHO Login Page  
- **File:** `lib/web/features/auth/login.dart`
- **Class:** `Login`
- **Features:** Customized for Community Health Officer portal
- **Subtitle:** "Advanced Analytics" and "Cloud Sync"

### 2. **Landing Page Routing**
- **File:** `lib/web/features/auth/landing.dart`
- "Login as BHO" button → `BHOLogin()`
- "Login as CHO" button → `Login()`

### 3. **Account Creation Methods**

#### For Admins Creating BHO Accounts
Create BHO accounts through the admin dashboard:
```dart
await _createBHOAccount('Officer Name', 'bho@example.com');
```

#### For Admins Creating CHO Accounts
Create CHO accounts through the admin dashboard:
```dart
await _createCHOAccount('Officer Name', 'cho@example.com');
```

**Location:** `lib/web/roles/bhw/dashboard/homepage.dart` (HomePage widget)

### 4. **Role Management Scripts**

#### Set BHO Role
Script: `functions/set_bho_role.js`

```bash
# Set BHO role for existing user
node set_bho_role.js bho@example.com --key ./service-account.json

# Or using environment variable
setx GOOGLE_APPLICATION_CREDENTIALS "C:\path\to\serviceAccount.json"
node set_bho_role.js bho@example.com
```

#### Set CHO Role
Script: `functions/set_cho_role.js`

```bash
# Set CHO role for existing user
node set_cho_role.js cho@example.com --key ./service-account.json
```

## Database Structure

Both roles are stored in Firestore:

```
users/{uid}
├── email: string
├── name: string
├── role: 'BHO' | 'CHO'
├── createdBy: uid
├── createdAt: timestamp
├── tempPassword: string
└── status: 'active'
```

## User Flow

### BHO User Flow
1. Admin creates BHO account via `_createBHOAccount()`
2. BHO receives email credentials
3. BHO visits landing page and clicks "Login as BHO"
4. BHO is directed to `BHOLogin` page
5. BHO logs in with temporary password
6. BHO must change password on first login
7. BHO accesses Block Health Officer dashboard

### CHO User Flow
1. Admin creates CHO account via `_createCHOAccount()`
2. CHO receives email credentials
3. CHO visits landing page and clicks "Login as CHO"
4. CHO is directed to `Login` page
5. CHO logs in with temporary password
6. CHO must change password on first login
7. CHO accesses Community Health Officer dashboard

## Role-Based Features

### BHO Features (Block Level)
- Block-level health analytics
- Team management for CHOs
- District-wide health monitoring
- Aggregate data views
- Report generation

### CHO Features (Community Level)
- Community health monitoring
- Patient management
- Local health data entry
- Community reports
- Direct patient interactions

## Firestore Custom Claims

Both BHO and CHO have custom claims set via Firebase Admin SDK:

```javascript
// BHO Custom Claims
{ role: 'BHO' }

// CHO Custom Claims
{ role: 'CHO' }
```

These can be verified client-side by checking user's `idTokenResult.claims.role`

## Security Considerations

1. **Temporary Passwords:** All new accounts receive temporary passwords
2. **Email Verification:** Not enforced at account creation (can be added)
3. **Role Assignment:** Must be done via admin scripts after account creation
4. **Account Segregation:** BHO and CHO have separate login pages in UI
5. **Firestore Rules:** Should enforce role-based access control (recommend updating security rules)

## Future Enhancements

1. Add role-specific dashboards with different layouts
2. Implement role-based Firestore security rules
3. Add audit logging for account creation per role
4. Create role-specific permission matrices
5. Implement role hierarchy if needed (BHO > CHO)
6. Add email verification before account activation
7. Create separate password reset flows per role

## Troubleshooting

### BHO Account Creation Falls
- Check Firebase Auth quota
- Verify Firestore write permissions
- Ensure email format is valid
- Check browser console for errors

### Role Not Reflecting
- Run appropriate set_bho_role.js or set_cho_role.js
- Verify user exists in Firebase Auth
- Check Firestore has role field set
- Clear browser cache and login again

### Login Page Shows Wrong Role Text
- Verify correct page import (BHOLogin vs Login)
- Check landing.dart routing
- Clear Flutter build cache: `flutter clean && flutter pub get`
