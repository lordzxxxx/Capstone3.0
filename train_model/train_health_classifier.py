#!/usr/bin/env python3
"""
Health Data Classification Model Training Script
Trains a TensorFlow Lite model for classifying health records into categories

Requirements:
    pip install tensorflow numpy pandas scikit-learn
"""

import tensorflow as tf
import numpy as np
import json
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
import os
import argparse
import re
from collections import Counter

# Paths resolved from this script location so commands work from any cwd.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
MODELS_DIR = os.path.join(PROJECT_ROOT, 'assets', 'models')

# Configuration
CATEGORIES = [
    'Communicable Disease',
    'Non-Communicable Disease',
    'Emergency',
    'Routine Checkup',
    'Prenatal Care',
    'Pediatric Care',
]

SEVERITY_LEVELS = ['Low', 'Medium', 'High', 'Critical']

# Medical keywords for feature engineering
KEYWORDS = {
    'communicable': [
        'fever', 'cough', 'flu', 'cold', 'infection', 'tuberculosis',
        'dengue', 'covid', 'measles', 'chickenpox', 'pneumonia',
        'sore throat', 'runny nose', 'body pain', 'headache', 'chills',
        'rash', 'vomiting', 'diarrhea', 'malaria', 'hepatitis',
        'typhoid', 'pertussis', 'mumps', 'rubella', 'meningitis',
        'bronchitis', 'viral infection', 'bacterial infection',
        'respiratory infection', 'skin infection', 'ear infection',
        'pink eye', 'conjunctivitis', 'hand foot and mouth disease',
        'hfmd', 'scabies', 'lice', 'parasite', 'worm infection',
        'gastroenteritis', 'uti', 'urinary tract infection'
    ],
    'emergency': [
        'chest pain', 'difficulty breathing', 'severe bleeding',
        'unconscious', 'seizure', 'stroke', 'heart attack',
        'fainting', 'loss of consciousness', 'shortness of breath',
        'severe headache', 'confusion', 'slurred speech',
        'numbness', 'paralysis', 'high fever', 'convulsion',
        'severe burn', 'broken bone', 'fracture', 'deep wound',
        'vomiting blood', 'blood in stool', 'severe dehydration',
        'allergic reaction', 'anaphylaxis', 'poisoning',
        'snake bite', 'dog bite', 'road accident', 'trauma',
        'collapse', 'labor pain', 'heavy vaginal bleeding',
        'unresponsive', 'bluish lips', 'rapid heartbeat'
    ],
    'non_communicable': [
        'diabetes', 'hypertension', 'asthma', 'arthritis',
        'cancer', 'thyroid', 'cholesterol', 'obesity',
        'heart disease', 'kidney disease', 'chronic kidney disease',
        'ckd', 'copd', 'chronic obstructive pulmonary disease',
        'osteoporosis', 'gout', 'epilepsy', 'migraine',
        'allergy', 'eczema', 'psoriasis', 'anemia',
        'liver disease', 'fatty liver', 'ulcer', 'gastritis',
        'acid reflux', 'gerd', 'depression', 'anxiety',
        'mental illness', 'bronchial asthma', 'high blood pressure',
        'coronary artery disease', 'stroke history', 'heart failure',
        'arrhythmia', 'insomnia', 'constipation'
    ],
    'prenatal': ['pregnant', 'pregnancy', 'prenatal', 'antenatal', 'maternal'],
    'pediatric': ['infant', 'child', 'baby', 'newborn', 'toddler'],
}

# Feature layout shared with Flutter runtime.
FEATURE_VECTOR_SIZE = 200
KEYWORD_FEATURE_START = 1
KEYWORD_BUCKET_COUNT = 50
BP_SYSTOLIC_FEATURE_INDEX = KEYWORD_FEATURE_START + KEYWORD_BUCKET_COUNT
BP_DIASTOLIC_FEATURE_INDEX = BP_SYSTOLIC_FEATURE_INDEX + 1
TEMP_FEATURE_INDEX = BP_DIASTOLIC_FEATURE_INDEX + 1
HR_FEATURE_INDEX = TEMP_FEATURE_INDEX + 1

