"""Prepare a recoverable reset of clinical data and move one BHW scope.

This is intentionally dry-run-only unless both explicit safety switches are
provided. It preserves accounts, roles, reference/guidance content, and
barangay workspace documents while deleting clinical collection groups from
both root and `barangays/{code}/...` paths.

Before `--apply`, create and verify a Firestore backup or clone. The command
refuses to run without a recorded recovery reference so an operator cannot
accidentally turn a reset into irreversible data loss.
"""

from __future__ import annotations

import argparse
import os
from collections import Counter
from dataclasses import dataclass
from typing import Iterable

import firebase_admin
from firebase_admin import auth, db, firestore

PROJECT_ID = "capstone-c98f9"
DATABASE_ID = "capstone-c98f9"
TARGET_EMAIL = "frisky4@gmail.com"
TARGET_BARANGAY = "Barangay 03"
TARGET_BARANGAY_CODE = "POBLACION-03"
TARGET_DISTRICT = "Poblacion District"

# Collection-group queries include root records and each BHW barangay mirror.
# Keep identity and reference collections out of this list.
CLINICAL_COLLECTION_GROUPS = (
    "patient_records",
    "checkup_records",
    "prenatal_records",
    "immunization_records",
    "morbidity_records",
    "mortality_records",
    "referrals",
    "doctor_notes",
)


@dataclass(frozen=True)
class ResetPlan:
    bhw_uid: str
    collection_counts: Counter[str]

    @property
    def clinical_document_count(self) -> int:
        return sum(self.collection_counts.values())


def client() -> firestore.Client:
    """Create an Admin client only from protected application credentials."""
    if not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        raise RuntimeError("GOOGLE_APPLICATION_CREDENTIALS must reference a protected service-account file.")
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(options={"projectId": PROJECT_ID})
    return firestore.Client(project=PROJECT_ID, database=DATABASE_ID)


def clinical_documents(database: firestore.Client) -> Iterable[firestore.DocumentReference]:
    for collection_id in CLINICAL_COLLECTION_GROUPS:
        yield from (snapshot.reference for snapshot in database.collection_group(collection_id).stream())


def build_plan(database: firestore.Client) -> ResetPlan:
    user = auth.get_user_by_email(TARGET_EMAIL)
    profile = database.collection("users").document(user.uid).get()
    if not profile.exists:
        raise RuntimeError(f"No Firestore user profile exists for {TARGET_EMAIL}.")
    role = str(profile.to_dict().get("role", "")).upper()
    if role != "BHW":
        raise RuntimeError(f"{TARGET_EMAIL} is {role or 'unassigned'}, not a BHW account; refusing scope migration.")
    counts = Counter(reference.parent.id for reference in clinical_documents(database))
    return ResetPlan(user.uid, counts)


def apply_plan(database: firestore.Client, plan: ResetPlan, recovery_reference: str) -> None:
    # Re-query immediately before deletes so a stale dry-run cannot hide added data.
    documents = list(clinical_documents(database))
    batch = database.batch()
    pending = 0
    for reference in documents:
        batch.delete(reference)
        pending += 1
        if pending == 400:
            batch.commit()
            batch = database.batch()
            pending = 0
    if pending:
        batch.commit()

    old_workspace_user = database.document(f"barangays/MAGSAYSAY/users/{plan.bhw_uid}")
    new_workspace_user = database.document(f"barangays/{TARGET_BARANGAY_CODE}/users/{plan.bhw_uid}")
    profile_patch = {
        "barangay": TARGET_BARANGAY,
        "barangayCode": TARGET_BARANGAY_CODE,
        "barangayDistrict": TARGET_DISTRICT,
        "barangayVerified": True,
        "accessScope": "barangay",
        "organizationLevel": "barangay",
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "lastClinicalResetRecoveryReference": recovery_reference,
    }
    migration = database.batch()
    migration.set(database.collection("users").document(plan.bhw_uid), profile_patch, merge=True)
    request_ref = database.collection("bhw_registration_requests").document(plan.bhw_uid)
    migration.set(request_ref, {
        **profile_patch,
        "assignedBarangay": TARGET_BARANGAY,
        "assignedBarangayCode": TARGET_BARANGAY_CODE,
    }, merge=True)
    migration.set(new_workspace_user, {"uid": plan.bhw_uid, **profile_patch}, merge=True)
    migration.delete(old_workspace_user)
    migration.set(database.collection("audit_logs").document(), {
        "action": "clinical_data_reset_and_bhw_scope_migration",
        "targetUid": plan.bhw_uid,
        "targetEmail": TARGET_EMAIL,
        "recoveryReference": recovery_reference,
        "deletedClinicalDocuments": len(documents),
        "createdAt": firestore.SERVER_TIMESTAMP,
    })
    migration.commit()
    # The BHW application reads this mirror during account bootstrap. Update it
    # in the same operation window so a fresh sign-in cannot restore Magsaysay.
    db.reference(f"users/{plan.bhw_uid}").update({
        "barangay": TARGET_BARANGAY,
        "barangayCode": TARGET_BARANGAY_CODE,
        "barangayDistrict": TARGET_DISTRICT,
        "updatedAt": {".sv": "timestamp"},
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Perform the guarded deletion and migration.")
    parser.add_argument("--recovery-reference", help="Verified backup or clone resource name.")
    parser.add_argument("--confirm", help="Must equal RESET_CLINICAL_DATA_AND_MOVE_FRISKY4.")
    args = parser.parse_args()
    database = client()
    plan = build_plan(database)
    print(f"Target BHW: {TARGET_EMAIL} ({plan.bhw_uid})")
    print(f"New scope: {TARGET_BARANGAY} / {TARGET_BARANGAY_CODE}")
    print(f"Clinical documents selected: {plan.clinical_document_count}")
    for collection_id in CLINICAL_COLLECTION_GROUPS:
        print(f"  {collection_id}: {plan.collection_counts[collection_id]}")
    if not args.apply:
        print("Dry run only. No data or profile has been changed.")
        return
    if not args.recovery_reference:
        raise SystemExit("--recovery-reference is required before any deletion.")
    if args.confirm != "RESET_CLINICAL_DATA_AND_MOVE_FRISKY4":
        raise SystemExit("Confirmation text did not match; no data was changed.")
    apply_plan(database, plan, args.recovery_reference)
    print("Clinical reset and BHW scope migration completed. Re-authenticate the BHW account before use.")


if __name__ == "__main__":
    main()
