# Staging and controlled production test-account matrix

Use a dedicated staging Firebase project whenever possible. If controlled
production testing is unavoidable, use synthetic names and records, separate
emails, short-lived passwords, and an owner-approved maintenance window.

Never use real patient accounts, real patient attachments, or shared personal
passwords for this test.

## Create accounts safely

Preferred path:

1. Ask the project owner to create four dedicated Firebase Authentication users
   in Firebase Console → **Build → Authentication → Users → Add user**.
2. Use addresses on a domain controlled by the team, such as
   `ai-dsuhis-qa-bhw@...`, `ai-dsuhis-qa-cho@...`,
   `ai-dsuhis-qa-doctor@...`, and `ai-dsuhis-qa-admin@...`.
3. Record each Firebase UID in the private test evidence; never commit
   passwords or reset links.
4. Let the approved CHO-admin account create/approve the corresponding managed
   profiles through the application workflow. This preserves the same server
   validation used in production.
5. Configure only the role's normal permissions. Do not add custom claims or
   extra permissions for convenience.
6. For the BHW account, assign a synthetic barangay scope such as
   `poblacion-10`. For Doctor, use `assigned_referrals`. CHO and Super Admin
   remain citywide.

If the application workflow is unavailable, a project owner may create the
`users/{uid}` profile from the existing profile schema after reviewing the
Firestore rules. Required fields are `uid`, `email`, `displayName`/`fullName`,
`role`, `approvalStatus: approved`, `accountStatus: active`, `status: Active`,
`isApproved: true`, `accessScope`, `organizationLevel`, and the BHW
`barangay`/`barangayCode`. Do not invent a role or permission key; use the
catalog in `lib/web/shared/services/rbac_policy.dart`.

## Role expectations

| Role | Allowed focus | Must be denied |
|---|---|---|
| BHW | Own barangay patients/records, create checkups/referrals, own profile | Other barangay data, CHO account management, RBAC, doctor-only referral actions |
| CHO | Citywide records, referral review/status, reports/data quality | CHO-admin account/RBAC operations unless explicitly granted |
| Doctor | Assigned referrals, clinical notes/status transitions, permitted read-only continuity data | Unassigned referral actions, account management, RBAC, BHW scope writes |
| CHO Super Admin | CHO-admin workflows, managed accounts, roles, branding, citywide governance | Nothing beyond the approved administrative policy; still no raw credential access |

## Test sequence for each identity

1. Login with valid credentials; verify the role landing route and profile.
2. Refresh the page and directly open a protected URL; verify the same server
   permission is enforced.
3. Execute one allowed read, create, update, search/filter, and pagination
   operation where the role supports it; verify persistence after refresh.
4. Attempt at least one denied URL, Firestore/API operation, and cross-scope
   record access. A hidden button is not evidence; record the backend denial.
5. Test logout and browser back navigation; private screens must not remain
   usable after logout.
6. Disable the user in Authentication and set its profile inactive; verify a
   new request is rejected after token refresh/revocation.
7. Test password reset with a mailbox the team controls and invalidate the
   temporary password afterward.
8. Test App Check in a real supported browser. Missing/invalid App Check must
   fail protected AI requests with `403`.

The account owner must sign the evidence for each allowed/denied row. Passing
the emulator suite does not replace this matrix.