# Category-level guidance used when no keyword-specific treatment is matched.
CATEGORY_RECOVERY_GUIDANCE = {
    'Communicable Disease': {
        'home_care': [
            'Rest and stay hydrated',
            'Monitor symptoms daily',
            'Practice hygiene and avoid close contact while contagious',
        ],
        'general_advice': [
            'Seek medical review if symptoms worsen',
            'Complete prescribed treatment course',
        ],
    },
    'Non-Communicable Disease': {
        'home_care': [
            'Follow diet and lifestyle plan',
            'Track blood pressure or glucose as advised',
            'Keep regular follow-up appointments',
        ],
        'general_advice': [
            'Keep scheduled clinical follow-up and monitoring',
            'Maintain routine preventive care',
        ],
    },
    'Emergency': {
        'home_care': ['Seek urgent in-person care immediately'],
        'general_advice': [
            'Call emergency services for severe or sudden symptoms',
            'Do not delay treatment',
        ],
    },
    'Routine Checkup': {
        'home_care': [
            'Maintain hydration, sleep, and balanced nutrition',
            'Continue preventive screening as scheduled',
        ],
        'general_advice': [
            'Return for review if new symptoms appear',
            'Follow personalized clinician advice',
        ],
    },
    'Prenatal Care': {
        'home_care': [
            'Attend regular prenatal visits',
            'Maintain healthy diet and hydration',
            'Monitor fetal movement and warning signs',
        ],
        'general_advice': [
            'Seek care for bleeding, severe pain, or reduced fetal movement',
            'Follow obstetric provider recommendations closely',
        ],
    },
    'Pediatric Care': {
        'home_care': [
            'Ensure hydration, nutrition, and rest',
            'Keep vaccinations and checkups up to date',
        ],
        'general_advice': [
            'Seek urgent care for breathing issues or persistent high fever',
            'Consult pediatrician for dosing and follow-up',
        ],
    },
}

CATEGORY_ALIASES = {
    'communicable': 'Communicable Disease',
    'communicable disease': 'Communicable Disease',
    'infectious disease': 'Communicable Disease',
    'respiratory': 'Communicable Disease',
    'non-communicable': 'Non-Communicable Disease',
    'non communicable': 'Non-Communicable Disease',
    'non-communicable disease': 'Non-Communicable Disease',
    'non communicable disease': 'Non-Communicable Disease',
    'ncd': 'Non-Communicable Disease',
    'chronic disease': 'Non-Communicable Disease',
    'metabolic': 'Non-Communicable Disease',
    'cardiovascular': 'Non-Communicable Disease',
    'musculoskeletal': 'Non-Communicable Disease',
    'mental health': 'Non-Communicable Disease',
    'neurological': 'Non-Communicable Disease',
    'emergency': 'Emergency',
    'critical': 'Emergency',
    'routine': 'Routine Checkup',
    'routine checkup': 'Routine Checkup',
    'general': 'Routine Checkup',
    'checkup': 'Routine Checkup',
    'prenatal': 'Prenatal Care',
    'prenatal care': 'Prenatal Care',
    'maternal': 'Prenatal Care',
    'maternal care': 'Prenatal Care',
    'antenatal': 'Prenatal Care',
    'pediatric': 'Pediatric Care',
    'pediatric care': 'Pediatric Care',
    'child health': 'Pediatric Care',
    'immunization': 'Pediatric Care',
}

SEVERITY_ALIASES = {
    'low': 'Low',
    'mild': 'Low',
    'medium': 'Medium',
    'moderate': 'Medium',
    'high': 'High',
    'severe': 'High',
    'critical': 'Critical',
}


def _build_feature_keywords():
    """Build unique keyword list used for hashed text features."""
    seen = set()
    feature_keywords = []

    for keyword_list in KEYWORDS.values():
        for keyword in keyword_list:
            normalized = str(keyword).strip().lower()
            if not normalized or normalized in seen:
                continue
            seen.add(normalized)
            feature_keywords.append(normalized)

    return feature_keywords


FEATURE_KEYWORDS = _build_feature_keywords()


def _fnv1a_32(text):
    """Deterministic 32-bit hash used by both Python and Flutter."""
    hash_value = 2166136261
    for byte in text.encode('utf-8'):
        hash_value ^= byte
        hash_value = (hash_value * 16777619) & 0xFFFFFFFF
    return hash_value


def _keyword_feature_index(keyword):
    """Map a keyword to one of the fixed hash buckets."""
    return KEYWORD_FEATURE_START + (_fnv1a_32(keyword) % KEYWORD_BUCKET_COUNT)


def _verify_keywords(keywords_to_verify):
    """Print whether specific keywords are included in feature extraction."""
    if not keywords_to_verify:
        return

    feature_lookup = set(FEATURE_KEYWORDS)
    print("\nKeyword verification:")
    for keyword in keywords_to_verify:
        normalized = str(keyword).strip().lower()
        if not normalized:
            continue
        in_features = normalized in feature_lookup
        if in_features:
            bucket = _keyword_feature_index(normalized)
            print(f"  [OK] '{normalized}' is used (hash bucket index: {bucket})")
        else:
            print(f"  [WARN] '{normalized}' is NOT in KEYWORDS and will be ignored")


def _sample_intensity(category):
    """Sample synthetic case intensity by category."""
    if category == 'Emergency':
        return float(np.random.beta(5.0, 1.4))
    if category == 'Routine Checkup':
        return float(np.random.beta(1.2, 4.5))
    if category == 'Communicable Disease':
        return float(np.random.beta(2.3, 2.0))
    if category == 'Non-Communicable Disease':
        return float(np.random.beta(2.0, 2.3))
    if category == 'Prenatal Care':
        return float(np.random.beta(1.8, 2.7))
    if category == 'Pediatric Care':
        return float(np.random.beta(1.7, 2.9))
    return float(np.random.beta(2.0, 2.0))


