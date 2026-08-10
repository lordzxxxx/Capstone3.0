from datetime import datetime, timezone

from backend.firebase.seed_bhw_analytics_demo import BhwScope
from backend.firebase.seed_care_workflow_demo import (
    SEED_VERSION,
    build_workflow_records,
)


def test_workflow_seed_contains_notes_schedule_conflict_and_completed_referral() -> None:
    scope = BhwScope("bhw-uid", "MAGSAYSAY", "Magsaysay")
    records = build_workflow_records(
        scope,
        doctor_a_uid="doctor-a-uid",
        doctor_b_uid="doctor-b-uid",
        anchor=datetime(2026, 8, 10, 9, tzinfo=timezone.utc),
    )

    assert set(records) == {"doctor_registry", "doctor_notes", "referrals"}
    assert len(records["doctor_registry"]) == 2
    assert len(records["doctor_notes"]) == 2
    assert len(records["referrals"]) == 3
    assert all(payload["isDemoData"] is True for values in records.values() for _, payload in values)
    assert all(payload["demoDataset"] == SEED_VERSION for values in records.values() for _, payload in values)

    doctor_a = records["doctor_registry"][0][1]
    assert doctor_a["availableDays"]
    assert doctor_a["workingHours"]["monday"] == {"start": "08:00", "end": "17:00"}

    notes = [payload for _, payload in records["doctor_notes"]]
    assert {note["authorUid"] for note in notes} == {"doctor-a-uid", "doctor-b-uid"}
    assert notes[0]["patientId"] == notes[1]["patientId"]
    assert all("medication" not in note["note"].lower() for note in notes)

    statuses = {payload["status"] for _, payload in records["referrals"]}
    assert statuses == {"assigned", "completed"}
    assigned = [payload for _, payload in records["referrals"] if payload["status"] == "assigned"]
    assert assigned[0]["assignedDoctorUid"] == assigned[1]["assignedDoctorUid"] == "doctor-a-uid"
    assert assigned[0]["appointmentDateTime"] < assigned[1]["appointmentDateTime"]


def test_workflow_seed_requires_real_demo_uids() -> None:
    scope = BhwScope("bhw-uid", "MAGSAYSAY", "Magsaysay")
    try:
        build_workflow_records(scope, doctor_a_uid="", doctor_b_uid="doctor-b")
    except ValueError as error:
        assert "doctor UIDs" in str(error)
    else:
        raise AssertionError("empty doctor UID should be rejected")
