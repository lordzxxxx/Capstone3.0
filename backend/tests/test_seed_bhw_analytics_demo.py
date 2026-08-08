from __future__ import annotations

from datetime import datetime, timezone

from backend.firebase.seed_bhw_analytics_demo import (
    BhwScope,
    SEED_VERSION,
    build_scope_records,
    month_date,
    record_total,
)


def test_month_date_handles_prior_year_and_current_day() -> None:
    anchor = datetime(2026, 1, 5, tzinfo=timezone.utc)

    assert month_date(anchor, 1).date().isoformat() == "2025-12-10"
    assert month_date(anchor, 0).date().isoformat() == "2026-01-05"


def test_seed_records_fill_all_bhw_analytics_sources() -> None:
    scope = BhwScope(
        uid="bhw-test-uid",
        barangay_code="AGLAYAN",
        barangay_name="Aglayan",
        barangay_district="South Highway District",
    )
    records = build_scope_records(
        scope,
        anchor=datetime(2026, 7, 17, tzinfo=timezone.utc),
        months=10,
        patient_count=15,
    )

    assert set(records) == {
        "patient_records",
        "checkup_records",
        "immunization_records",
        "morbidity_records",
        "mortality_records",
        "referrals",
    }
    assert record_total(records) == 79
    assert len(records["patient_records"]) == 15
    assert len(records["checkup_records"]) == 20
    assert len(records["morbidity_records"]) == 20

    all_payloads = [
        payload
        for collection_records in records.values()
        for _, payload in collection_records
    ]
    assert all(payload["isDemoData"] is True for payload in all_payloads)
    assert all(payload["demoDataset"] == SEED_VERSION for payload in all_payloads)
    assert all(payload["barangayCode"] == "AGLAYAN" for payload in all_payloads)

    classifications = {
        payload["caseClassification"]
        for _, payload in records["morbidity_records"]
    }
    assert classifications == {"Communicable", "Non-Communicable"}

    assert all(
        payload["createdByUid"] == scope.uid
        for _, payload in records["referrals"]
    )


def test_seed_document_ids_are_stable() -> None:
    scope = BhwScope("uid", "BANGCUD", "Bangcud")
    anchor = datetime(2026, 7, 17, tzinfo=timezone.utc)

    first = build_scope_records(scope, anchor=anchor)
    second = build_scope_records(scope, anchor=anchor)

    assert [doc_id for doc_id, _ in first["checkup_records"]] == [
        doc_id for doc_id, _ in second["checkup_records"]
    ]
