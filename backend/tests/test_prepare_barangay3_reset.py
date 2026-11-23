from pathlib import Path
import ast


def test_barangay3_reset_is_guarded_and_covers_root_and_nested_clinical_records():
    source = (Path(__file__).resolve().parents[1] / "firebase" / "prepare_barangay3_reset.py").read_text()
    assert 'TARGET_EMAIL = "frisky4@gmail.com"' in source
    assert 'TARGET_BARANGAY_CODE = "POBLACION-03"' in source
    assert 'collection_group(collection_id)' in source
    assert '"patient_records"' in source
    assert '"doctor_notes"' in source
    assert 'bhw_registration_requests' in source
    assert 'db.reference' in source
    assert '--recovery-reference is required' in source
    assert 'RESET_CLINICAL_DATA_AND_MOVE_FRISKY4' in source
    ast.parse(source)
