"""Seed a small, deterministic fictional BHW -> CHO -> doctor demo workflow.

The command is a dry run unless ``--apply`` is supplied.  It only writes
documents marked ``isDemoData`` and uses stable IDs with merge writes, so it is
safe to rerun and never deletes production records.  Doctor UIDs are supplied
explicitly because referral visibility is tied to the authenticated doctor's
UID in Firestore rules.

Use this only in a development/evaluation Firebase project, for example:

    python backend/firebase/seed_care_workflow_demo.py \
      --barangay-code MAGSAYSAY \
      --doctor-a-uid <firebase-uid-a> \
      --doctor-b-uid <firebase-uid-b> \
      --apply
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

FIREBASE_DIR = Path(__file__).resolve().parent
APP_DIR = FIREBASE_DIR.parent / "app"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from firebase_service import get_firestore_client  # noqa: E402
from seed_bhw_analytics_demo import (  # noqa: E402
    BhwScope,
    commit_in_chunks,
    discover_bhw_scopes,
    month_date,
    normalize_code,
)

SEED_VERSION = "care-workflow-demo-v1"


def _base(scope: BhwScope, event_date: datetime) -> dict[str, Any]:
    return {
        "barangay": scope.barangay_name,
        "barangayCode": scope.barangay_code,
        "barangayDistrict": scope.barangay_district,
        "isDemoData": True,
        "demoDataset": SEED_VERSION,
        "seedVersion": SEED_VERSION,
        "createdByUid": scope.uid,
        "updatedAt": event_date,
    }


def build_workflow_records(
    scope: BhwScope,
    *,
    doctor_a_uid: str,
    doctor_b_uid: str,
    anchor: datetime | None = None,
) -> dict[str, list[tuple[str, dict[str, Any]]]]:
    """Build notes, schedules, and referrals for a fictional care handoff."""
    if not doctor_a_uid.strip() or not doctor_b_uid.strip():
        raise ValueError("doctor UIDs must be non-empty")

    now = anchor or datetime.now(timezone.utc)
    patient_id = f"DEMO-{scope.barangay_code}-001"
    patient_name = "Demo Analytics Patient 01"
    first_checkup = month_date(now, 1, day=8)
    second_checkup = month_date(now, 0, day=8)
    appointment = now.replace(minute=0, second=0, microsecond=0) + timedelta(days=1)
    conflict = appointment + timedelta(minutes=30)

    doctors = [
        (
            "care-workflow-demo-doctor-a",
            {
                "uid": doctor_a_uid,
                "userUid": doctor_a_uid,
                "displayName": "Dr. Demo Alpha",
                "name": "Dr. Demo Alpha",
                "email": "demo.doctor.alpha@example.invalid",
                "role": "DOCTOR",
                "status": "available",
                "availability": "available",
                "availableDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
                "workingHours": {
                    "monday": {"start": "08:00", "end": "17:00"},
                    "tuesday": {"start": "08:00", "end": "17:00"},
                    "wednesday": {"start": "08:00", "end": "17:00"},
                    "thursday": {"start": "08:00", "end": "17:00"},
                    "friday": {"start": "08:00", "end": "17:00"},
                },
                "isDemoData": True,
                "demoDataset": SEED_VERSION,
                "seedVersion": SEED_VERSION,
                "barangayCode": scope.barangay_code,
                "updatedAt": now,
            },
        ),
        (
            "care-workflow-demo-doctor-b",
            {
                "uid": doctor_b_uid,
                "userUid": doctor_b_uid,
                "displayName": "Dr. Demo Beta",
                "name": "Dr. Demo Beta",
                "email": "demo.doctor.beta@example.invalid",
                "role": "DOCTOR",
                "status": "available",
                "availability": "available",
                "availableDays": ["monday", "wednesday", "friday"],
                "workingHours": {
                    "monday": {"start": "09:00", "end": "15:00"},
                    "wednesday": {"start": "09:00", "end": "15:00"},
                    "friday": {"start": "09:00", "end": "15:00"},
                },
                "isDemoData": True,
                "demoDataset": SEED_VERSION,
                "seedVersion": SEED_VERSION,
                "barangayCode": scope.barangay_code,
                "updatedAt": now,
            },
        ),
    ]

    notes = [
        (
            "care-workflow-demo-note-a",
            {
                **_base(scope, first_checkup),
                "patientId": patient_id,
                "patientName": patient_name,
                "checkupId": f"DEMO-checkup-{scope.barangay_code}-001",
                "authorUid": doctor_a_uid,
                "authorName": "Dr. Demo Alpha",
                "authorRole": "DOCTOR",
                "note": "Demo note: monitor blood pressure and repeat vitals at the next visit.",
                "createdAt": first_checkup,
            },
        ),
        (
            "care-workflow-demo-note-b",
            {
                **_base(scope, second_checkup),
                "patientId": patient_id,
                "patientName": patient_name,
                "checkupId": f"DEMO-checkup-{scope.barangay_code}-002",
                "authorUid": doctor_b_uid,
                "authorName": "Dr. Demo Beta",
                "authorRole": "DOCTOR",
                "note": "Demo note: previous findings reviewed; continue follow-up and escalate if warning signs appear.",
                "createdAt": second_checkup,
            },
        ),
    ]

    referrals = [
        (
            "care-workflow-demo-referral-pending",
            {
                **_base(scope, appointment),
                "patientId": patient_id,
                "patientRecordId": patient_id,
                "linkedPatientId": patient_id,
                "patientName": patient_name,
                "referralDateTime": appointment,
                "appointmentDateTime": appointment,
                "durationMinutes": 60,
                "referralType": "Medical consultation",
                "referralReason": "Demo continuity-of-care review",
                "status": "assigned",
                "submissionStatus": "submitted",
                "assignedDoctorUid": doctor_a_uid,
                "assignedDoctorName": "Dr. Demo Alpha",
                "assignedDoctorEmail": "demo.doctor.alpha@example.invalid",
            },
        ),
        (
            "care-workflow-demo-referral-conflict",
            {
                **_base(scope, conflict),
                "patientId": f"DEMO-{scope.barangay_code}-002",
                "patientRecordId": f"DEMO-{scope.barangay_code}-002",
                "linkedPatientId": f"DEMO-{scope.barangay_code}-002",
                "patientName": "Demo Analytics Patient 02",
                "referralDateTime": conflict,
                "appointmentDateTime": conflict,
                "durationMinutes": 60,
                "referralType": "Medical consultation",
                "referralReason": "Demo overlapping appointment",
                "status": "assigned",
                "submissionStatus": "submitted",
                "assignedDoctorUid": doctor_a_uid,
                "assignedDoctorName": "Dr. Demo Alpha",
                "assignedDoctorEmail": "demo.doctor.alpha@example.invalid",
            },
        ),
        (
            "care-workflow-demo-referral-completed",
            {
                **_base(scope, first_checkup),
                "patientId": patient_id,
                "patientRecordId": patient_id,
                "linkedPatientId": patient_id,
                "patientName": patient_name,
                "referralDateTime": first_checkup,
                "appointmentDateTime": first_checkup,
                "durationMinutes": 60,
                "referralType": "Medical consultation",
                "referralReason": "Demo completed referral",
                "status": "completed",
                "submissionStatus": "completed",
                "assignedDoctorUid": doctor_b_uid,
                "assignedDoctorName": "Dr. Demo Beta",
                "assignedDoctorEmail": "demo.doctor.beta@example.invalid",
            },
        ),
    ]

    return {"doctor_registry": doctors, "doctor_notes": notes, "referrals": referrals}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write to Firestore")
    parser.add_argument("--barangay-code", required=True)
    parser.add_argument("--doctor-a-uid", required=True)
    parser.add_argument("--doctor-b-uid", required=True)
    args = parser.parse_args()

    code = normalize_code(args.barangay_code)
    db = get_firestore_client()
    scopes = discover_bhw_scopes(db, {code})
    if not scopes:
        raise SystemExit(f"No registered BHW scope was found for {code}.")

    writes: list[tuple[Any, dict[str, Any]]] = []
    total = 0
    for scope in scopes:
        records = build_workflow_records(
            scope,
            doctor_a_uid=args.doctor_a_uid,
            doctor_b_uid=args.doctor_b_uid,
        )
        summary = ", ".join(f"{key}={len(value)}" for key, value in records.items())
        print(f"{scope.barangay_code}: {summary}")
        total += sum(len(value) for value in records.values())
        for document_id, payload in records["doctor_registry"]:
            writes.append((db.collection("doctor_registry").document(document_id), payload))
        for document_id, payload in records["doctor_notes"]:
            writes.append((db.collection("doctor_notes").document(document_id), payload))
        for document_id, payload in records["referrals"]:
            writes.append((db.collection("referrals").document(document_id), payload))

    if not args.apply:
        print(f"Dry run: validated {total} fictional workflow documents. Use --apply to write them.")
        return 0

    committed = commit_in_chunks(db, writes)
    print(f"Applied {committed} fictional workflow documents. No documents were deleted.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