def _normal_vitals_for_age(age):
    """Generate age-appropriate normal vitals."""
    if age < 10:
        bp_systolic = np.random.randint(90, 112)
        bp_diastolic = np.random.randint(58, 76)
        hr = np.random.randint(75, 115)
    elif age < 18:
        bp_systolic = np.random.randint(100, 124)
        bp_diastolic = np.random.randint(62, 82)
        hr = np.random.randint(68, 104)
    else:
        bp_systolic = np.random.randint(108, 132)
        bp_diastolic = np.random.randint(68, 86)
        hr = np.random.randint(60, 96)

    temp = float(np.random.uniform(36.4, 37.2))
    return bp_systolic, bp_diastolic, temp, hr


def _inject_bp_abnormality(intensity):
    severe = intensity >= 0.72
    direction = np.random.choice(['high', 'low'], p=[0.78, 0.22])

    if direction == 'high':
        if severe:
            return np.random.randint(175, 211), np.random.randint(112, 131)
        return np.random.randint(145, 175), np.random.randint(92, 112)

    if severe:
        return np.random.randint(70, 86), np.random.randint(42, 56)
    return np.random.randint(86, 100), np.random.randint(56, 68)


def _inject_temp_abnormality(intensity):
    severe = intensity >= 0.72
    direction = np.random.choice(['high', 'low'], p=[0.9, 0.1])

    if direction == 'high':
        if severe:
            return float(np.random.uniform(39.6, 41.0))
        return float(np.random.uniform(38.0, 39.6))

    if severe:
        return float(np.random.uniform(34.2, 35.0))
    return float(np.random.uniform(35.0, 36.0))


def _inject_hr_abnormality(intensity):
    severe = intensity >= 0.72
    direction = np.random.choice(['high', 'low'], p=[0.8, 0.2])

    if direction == 'high':
        if severe:
            return np.random.randint(130, 171)
        return np.random.randint(101, 130)

    if severe:
        return np.random.randint(35, 50)
    return np.random.randint(50, 60)


def _generate_vitals(age, intensity):
    """
    Generate vitals with abnormalities based on case intensity.
    Higher intensity means more abnormal vital signs.
    """
    bp_systolic, bp_diastolic, temp, hr = _normal_vitals_for_age(age)

    if intensity < 0.30:
        return bp_systolic, bp_diastolic, temp, hr

    if intensity < 0.55:
        band = 'medium'
    elif intensity < 0.78:
        band = 'high'
    else:
        band = 'critical'

    def apply_abnormality(vital, level, bp_sys, bp_dia, body_temp, heart_rate):
        if vital == 'bp':
            high_prob = 0.75
            direction = np.random.choice(['high', 'low'], p=[high_prob, 1.0 - high_prob])
            if level == 'medium':
                if direction == 'high':
                    bp_sys = np.random.randint(145, 160)
                    bp_dia = np.random.randint(90, 100)
                else:
                    bp_sys = np.random.randint(90, 100)
                    bp_dia = np.random.randint(60, 70)
            elif level == 'high':
                if direction == 'high':
                    bp_sys = np.random.randint(160, 180)
                    bp_dia = np.random.randint(100, 120)
                else:
                    bp_sys = np.random.randint(80, 90)
                    bp_dia = np.random.randint(50, 60)
            else:  # critical
                if direction == 'high':
                    bp_sys = np.random.randint(180, 211)
                    bp_dia = np.random.randint(120, 131)
                else:
                    bp_sys = np.random.randint(65, 80)
                    bp_dia = np.random.randint(40, 50)
        elif vital == 'temp':
            direction = np.random.choice(['high', 'low'], p=[0.9, 0.1])
            if level == 'medium':
                body_temp = (
                    float(np.random.uniform(37.8, 38.6))
                    if direction == 'high'
                    else float(np.random.uniform(35.6, 36.0))
                )
            elif level == 'high':
                body_temp = (
                    float(np.random.uniform(39.0, 39.8))
                    if direction == 'high'
                    else float(np.random.uniform(35.0, 35.5))
                )
            else:  # critical
                body_temp = (
                    float(np.random.uniform(40.0, 41.2))
                    if direction == 'high'
                    else float(np.random.uniform(34.0, 34.9))
                )
        else:  # hr
            direction = np.random.choice(['high', 'low'], p=[0.8, 0.2])
            if level == 'medium':
                heart_rate = (
                    np.random.randint(100, 115)
                    if direction == 'high'
                    else np.random.randint(55, 60)
                )
            elif level == 'high':
                heart_rate = (
                    np.random.randint(115, 130)
                    if direction == 'high'
                    else np.random.randint(45, 55)
                )
            else:  # critical
                heart_rate = (
                    np.random.randint(130, 171)
                    if direction == 'high'
                    else np.random.randint(30, 45)
                )

        return bp_sys, bp_dia, body_temp, heart_rate

    primary_vital = np.random.choice(['bp', 'temp', 'hr'])
    bp_systolic, bp_diastolic, temp, hr = apply_abnormality(
        primary_vital,
        band,
        bp_systolic,
        bp_diastolic,
        temp,
        hr,
    )

    add_secondary = (
        (band == 'medium' and np.random.rand() < 0.25)
        or (band == 'high' and np.random.rand() < 0.60)
        or (band == 'critical' and np.random.rand() < 0.85)
    )
    if add_secondary:
        remaining = [v for v in ['bp', 'temp', 'hr'] if v != primary_vital]
        secondary_vital = np.random.choice(remaining)
        secondary_level = 'medium' if band == 'medium' else 'high'
        bp_systolic, bp_diastolic, temp, hr = apply_abnormality(
            secondary_vital,
            secondary_level,
            bp_systolic,
            bp_diastolic,
            temp,
            hr,
        )

    if band == 'critical' and np.random.rand() < 0.35:
        remaining = [v for v in ['bp', 'temp', 'hr'] if v not in [primary_vital]]
        tertiary_vital = np.random.choice(remaining)
        bp_systolic, bp_diastolic, temp, hr = apply_abnormality(
            tertiary_vital,
            'critical',
            bp_systolic,
            bp_diastolic,
            temp,
            hr,
        )

    return bp_systolic, bp_diastolic, temp, hr


