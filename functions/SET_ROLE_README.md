Setting CHO role (custom claim + Firestore users doc)
===============================================

This helper script sets a CHO role for an existing Firebase Auth user. It does two things:

- Sets a custom claim `role: 'CHO'` on the user (so clients can check token claims).
- Writes/merges `role: 'CHO'` into Firestore at `users/{uid}` (so clients can read Firestore user documents).

Prerequisites
-------------

- Node.js (same runtime as functions, Node 18 recommended).
- A Firebase service account JSON with project-level Admin permissions.
- The `firebase-admin` dependency is already included in `functions/package.json`.

Usage
-----

1. Ensure `GOOGLE_APPLICATION_CREDENTIALS` points to your service account JSON:

   Windows (PowerShell):

   ```powershell
   setx GOOGLE_APPLICATION_CREDENTIALS "C:\path\to\serviceAccount.json"
   ```

   macOS/Linux:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
   ```


2. From the `functions/` folder run one of these:

- Using an explicit key file (recommended local usage):

```bash
node set_cho_role.js cho@example.com --key ./service-account.json
```

- Or rely on the `GOOGLE_APPLICATION_CREDENTIALS` env var:

```powershell
#$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\serviceAccount.json"
node set_cho_role.js cho@example.com
```

Replace `cho@example.com` with the CHO user's email. The script will print the UID and confirmation messages.

Security note
-------------

Do not commit service account JSONs to version control. Keep them secure and run this script from a trusted machine or CI with restricted access.
