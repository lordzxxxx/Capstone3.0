# Fictional care-workflow demo data

`backend/firebase/seed_care_workflow_demo.py` provides a dry-run-by-default
fixture for evaluation environments. It creates only explicitly marked
`isDemoData` documents and uses stable IDs with merge writes:

- two published doctor registry schedules;
- two append-only notes for the same fictional patient, authored by two
  different doctors;
- one active assigned referral, one overlapping assigned referral to exercise
  conflict detection, and one completed referral.

The script requires the real Firebase UIDs of the two demo doctor accounts so
Firestore referral rules can be exercised correctly:

```sh
python backend/firebase/seed_care_workflow_demo.py \
  --barangay-code MAGSAYSAY \
  --doctor-a-uid <firebase-uid-a> \
  --doctor-b-uid <firebase-uid-b>
```

Add `--apply` only when connected to the intended development/evaluation
Firebase project. The script never deletes documents. It is intentionally not
run automatically in production and does not create Firebase Auth accounts.