def _severity_from_rules(category, age, bp_systolic, bp_diastolic, temp, hr, symptoms):
    """
    Determine severity from vitals + context using deterministic rules.
    This removes random severity labels from synthetic data.
    """
    level = 0  # 0=Low, 1=Medium, 2=High, 3=Critical

    # Blood pressure level
    if bp_systolic >= 180 or bp_systolic < 85 or bp_diastolic >= 120 or bp_diastolic < 55:
        level = max(level, 3)
    elif bp_systolic >= 160 or bp_systolic < 95 or bp_diastolic >= 100 or bp_diastolic < 65:
        level = max(level, 2)
    elif bp_systolic >= 145 or bp_systolic < 100 or bp_diastolic >= 90 or bp_diastolic < 70:
        level = max(level, 1)

    # Temperature level
    if temp >= 40.0 or temp < 35.0:
        level = max(level, 3)
    elif temp >= 39.0 or temp < 35.5:
        level = max(level, 2)
    elif temp >= 37.8 or temp < 36.0:
        level = max(level, 1)

    # Heart-rate level
    if hr >= 130 or hr < 45:
        level = max(level, 3)
    elif hr >= 115 or hr < 55:
        level = max(level, 2)
    elif hr >= 100 or hr < 60:
        level = max(level, 1)

    symptoms_text = (symptoms or '').lower()
    critical_keywords = ['unconscious', 'stroke', 'heart attack', 'severe bleeding']
    high_keywords = ['chest pain', 'difficulty breathing', 'seizure']

    if any(keyword in symptoms_text for keyword in critical_keywords):
        level = max(level, 3)
    elif any(keyword in symptoms_text for keyword in high_keywords):
        level = max(level, 2)

    # Category and age guardrails
    if category == 'Emergency':
        level = max(level, 2)
    if age >= 75 and level == 0:
        level = 1

    return ['Low', 'Medium', 'High', 'Critical'][level]


def create_synthetic_training_data(num_samples=1000):
    """
    Generate synthetic training data for demonstration
    In production, use your actual health records from Firebase
    Data is based on keywords from communicable, emergency, non_communicable, prenatal, and pediatric categories
    """
    print(f"Generating {num_samples} synthetic training samples...")
    
    data = []
    
    for _ in range(num_samples):
        # Random category
        category = np.random.choice(CATEGORIES)

        # Generate symptoms based on category keywords
        if category == 'Communicable Disease':
            selected_keywords = np.random.choice(
                KEYWORDS['communicable'],
                size=np.random.randint(1, 4),
                replace=False,
            )
            age = np.random.randint(5, 85)
            symptoms = ', '.join(selected_keywords)
        elif category == 'Emergency':
            selected_keywords = np.random.choice(
                KEYWORDS['emergency'],
                size=np.random.randint(1, 3),
                replace=False,
            )
            age = np.random.randint(20, 85)
            symptoms = ', '.join(selected_keywords)
        elif category == 'Non-Communicable Disease':
            selected_keywords = np.random.choice(
                KEYWORDS['non_communicable'],
                size=np.random.randint(1, 4),
                replace=False,
            )
            age = np.random.randint(30, 90)
            symptoms = ', '.join(selected_keywords)
        elif category == 'Prenatal Care':
            selected_keywords = np.random.choice(
                KEYWORDS['prenatal'],
                size=np.random.randint(1, 3),
                replace=False,
            )
            age = np.random.randint(18, 45)
            symptoms = ', '.join(selected_keywords)
        elif category == 'Pediatric Care':
            selected_keywords = np.random.choice(
                KEYWORDS['pediatric'],
                size=np.random.randint(1, 3),
                replace=False,
            )
            age = np.random.randint(1, 18)
            symptoms = ', '.join(selected_keywords)
        else:  # Routine Checkup
            age = np.random.randint(1, 90)
            symptoms = np.random.choice(
                ['general checkup', 'follow-up visit', 'routine monitoring'],
            )

        # Severity is now derived from generated clinical signals, not random labels.
        intensity = _sample_intensity(category)
        bp_systolic, bp_diastolic, temp, hr = _generate_vitals(age, intensity)

        severity = _severity_from_rules(
            category,
            age,
            bp_systolic,
            bp_diastolic,
            temp,
            hr,
            symptoms,
        )

        # Category-specific guardrails for realism
        if category == 'Emergency' and severity in ['Low', 'Medium']:
            severity = 'High'
        if category == 'Routine Checkup' and severity == 'Critical':
            severity = 'High'

        details = (
            f"Age: {age}, BP: {bp_systolic}/{bp_diastolic}, "
            f"Temp: {temp:.1f}, HR: {hr}"
        )

        data.append({
            'symptoms': symptoms,
            'details': details,
            'age': age,
            'category': category,
            'severity': severity,
        })
    
    return data


