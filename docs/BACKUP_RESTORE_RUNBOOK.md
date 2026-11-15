# Backup and restore runbook

This runbook is intentionally non-destructive. Never restore over the live
Firestore database during testing.

## Firestore

1. In Google Cloud Console → **Firestore → Backups**, create daily scheduled
   backups for database `capstone-c98f9` in `asia-east1`. Choose retention that
   covers the two-month evaluation window and the project's recovery policy.
2. Confirm the backup schedule and latest backup with a project owner. If using
   CLI, a permitted operator can run:

   ```bash
   gcloud firestore backups schedules list \
     --project capstone-c98f9 --database capstone-c98f9
   gcloud firestore backups list \
     --project capstone-c98f9 --location asia-east1
   ```

3. Restore one known backup to a new isolated database ID, for example
   `restore-test-20260915`:

   ```bash
   gcloud firestore databases restore \
     --project capstone-c98f9 \
     --source-backup=projects/capstone-c98f9/locations/asia-east1/backups/BACKUP_ID \
     --destination-database=restore-test-20260915
   ```

4. Compare document counts and representative non-sensitive test records,
   confirm rules/indexes/config compatibility, and run read-only application
   checks against the restored database.
5. Delete the isolated restore database only after the owner signs the result.
   Never substitute the live database ID in the restore command.

The operator needs the least-privilege Backup/Restore IAM roles; a project
owner should grant and revoke those roles for the exercise.

## Firebase Storage

After the bucket is provisioned:

- Enable Cloud Storage soft delete and choose a retention period appropriate to
  the project policy.
- Consider object versioning only if the retention/cost trade-off is approved.
- Export a synthetic branding file and referral attachment, verify their size,
  content type, and storage path, then simulate recovery by restoring a prior
  object generation in an isolated test prefix/bucket.
- Confirm lifecycle/retention settings do not delete active files or retain
  clinical attachments longer than policy allows.

Do not copy real patient files to a developer laptop. Use synthetic fixtures.

## Configuration inventory

Back up/review the recoverable configuration separately: Firebase rules and
indexes, Functions source/lockfile, Vercel environment-variable names (never
values), Cloud Run deployment settings, Firebase App Check providers, model
checksum, and the clinical content/version approval record. Secrets remain in
the provider secret manager and are never placed in backups committed to Git.

## Evidence required before approval

Record schedule ID, retention, latest backup ID, restore database ID, restore
time, integrity checks, operator, IAM approval, and cleanup result. Without a
successful isolated restore, backup protection is not verified.
