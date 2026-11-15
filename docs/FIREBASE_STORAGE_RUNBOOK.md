# Firebase Storage provisioning and verification

Project: `capstone-c98f9`  
Recommended location: `asia-east1`, matching the existing Firestore database.

## Provision the bucket

1. Open the [Firebase Console](https://console.firebase.google.com/) and select
   `capstone-c98f9`.
2. Open **Build → Storage** (or **Databases & Storage → Storage**) and choose
   **Get started**.
3. Select the production mode option so rules are required, not an open test
   mode.
4. Select `asia-east1` if it is offered and confirm the bucket. The expected
   new default bucket is `capstone-c98f9.firebasestorage.app`.
5. Confirm that the Web Firebase configuration still uses that exact bucket.
   `lib/main.dart` currently declares it; do not change it to a guessed value.
6. Confirm the project is on the Blaze plan. Storage/Cloud Run/backup usage
   must be budgeted and monitored.

Do not paste service-account credentials into the console or repository.

## Deploy the reviewed rules

From the repository root, after the bucket exists:

```bash
npx firebase use capstone-c98f9
npx firebase deploy --only storage
```

The rules enforce:

- Public read for barangay branding because registration pages display it.
- CHO-admin-only immutable branding uploads, max 5 MB, PNG/JPEG/WebP.
- Owner-only referral uploads, max 10 MB, PDF/JPEG/PNG.
- Owner/CHO-only referral reads and deletes.
- No fallback path access.

The direct doctor read that existed previously was removed because a doctor
role alone does not prove assignment to the referral. The project uses the
named Firestore database `capstone-c98f9`; Storage rule cross-document access
is not a safe substitute for this assignment check. Doctor downloads now use
the `getReferralAttachmentDownloadUrl` callable, which:

1. verifies Firebase Auth and enforced App Check;
2. reads `referrals/{referralId}` from the named database;
3. confirms `assignedDoctorUid == request.auth.uid` (or the CHO permission);
4. validates the recorded `storagePath` belongs to that referral;
5. checks that the object exists and returns a ten-minute signed read URL
   without logging the object or clinical payload.

## Application checks already implemented

The web client validates the same policy before upload and shows a safe error.
Storage Rules remain the authority. Referral removal deletes the object and
then removes its metadata from the pending form. Branding assets remain
versioned/immutable; cleanup of an old branding object must be an explicit CHO
admin workflow after the new Firestore profile points to the replacement.

## Required test matrix

Use synthetic staging accounts and files only:

| Test | Expected result |
|---|---|
| CHO Admin uploads 1–5 MB PNG/JPEG/WebP branding | Allowed |
| Normal CHO uploads branding | Denied |
| Anonymous branding read | Allowed only for the public branding path |
| BHW owner uploads PDF/JPEG/PNG referral file ≤10 MB | Allowed |
| Owner uploads >10 MB, GIF, or mismatched extension/MIME | Denied client-side and by rules |
| Another BHW reads/deletes owner file | Denied |
| Doctor directly reads/deletes owner file | Denied by Storage Rules; assigned reads use the server-mediated callable |
| Owner deletes an uploaded referral file | Allowed; verify object is gone |
| Network failure during upload | Safe error; no false Firestore success |
| Replace branding or attachment | New object only; verify old-object cleanup policy |

Capture the bucket name, location, rule deployment ID, test account IDs (not
passwords), object sizes/types, and results in the release evidence.