def normalize_category(value):
    """Normalize category labels to the 6 supported classes."""
    if value is None:
        return None

    text = str(value).strip().lower()
    if not text:
        return None

    if text in CATEGORY_ALIASES:
        return CATEGORY_ALIASES[text]

    for category in CATEGORIES:
        if text == category.lower():
            return category

    return None


def normalize_severity(value):
    """Normalize severity labels to Low/Medium/High/Critical."""
    if value is None:
        return None

    text = str(value).strip().lower()
    if not text:
        return None

    if text in SEVERITY_ALIASES:
        return SEVERITY_ALIASES[text]

    for severity in SEVERITY_LEVELS:
        if text == severity.lower():
            return severity

    return None


def parse_age(value):
    """Extract age as integer from flexible inputs (e.g., '45 years')."""
    if value is None:
        return 0

    if isinstance(value, (int, float)):
        return max(int(value), 0)

    text = str(value).strip()
    if not text:
        return 0

    match = re.search(r'\d+', text)
    if not match:
        return 0

    return max(int(match.group(0)), 0)


def _coerce_firestore_value(value):
    """
    Convert Firestore typed JSON values to plain Python values.
    Supports exports that include stringValue/integerValue/mapValue/etc.
    """
    if isinstance(value, list):
        return [_coerce_firestore_value(item) for item in value]

    if not isinstance(value, dict):
        return value

    if 'stringValue' in value:
        return value.get('stringValue')
    if 'integerValue' in value:
        try:
            return int(value.get('integerValue'))
        except Exception:
            return 0
    if 'doubleValue' in value:
        try:
            return float(value.get('doubleValue'))
        except Exception:
            return 0.0
    if 'booleanValue' in value:
        return bool(value.get('booleanValue'))
    if 'nullValue' in value:
        return None
    if 'timestampValue' in value:
        return value.get('timestampValue')
    if 'arrayValue' in value:
        items = value.get('arrayValue', {}).get('values', [])
        return [_coerce_firestore_value(item) for item in items]
    if 'mapValue' in value:
        fields = value.get('mapValue', {}).get('fields', {})
        return {k: _coerce_firestore_value(v) for k, v in fields.items()}
    if 'fields' in value and isinstance(value.get('fields'), dict):
        return {k: _coerce_firestore_value(v) for k, v in value['fields'].items()}

    return {k: _coerce_firestore_value(v) for k, v in value.items()}


def _extract_candidate_records(payload):
    """Get record-like dictionaries from several common JSON export shapes."""
    if isinstance(payload, list):
        return payload

    if isinstance(payload, dict):
        # Firestore export wrapper style
        if isinstance(payload.get('documents'), list):
            return payload['documents']

        # Single record object
        likely_record_keys = {'symptoms', 'details', 'ai_category', 'category', 'ai_severity', 'severity'}
        if likely_record_keys.intersection(set(payload.keys())):
            return [payload]

        # Map keyed by IDs
        dict_values = [value for value in payload.values() if isinstance(value, dict)]
        if dict_values:
            return dict_values

    return []


def _build_details(record, age):
    """Create details text when source data does not already provide it."""
    details = str(record.get('details', '') or '').strip()
    if details:
        return details

    bp_value = record.get('bp') or record.get('bloodPressure') or record.get('blood_pressure')
    temp_value = record.get('temp') or record.get('temperature')
    hr_value = record.get('hr') or record.get('heartRate') or record.get('heart_rate') or record.get('pulse')

    parts = []
    if age > 0:
        parts.append(f"Age: {age}")
    if bp_value:
        parts.append(f"BP: {bp_value}")
    if temp_value:
        parts.append(f"Temp: {temp_value}")
    if hr_value:
        parts.append(f"HR: {hr_value}")

    return ", ".join(parts)


