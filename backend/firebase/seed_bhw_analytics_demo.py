"""Seed deterministic, barangay-scoped demo records for BHW Analytics.

The command is a dry run unless ``--apply`` is provided. Applied documents use
stable IDs and merge writes, so rerunning the command does not duplicate data.
All generated records are explicitly marked as demo data.
"""

from __future__ import annotations

import argparse
import calendar
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

FIREBASE_DIR = Path(__file__).resolve().parent
APP_DIR = FIREBASE_DIR.parent / "app"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

from firebase_service import get_firestore_client  # noqa: E402

SEED_VERSION = "bhw-analytics-demo-v1"
COLLECTIONS = (
    "patient_records",
    "checkup_records",
    "immunization_records",
    "morbidity_records",
    "mortality_records",
    "referrals",
)


@dataclass(frozen=True)
class BhwScope:
    uid: str
    barangay_code: str
    barangay_name: str
    barangay_district: str = ""


def normalize_code(value: str) -> str:
    return value.strip().upper()


def month_date(anchor: datetime, months_ago: int, day: int = 10) -> datetime:
    """Return a safe UTC date in the requested prior calendar month."""
    absolute_month = (anchor.year * 12 + anchor.month - 1) - months_ago
    year, zero_based_month = divmod(absolute_month, 12)
    month = zero_based_month + 1
    last_day = calendar.monthrange(year, month)[1]
    safe_day = min(day, last_day)
    if months_ago == 0:
        safe_day = min(safe_day, anchor.day)
    return datetime(year, month, safe_day, 9, 0, tzinfo=timezone.utc)


def _base(scope: BhwScope, record_date: datetime) -> dict[str, Any]:
    return {
        "barangay": scope.barangay_name,
        "barangayCode": scope.barangay_code,
        "barangayDistrict": scope.barangay_district,
        "isDemoData": True,
        "demoDataset": SEED_VERSION,
        "seedVersion": SEED_VERSION,
        "createdByUid": scope.uid,
        "updatedAt": record_date,
    }


