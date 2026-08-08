"""Seed complete barangay patient profiles with linked service histories.

Dry-run by default. Pass ``--apply`` to write deterministic, merge-safe demo
documents. The command never deletes existing Firestore data.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

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

SEED_VERSION = "barangay-patient-history-demo-v1"
COLLECTIONS = (
    "patient_records",
    "checkup_records",
    "prenatal_records",
    "immunization_records",
)

FIRST_NAMES = (
    "Maria",
    "Jose",
    "Angela",
    "Carlo",
    "Liza",
    "Miguel",
    "Rose",
    "Daniel",
    "Grace",
    "Paolo",
)
MIDDLE_NAMES = ("Reyes", "Cruz", "Garcia", "Santos", "Flores")
SURNAMES = (
    "Dela Cruz",
    "Fernandez",
    "Ramos",
    "Mendoza",
    "Villanueva",
    "Torres",
    "Castillo",
    "Navarro",
    "Aquino",
    "Bautista",
)


def _base(scope: BhwScope, event_date: datetime) -> dict[str, Any]:
    return {
        "barangay": scope.barangay_name,
        "barangayCode": scope.barangay_code,
        "barangayDistrict": scope.barangay_district,
        "createdByUid": scope.uid,
        "registeredByUid": scope.uid,
        "isDemoData": True,
        "demoDataset": SEED_VERSION,
        "seedVersion": SEED_VERSION,
        "updatedAt": event_date,
    }


def build_records(
    scope: BhwScope,
    *,
    patient_count: int = 50,
    anchor: datetime | None = None,
) -> dict[str, list[tuple[str, dict[str, Any]]]]:
    if patient_count < 1:
        raise ValueError("patient_count must be positive")

    now = anchor or datetime.now(timezone.utc)
    records = {collection: [] for collection in COLLECTIONS}
    symptoms = (
        "Fever and cough",
        "Headache and fatigue",
        "Abdominal discomfort",
        "Runny nose and sore throat",
        "Body pain and dizziness",
    )
    vaccines = ("BCG", "Pentavalent", "OPV", "MMR", "Hepatitis B")
    blood_types = ("O+", "A+", "B+", "AB+", "O-")

    for index in range(patient_count):
        number = index + 1
        first_name = FIRST_NAMES[index % len(FIRST_NAMES)]
        middle_name = MIDDLE_NAMES[index % len(MIDDLE_NAMES)]
        surname = SURNAMES[index % len(SURNAMES)]
        full_name = f"{first_name} {middle_name} {surname}"
        sex = "Female" if index % 2 == 0 else "Male"
        age = 4 + ((index * 3) % 43)
        birth_year = now.year - age
        date_of_birth = f"{birth_year}-{(index % 12) + 1:02d}-{(index % 27) + 1:02d}"
        patient_id = f"DEMO-{scope.barangay_code}-{number:03d}"
        registration_date = month_date(now, index % 12, 3 + (index % 20))
        phone = f"0917{number:07d}"
        emergency_phone = f"0928{number:07d}"
        household_id = f"HH-{scope.barangay_code}-{((index // 4) + 1):03d}"
        address = f"Purok {(index % 7) + 1}, {scope.barangay_name}"

        patient = {
            **_base(scope, registration_date),
            "patientId": patient_id,
            "linkedPatientId": patient_id,
            "firstName": first_name,
            "middleName": middle_name,
            "surname": surname,
            "lastName": surname,
            "fullName": full_name,
            "patientName": full_name,
            "dateOfBirth": date_of_birth,
            "age": age,
            "sex": sex,
            "gender": sex,
            "address": address,
            "street": address,
            "householdId": household_id,
            "contactNumber": phone,
            "phoneNumber": phone,
            "emergencyContact": f"Elena {surname}",
            "emergencyContactName": f"Elena {surname}",
            "emergencyContactNumber": emergency_phone,
            "emergencyContactPhone": emergency_phone,
            "medicalHistory": "No known chronic illness" if index % 4 else "Asthma",
            "pastMedicalHistory": "No known chronic illness" if index % 4 else "Asthma",
            "allergies": "None reported" if index % 5 else "Penicillin",
            "bloodType": blood_types[index % len(blood_types)],
            "status": "Active",
            "registrationDate": registration_date,
            "createdAt": registration_date,
        }
        records["patient_records"].append(
            (f"{SEED_VERSION}-patient-{number:03d}", patient)
        )

        for visit in range(2):
            visit_date = month_date(now, (index + visit * 4) % 12, 7 + visit * 8)
            systolic = 105 + ((index * 3 + visit * 7) % 42)
            diastolic = 65 + ((index * 2 + visit * 5) % 25)
            temperature = 36.2 + ((index + visit) % 7) / 10
            checkup = {
                **_base(scope, visit_date),
                "patientId": patient_id,
                "linkedPatientId": patient_id,
                "patient": full_name,
                "patientName": full_name,
                "firstName": first_name,
                "surname": surname,
                "age": str(age),
                "address": address,
                "datetime": visit_date,
                "date": visit_date,
                "vitalsigns": (
                    f"BP: {systolic}/{diastolic}, Temp: {temperature:.1f}°C, "
                    f"HR: {72 + index % 18} bpm, O2: {96 + index % 4}%"
                ),
                "bloodPressure": f"{systolic}/{diastolic}",
                "bpSystolic": systolic,
                "bpDiastolic": diastolic,
                "temperature": round(temperature, 1),
                "symptoms": symptoms[(index + visit) % len(symptoms)],
                "followup": "N/A" if visit else "Follow-up scheduled",
                "status": "Completed",
                "type": "General",
                "createdAt": visit_date,
            }
            records["checkup_records"].append(
                (f"{SEED_VERSION}-checkup-{number:03d}-{visit + 1}", checkup)
            )

        immunization_date = month_date(now, index % 12, 12)
        immunization = {
            **_base(scope, immunization_date),
            "patientId": patient_id,
            "linkedPatientId": patient_id,
            "patientName": full_name,
            "age": age,
            "sex": sex,
            "vaccine": vaccines[index % len(vaccines)],
            "vaccineName": vaccines[index % len(vaccines)],
            "immunizationType": vaccines[index % len(vaccines)],
            "doseNumber": (index % 3) + 1,
            "administrationDate": immunization_date,
            "dateAdministered": immunization_date,
            "nextSchedule": month_date(now, max(0, (index % 12) - 1), 20),
            "status": "Completed",
            "createdAt": immunization_date,
        }
        records["immunization_records"].append(
            (f"{SEED_VERSION}-immunization-{number:03d}", immunization)
        )

        if sex == "Female" and 18 <= age <= 45:
            for visit in range(3):
                prenatal_date = month_date(now, (index + visit * 2) % 10, 10 + visit * 4)
                gestational_weeks = 12 + visit * 10 + (index % 3)
                risk = "High Risk" if index % 10 == 0 else "Active"
                prenatal = {
                    **_base(scope, prenatal_date),
                    "patientId": patient_id,
                    "linkedPatientId": patient_id,
                    "patientName": full_name,
                    "firstName": first_name,
                    "surname": surname,
                    "age": str(age),
                    "address": address,
                    "contactNumber": phone,
                    "gravida": 1 + (index % 4),
                    "para": index % 3,
                    "riskLevel": risk,
                    "status": risk,
                    "bloodType": blood_types[index % len(blood_types)],
                    "allergies": patient["allergies"],
                    "aog": f"{gestational_weeks} weeks",
                    "gestationalAge": gestational_weeks,
                    "wt": f"{52 + index % 18} kg",
                    "temp": "36.7°C",
                    "bp": f"{108 + index % 22}/{68 + index % 16}",
                    "fh": f"{max(12, gestational_weeks - 2)} cm",
                    "dhb": f"{135 + index % 15} bpm",
                    "registrationDate": prenatal_date,
                    "visitDate": prenatal_date,
                    "createdAt": prenatal_date,
                }
                records["prenatal_records"].append(
                    (f"{SEED_VERSION}-prenatal-{number:03d}-{visit + 1}", prenatal)
                )

    return records


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Seed complete patients with linked service histories."
    )
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--barangay-code", required=True)
    parser.add_argument("--patients", type=int, default=50)
    args = parser.parse_args()

    code = normalize_code(args.barangay_code)
    db = get_firestore_client()
    scopes = discover_bhw_scopes(db, {code})
    if not scopes:
        raise SystemExit(f"No registered BHW scope was found for {code}.")

    scope = scopes[0]
    records = build_records(scope, patient_count=args.patients)
    summary = ", ".join(
        f"{collection}={len(records[collection])}" for collection in COLLECTIONS
    )
    print(f"{scope.barangay_code}: {summary}")
    total = sum(len(items) for items in records.values())
    if not args.apply:
        print(f"Dry run: validated {total} deterministic linked demo documents.")
        return 0

    barangay_ref = db.collection("barangays").document(scope.barangay_code)
    writes = []
    for collection, documents in records.items():
        for document_id, payload in documents:
            writes.append(
                (barangay_ref.collection(collection).document(document_id), payload)
            )
    committed = commit_in_chunks(db, writes)
    print(f"Applied {committed} linked demo documents. No documents were deleted.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
