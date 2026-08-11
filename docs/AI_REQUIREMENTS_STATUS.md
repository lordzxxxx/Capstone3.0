# AI system requirements status

The machine-readable report at
`backend/reports/ai_requirements_verification.json` is the authoritative
record for counts and metrics. Regenerate it after changing data or model
artifacts:

```bash
python3 backend/scripts/verify_ai_requirements.py
```

The verifier reads the repository's actual files and saved model, reconstructs
the group-safe held-out split, and evaluates the saved artifact. It never
duplicates, pads, relabels, or fabricates records. `--strict` is available for
CI and exits non-zero when either the 150,000-record minimum or 95% accuracy
minimum is not met.

The current run also records row-level provenance, class distribution,
constant/near-zero-variance checks, exact label-conflict groups,
Hamming-distance-one neighborhoods, highest-frequency confusion pairs,
Random Forest feature importance, and held-out probability/coverage behavior.
Near-duplicates are diagnostic findings and are not silently removed.

## Acceptance rules

- The training-record target is 150,000–200,000 valid records. Only real,
  traceable, compatible, licensed or properly consented records count.
- The accuracy target is 95%–98%, with 95% as the minimum. The reported
  number must come from the locked held-out evaluation; cross-validation is a
  robustness check, not a substitute for the held-out result.
- Exact feature-vector groups may not cross the train/test boundary.
- Every `X` input, `y` target, measurement, encoding, source, and quality
  decision must be documented in the generated report.
- ISO alignment refers to documented controls only. The project makes no ISO
  certification claim.

## Current state

Run the verifier to obtain the current numbers. If a target is not met, the
report records `not_met` and the system must not convert a confidence score or
historical experiment into a claim that the target was achieved. The current
repository intentionally keeps the known dataset-scale and accuracy gaps
visible until legitimate additional data and/or additional discriminating
clinical variables are available.

Current verified result: 93,993 usable records, 228 Random Forest inputs,
100 classes, 89.3399% held-out accuracy, 89.1082% five-fold training-only CV
mean accuracy with 0.1136 percentage-point standard deviation, and zero
train/test exact feature-vector overlap. The 150,000-record and 95% gates
remain `not_met`.