def build_scope_records(
    scope: BhwScope,
    *,
    anchor: datetime | None = None,
    months: int = 10,
    patient_count: int = 15,
) -> dict[str, list[tuple[str, dict[str, Any]]]]:
    """Build records covering every BHW Analytics graph and insight panel."""
    if months < 6:
        raise ValueError("months must be at least 6 to fill the six-month charts")
    if patient_count < 10:
        raise ValueError("patient_count must be at least 10")

    now = anchor or datetime.now(timezone.utc)
    output: dict[str, list[tuple[str, dict[str, Any]]]] = {
        collection: [] for collection in COLLECTIONS
    }

    ages = (8, 13, 18, 23, 29, 34, 39, 47, 55, 63, 68, 74, 42, 31, 16)
    genders = ("Female", "Male", "Female", "Male")
    bmi_values = (17.8, 21.6, 24.2, 27.4, 31.1)
    for index in range(patient_count):
        patient_number = index + 1
        created = month_date(now, index % months, day=4 + (index % 10))
        age = ages[index % len(ages)]
        gender = genders[index % len(genders)]
        bmi = bmi_values[index % len(bmi_values)]
        height_cm = 145 + (index % 8) * 4
        weight_kg = round(bmi * ((height_cm / 100) ** 2), 1)
        patient_id = f"DEMO-{scope.barangay_code}-{patient_number:03d}"
        payload = {
            **_base(scope, created),
            "patientId": patient_id,
            "firstName": "Demo",
            "middleName": "Analytics",
            "surname": f"Patient {patient_number:02d}",
            "patientName": f"Demo Analytics Patient {patient_number:02d}",
            "age": age,
            "gender": gender,
            "sex": gender,
            "height": height_cm,
            "weight": weight_kg,
            "bmi": bmi,
            "status": "Active",
            "registrationDate": created,
            "createdAt": created,
        }
        output["patient_records"].append(
            (f"{SEED_VERSION}-patient-{patient_number:03d}", payload)
        )

    communicable_cases = (
        ("Dengue fever", "Communicable", "Moderate"),
        ("Influenza", "Communicable", "Mild"),
        ("Pneumonia", "Communicable", "Moderate"),
        ("Tuberculosis", "Communicable", "High"),
        ("Acute diarrhea", "Communicable", "Mild"),
    )
    chronic_cases = (
        ("Hypertension", "Non-Communicable", "Moderate"),
        ("Type 2 diabetes", "Non-Communicable", "High"),
        ("Asthma", "Non-Communicable", "Mild"),
        ("Arthritis", "Non-Communicable", "Moderate"),
        ("Chronic kidney disease", "Non-Communicable", "High"),
    )
    all_cases = communicable_cases + chronic_cases
    for month_index in range(months):
        for visit_index in range(2):
            sequence = month_index * 2 + visit_index
            patient_number = (sequence % patient_count) + 1
            visit_date = month_date(now, month_index, day=8 + visit_index * 7)
            disease, classification, severity = all_cases[sequence % len(all_cases)]
            systolic = 108 + ((sequence * 7) % 46)
            diastolic = 68 + ((sequence * 5) % 28)
            bmi = bmi_values[patient_number % len(bmi_values)]
            patient_id = f"DEMO-{scope.barangay_code}-{patient_number:03d}"
            payload = {
                **_base(scope, visit_date),
                "patientId": patient_id,
                "linkedPatientId": patient_id,
                "patientName": f"Demo Analytics Patient {patient_number:02d}",
                "age": ages[(patient_number - 1) % len(ages)],
                "gender": genders[(patient_number - 1) % len(genders)],
                "datetime": visit_date,
                "date": visit_date,
                "disease": disease,
                "diagnosis": disease,
                "chiefComplaint": disease,
                "symptoms": disease,
                "diseaseType": classification,
                "caseClassification": classification,
                "severity": severity,
                "status": "Follow-up" if sequence % 3 == 0 else "Completed",
                "bloodPressure": f"{systolic}/{diastolic}",
                "bpSystolic": systolic,
                "bpDiastolic": diastolic,
                "bmi": bmi,
                "details": f"BMI: {bmi}; Blood pressure: {systolic}/{diastolic}",
                "createdAt": visit_date,
            }
            output["checkup_records"].append(
                (f"{SEED_VERSION}-checkup-{sequence + 1:03d}", payload)
            )

    vaccines = ("BCG", "Pentavalent", "OPV", "MMR", "Influenza", "Hepatitis B")
    for month_index in range(months):
        patient_number = ((month_index * 3) % patient_count) + 1
        administration_date = month_date(now, month_index, day=12)
        payload = {
            **_base(scope, administration_date),
            "patientId": f"DEMO-{scope.barangay_code}-{patient_number:03d}",
            "patientName": f"Demo Analytics Patient {patient_number:02d}",
            "vaccine": vaccines[month_index % len(vaccines)],
            "immunizationType": vaccines[month_index % len(vaccines)],
            "doseNumber": (month_index % 3) + 1,
            "administrationDate": administration_date,
            "status": "Completed" if month_index % 4 else "Scheduled",
            "createdAt": administration_date,
        }
        output["immunization_records"].append(
            (f"{SEED_VERSION}-immunization-{month_index + 1:03d}", payload)
        )

    for month_index in range(months):
        for case_index in range(2):
            sequence = month_index * 2 + case_index
            patient_number = ((sequence * 2) % patient_count) + 1
            report_date = month_date(now, month_index, day=6 + case_index * 11)
            disease, classification, severity = all_cases[
                (sequence + 2) % len(all_cases)
            ]
            payload = {
                **_base(scope, report_date),
                "patientId": f"DEMO-{scope.barangay_code}-{patient_number:03d}",
                "linkedPatientId": f"DEMO-{scope.barangay_code}-{patient_number:03d}",
                "patientName": f"Demo Analytics Patient {patient_number:02d}",
                "disease": disease,
                "condition": disease,
                "symptoms": disease,
                "caseClassification": classification,
                "classification": classification,
                "severity": severity,
                "status": "Active" if sequence % 3 else "Monitoring",
                "dateReported": report_date,
                "createdAt": report_date,
            }
            output["morbidity_records"].append(
                (f"{SEED_VERSION}-morbidity-{sequence + 1:03d}", payload)
            )

    mortality_causes = ("Cardiovascular disease", "Pneumonia", "Stroke")
    mortality_count = max(3, (months + 2) // 3)
    for index in range(mortality_count):
        report_date = month_date(now, min(index * 3, months - 1), day=14)
        payload = {
            **_base(scope, report_date),
            "patientName": f"Demo Mortality Case {index + 1:02d}",
            "age": 58 + index * 6,
            "gender": "Male" if index % 2 else "Female",
            "causeOfDeath": mortality_causes[index % len(mortality_causes)],
            "causeCategory": mortality_causes[index % len(mortality_causes)],
            "dateTimeOfDeath": report_date,
            "dateReported": report_date,
            "verification": "Verified" if index % 2 else "Pending",
            "createdAt": report_date,
        }
        output["mortality_records"].append(
            (f"{SEED_VERSION}-mortality-{index + 1:03d}", payload)
        )

    referral_statuses = ("submitted", "assigned", "in-treatment", "completed")
    for month_index in range(months):
        patient_number = ((month_index * 4) % patient_count) + 1
        referral_date = month_date(now, month_index, day=16)
        disease, _, severity = all_cases[(month_index + 4) % len(all_cases)]
        payload = {
            **_base(scope, referral_date),
            "patientRecordId": f"DEMO-{scope.barangay_code}-{patient_number:03d}",
            "patientName": f"Demo Analytics Patient {patient_number:02d}",
            "referralDateTime": referral_date,
            "referralType": "Medical consultation",
            "referralCategorySummary": disease,
            "referralReason": f"Follow-up assessment for {disease}",
            "urgency": severity,
            "status": referral_statuses[month_index % len(referral_statuses)],
            "referredTo": "City Health Office",
            "createdAt": referral_date,
        }
        output["referrals"].append(
            (f"{SEED_VERSION}-referral-{month_index + 1:03d}", payload)
        )

    return output


def discover_bhw_scopes(db: Any, requested_codes: set[str]) -> list[BhwScope]:
    scopes: dict[str, BhwScope] = {}
    for document in db.collection("users").stream():
        data = document.to_dict() or {}
        if str(data.get("role", "")).strip().lower() != "bhw":
            continue
        code = normalize_code(str(data.get("barangayCode", "")))
        if not code or (requested_codes and code not in requested_codes):
            continue
        scopes.setdefault(
            code,
            BhwScope(
                uid=document.id,
                barangay_code=code,
                barangay_name=str(data.get("barangay") or code).strip(),
                barangay_district=str(data.get("barangayDistrict") or "").strip(),
            ),
        )
    return sorted(scopes.values(), key=lambda value: value.barangay_code)


def record_total(records: dict[str, list[tuple[str, dict[str, Any]]]]) -> int:
    return sum(len(values) for values in records.values())


def commit_in_chunks(db: Any, writes: Iterable[tuple[Any, dict[str, Any]]]) -> int:
    committed = 0
    batch = db.batch()
    pending = 0
    for reference, payload in writes:
        batch.set(reference, payload, merge=True)
        pending += 1
        if pending == 400:
            batch.commit()
            committed += pending
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
        committed += pending
    return committed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Seed scoped Firestore demo data for BHW Analytics."
    )
    parser.add_argument("--apply", action="store_true", help="Write to Firestore")
    parser.add_argument(
        "--barangay-code",
        action="append",
        default=[],
        help="Limit to a barangay code; repeat to select multiple scopes",
    )
    parser.add_argument("--months", type=int, default=10)
    parser.add_argument("--patients", type=int, default=15)
    args = parser.parse_args()

    requested_codes = {normalize_code(value) for value in args.barangay_code}
    db = get_firestore_client()
    scopes = discover_bhw_scopes(db, requested_codes)
    if not scopes:
        requested = ", ".join(sorted(requested_codes)) or "any registered BHW scope"
        raise SystemExit(f"No BHW user was found for {requested}.")

    planned: list[tuple[BhwScope, dict[str, list[tuple[str, dict[str, Any]]]]]] = []
    for scope in scopes:
        records = build_scope_records(
            scope,
            months=args.months,
            patient_count=args.patients,
        )
        planned.append((scope, records))
        collection_summary = ", ".join(
            f"{collection}={len(records[collection])}" for collection in COLLECTIONS
        )
        print(f"{scope.barangay_code}: {collection_summary}")

    total = sum(record_total(records) for _, records in planned)
    if not args.apply:
        print(
            f"Dry run: validated {total} deterministic demo documents across "
            f"{len(scopes)} BHW barangay scopes. Use --apply to write them."
        )
        return 0

    writes: list[tuple[Any, dict[str, Any]]] = []
    for scope, records in planned:
        barangay_ref = db.collection("barangays").document(scope.barangay_code)
        for collection, documents in records.items():
            for document_id, payload in documents:
                reference = barangay_ref.collection(collection).document(document_id)
                writes.append((reference, payload))

    committed = commit_in_chunks(db, writes)
    print(
        f"Applied {committed} deterministic demo documents across "
        f"{len(scopes)} BHW barangay scopes. No documents were deleted."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