def load_real_training_data(data_file):
    """
    Load real labeled records from a JSON file.
    Required labels per record: category/ai_category and severity/ai_severity.
    """
    with open(data_file, 'r', encoding='utf-8') as f:
        payload = json.load(f)

    candidates = _extract_candidate_records(payload)
    if not candidates:
        raise ValueError(
            f"No records found in {data_file}. Expected a list/dict of records."
        )

    normalized = []
    skipped_unlabeled = 0
    skipped_empty = 0

    for raw in candidates:
        record = _coerce_firestore_value(raw)
        if not isinstance(record, dict):
            continue

        category_raw = record.get('ai_category') or record.get('category') or record.get('diseaseType') or record.get('disease_type')
        severity_raw = record.get('ai_severity') or record.get('severity') or record.get('riskLevel') or record.get('risk_level')

        category = normalize_category(category_raw)
        severity = normalize_severity(severity_raw)
        if category is None or severity is None:
            skipped_unlabeled += 1
            continue

        symptoms = str(record.get('symptoms', '') or '').strip()
        age = parse_age(record.get('age') or record.get('patientAge') or record.get('patient_age'))
        details = _build_details(record, age)

        if not symptoms and not details:
            skipped_empty += 1
            continue

        normalized.append({
            'symptoms': symptoms,
            'details': details,
            'age': age,
            'category': category,
            'severity': severity,
        })

    if not normalized:
        raise ValueError(
            f"No usable labeled records in {data_file}. "
            "Records need category/ai_category and severity/ai_severity."
        )

    print(f"\nLoaded {len(normalized)} labeled records from: {data_file}")
    print(f"Skipped unlabeled records: {skipped_unlabeled}")
    print(f"Skipped empty records: {skipped_empty}")
    print(f"Category distribution: {dict(Counter([r['category'] for r in normalized]))}")
    print(f"Severity distribution: {dict(Counter([r['severity'] for r in normalized]))}")

    return normalized


def extract_features(record):
    """Extract numerical features from health record"""
    features = np.zeros(FEATURE_VECTOR_SIZE, dtype=np.float32)
    
    symptoms = record['symptoms'].lower()
    details = record['details'].lower()
    combined_text = f"{symptoms} {details}"
    
    # Feature 0: Normalized age
    features[0] = record['age'] / 100.0
    
    # Features 1-50: Hashed keyword presence (supports all configured keywords)
    for keyword in FEATURE_KEYWORDS:
        if keyword in combined_text:
            features[_keyword_feature_index(keyword)] = 1.0
    
    # Features 51-54: Vital signs
    bp_match = re.search(r'bp:\s*(\d+)/(\d+)', details)
    if bp_match:
        features[BP_SYSTOLIC_FEATURE_INDEX] = int(bp_match.group(1)) / 200.0
        features[BP_DIASTOLIC_FEATURE_INDEX] = int(bp_match.group(2)) / 150.0
    
    temp_match = re.search(r'temp:\s*(\d+\.?\d*)', details)
    if temp_match:
        features[TEMP_FEATURE_INDEX] = float(temp_match.group(1)) / 42.0
    
    hr_match = re.search(r'hr:\s*(\d+)', details)
    if hr_match:
        features[HR_FEATURE_INDEX] = int(hr_match.group(1)) / 200.0
    
    return features


def build_model(input_shape, num_categories, num_severity_levels):
    """Build multi-output neural network"""
    print("\nBuilding model architecture...")
    
    inputs = tf.keras.Input(shape=(input_shape,), name='input_features')
    
    # Shared layers
    x = tf.keras.layers.Dense(128, activation='relu', name='dense_1')(inputs)
    x = tf.keras.layers.Dropout(0.3)(x)
    x = tf.keras.layers.Dense(64, activation='relu', name='dense_2')(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    x = tf.keras.layers.Dense(32, activation='relu', name='dense_3')(x)
    
    # Category output
    category_output = tf.keras.layers.Dense(
        num_categories,
        activation='softmax',
        name='category_output'
    )(x)
    
    # Severity output
    severity_output = tf.keras.layers.Dense(
        num_severity_levels,
        activation='softmax',
        name='severity_output'
    )(x)
    
    model = tf.keras.Model(
        inputs=inputs,
        outputs=[category_output, severity_output],
        name='health_classifier'
    )
    
    model.compile(
        optimizer='adam',
        loss={
            'category_output': 'sparse_categorical_crossentropy',
            'severity_output': 'sparse_categorical_crossentropy',
        },
        metrics={
            'category_output': ['accuracy'],
            'severity_output': ['accuracy']
        }
    )
    
    return model


def export_portable_web_model(model, category_encoder, severity_encoder):
    """
    Export dense-layer weights to JSON for Flutter Web inference.
    """
    def layer_payload(layer_name):
        layer = model.get_layer(layer_name)
        kernel, bias = layer.get_weights()
        return {
            'kernel': kernel.astype(np.float32).tolist(),
            'bias': bias.astype(np.float32).tolist(),
        }

    portable_model = {
        'format_version': 1,
        'input_size': int(model.input_shape[-1]),
        'category_labels': category_encoder.classes_.tolist(),
        'severity_labels': severity_encoder.classes_.tolist(),
        'feature_keywords': FEATURE_KEYWORDS,
        'keyword_hash': {
            'algorithm': 'fnv1a_32',
            'feature_start_index': KEYWORD_FEATURE_START,
            'bucket_count': KEYWORD_BUCKET_COUNT,
        },
        'vital_feature_indices': {
            'bp_systolic': BP_SYSTOLIC_FEATURE_INDEX,
            'bp_diastolic': BP_DIASTOLIC_FEATURE_INDEX,
            'temperature': TEMP_FEATURE_INDEX,
            'heart_rate': HR_FEATURE_INDEX,
        },
        'category_recovery_guidance': CATEGORY_RECOVERY_GUIDANCE,
        'layers': {
            'dense_1': layer_payload('dense_1'),
            'dense_2': layer_payload('dense_2'),
            'dense_3': layer_payload('dense_3'),
            'category_output': layer_payload('category_output'),
            'severity_output': layer_payload('severity_output'),
        },
    }

    output_path = os.path.join(MODELS_DIR, 'health_classifier_weights.json')
    with open(output_path, 'w') as f:
        json.dump(portable_model, f)

    print(f"\n[OK] Portable web model saved to: {output_path}")
    print(f"Portable model size: {os.path.getsize(output_path) / 1024:.2f} KB")


def train_model(
    data_file=None,
    synthetic_samples=2000,
    augment_synthetic=0,
    epochs=50,
    batch_size=32,
    random_seed=42,
    verify_keywords=None,
):
    """Main training function."""
    print("=" * 60)
    print("Health Classification Model Training")
    print("=" * 60)

    np.random.seed(random_seed)
    tf.random.set_seed(random_seed)

    print(
        f"Keyword feature setup: {len(FEATURE_KEYWORDS)} keywords -> "
        f"{KEYWORD_BUCKET_COUNT} hash buckets"
    )
    _verify_keywords(verify_keywords)

    # Choose training data source
    if data_file:
        data = load_real_training_data(data_file)
        if augment_synthetic > 0:
            synthetic_data = create_synthetic_training_data(
                num_samples=augment_synthetic,
            )
            data.extend(synthetic_data)
            print(
                f"\nAdded {augment_synthetic} synthetic records for augmentation. "
                f"Total training records: {len(data)}"
            )
    else:
        data = create_synthetic_training_data(num_samples=synthetic_samples)

    if len(data) < 20:
        raise ValueError(
            "At least 20 records are recommended for training. "
            f"Current usable records: {len(data)}"
        )
    
    # Extract features and labels
    print("\nExtracting features...")
    X = np.array([extract_features(record) for record in data])
    
    # Encode labels
    category_encoder = LabelEncoder()
    severity_encoder = LabelEncoder()
    
    y_category = category_encoder.fit_transform([r['category'] for r in data])
    y_severity = severity_encoder.fit_transform([r['severity'] for r in data])
    
    # Split data
    X_train, X_test, y_cat_train, y_cat_test, y_sev_train, y_sev_test = train_test_split(
        X, y_category, y_severity, test_size=0.2, random_state=random_seed
    )
    
    print(f"\nTraining set size: {len(X_train)}")
    print(f"Test set size: {len(X_test)}")
    
    # Build model
    model = build_model(
        input_shape=X.shape[1],
        num_categories=len(CATEGORIES),
        num_severity_levels=len(SEVERITY_LEVELS)
    )
    
    print("\nModel Summary:")
    model.summary()
    
    # Train model
    print("\nTraining model...")
    history = model.fit(
        X_train,
        {'category_output': y_cat_train, 'severity_output': y_sev_train},
        validation_data=(
            X_test,
            {'category_output': y_cat_test, 'severity_output': y_sev_test}
        ),
        epochs=epochs,
        batch_size=batch_size,
        verbose=1,
        callbacks=[]
    )
    
    # Evaluate
    print("\nEvaluating model...")
    results = model.evaluate(
        X_test,
        {'category_output': y_cat_test, 'severity_output': y_sev_test},
        return_dict=True,
    )
    print(f"\nTest Results: {results}")
    cat_acc = float(results.get('category_output_accuracy', 0.0)) * 100.0
    sev_acc = float(results.get('severity_output_accuracy', 0.0)) * 100.0
    print(f"Category accuracy: {cat_acc:.2f}%")
    print(f"Severity accuracy: {sev_acc:.2f}%")
    
    # Ensure model output directory exists
    os.makedirs(MODELS_DIR, exist_ok=True)

    # Save encoders
    encoders = {
        'categories': category_encoder.classes_.tolist(),
        'severity_levels': severity_encoder.classes_.tolist(),
        'feature_keywords': FEATURE_KEYWORDS,
        'keyword_hash': {
            'algorithm': 'fnv1a_32',
            'feature_start_index': KEYWORD_FEATURE_START,
            'bucket_count': KEYWORD_BUCKET_COUNT,
        },
        'vital_feature_indices': {
            'bp_systolic': BP_SYSTOLIC_FEATURE_INDEX,
            'bp_diastolic': BP_DIASTOLIC_FEATURE_INDEX,
            'temperature': TEMP_FEATURE_INDEX,
            'heart_rate': HR_FEATURE_INDEX,
        },
        'category_recovery_guidance': CATEGORY_RECOVERY_GUIDANCE,
    }

    encoders_path = os.path.join(MODELS_DIR, 'encoders.json')
    with open(encoders_path, 'w') as f:
        json.dump(encoders, f, indent=2)

    print(f"\n[OK] Encoders saved to: {encoders_path}")

    # Save portable web model weights (pure JSON, no TFLite runtime needed)
    export_portable_web_model(model, category_encoder, severity_encoder)

    # Convert to TensorFlow Lite (optional for native platforms)
    tflite_created = False
    print("\nConverting to TensorFlow Lite...")
    try:
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        tflite_model = converter.convert()

        model_path = os.path.join(MODELS_DIR, 'health_classifier.tflite')
        with open(model_path, 'wb') as f:
            f.write(tflite_model)

        print(f"\n[OK] Model saved to: {model_path}")
        print(f"Model size: {len(tflite_model) / 1024:.2f} KB")
        tflite_created = True
    except Exception as e:
        print(f"\n[WARN] TFLite conversion failed: {e}")
        print("Continuing with portable web model export only.")

    return model, history, tflite_created


def test_model():
    """Test the trained model with sample inputs"""
    print("\n" + "=" * 60)
    print("Testing Model with Sample Inputs")
    print("=" * 60)
    
    # Load model
    model_path = os.path.join(MODELS_DIR, 'health_classifier.tflite')
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    # Test samples
    test_samples = [
        {'symptoms': 'severe chest pain', 'details': 'Age: 55, BP: 180/120', 'age': 55},
        {'symptoms': 'fever and cough', 'details': 'Age: 30, Temp: 38.5', 'age': 30},
        {'symptoms': 'diabetes checkup', 'details': 'Age: 60, BP: 140/90', 'age': 60},
    ]
    
    for i, sample in enumerate(test_samples):
        print(f"\n--- Test Sample {i+1} ---")
        print(f"Symptoms: {sample['symptoms']}")
        print(f"Details: {sample['details']}")
        
        features = extract_features(sample).reshape(1, -1).astype(np.float32)
        
        interpreter.set_tensor(input_details[0]['index'], features)
        interpreter.invoke()
        
        category_probs = interpreter.get_tensor(output_details[0]['index'])[0]
        severity_probs = interpreter.get_tensor(output_details[1]['index'])[0]
        
        category_idx = np.argmax(category_probs)
        severity_idx = np.argmax(severity_probs)
        
        print(f"Predicted Category: {CATEGORIES[category_idx]} ({category_probs[category_idx]*100:.1f}%)")
        print(f"Predicted Severity: {SEVERITY_LEVELS[severity_idx]} ({severity_probs[severity_idx]*100:.1f}%)")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Train and export health classification models.",
    )
    parser.add_argument(
        '--data-file',
        type=str,
        default=None,
        help=(
            "Path to JSON file with real labeled records. "
            "If omitted, synthetic data is used."
        ),
    )
    parser.add_argument(
        '--synthetic-samples',
        type=int,
        default=2000,
        help="Number of synthetic samples when --data-file is not provided.",
    )
    parser.add_argument(
        '--augment-synthetic',
        type=int,
        default=0,
        help=(
            "Number of synthetic samples to add on top of real data. "
            "Useful when the real dataset is small."
        ),
    )
    parser.add_argument(
        '--epochs',
        type=int,
        default=50,
        help="Training epochs.",
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=32,
        help="Training batch size.",
    )
    parser.add_argument(
        '--seed',
        type=int,
        default=42,
        help="Random seed for reproducibility.",
    )
    parser.add_argument(
        '--verify-keyword',
        action='append',
        default=[],
        help=(
            "Keyword to verify before training. "
            "Use multiple times to check multiple keywords."
        ),
    )
    return parser.parse_args()


if __name__ == '__main__':
    args = parse_args()

    # Train the model
    model, history, tflite_created = train_model(
        data_file=args.data_file,
        synthetic_samples=args.synthetic_samples,
        augment_synthetic=args.augment_synthetic,
        epochs=args.epochs,
        batch_size=args.batch_size,
        random_seed=args.seed,
        verify_keywords=args.verify_keyword,
    )
    
    # Test TensorFlow Lite model only when conversion succeeds
    if tflite_created:
        test_model()
    else:
        print("\nSkipping TFLite test because conversion did not succeed.")
    
    print("\n" + "=" * 60)
    print("Training Complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Keep assets/models/health_classifier.tflite for native platforms")
    print("2. Keep assets/models/health_classifier_weights.json for Flutter Web")
    print("3. Ensure pubspec.yaml includes assets/models/")
    print("4. The AI classifier will automatically choose ML when files exist")
    print("=" * 60)
