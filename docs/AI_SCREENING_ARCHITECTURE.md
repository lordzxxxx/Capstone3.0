# AI-DSUHIS structured screening architecture

## Purpose

AI-DSUHIS uses AI-assisted processing for data-quality checks, deterministic
screening support, explainable warnings, referral decision support, and scoped
health-information summaries. The screening result is not a diagnosis, a
treatment plan, a prescription, or an autonomous clinical decision.

The BHW verifies the recorded information, reviews the result, and decides
whether to continue the normal workflow or open the existing referral flow.
Nothing in the screening engine submits a referral automatically.

## Runtime flow

```text
Manual form or verified record input
        -> HealthScreeningEngine.evaluate
        -> HealthScreeningResult
        -> BHW review / existing referral workflow
        -> persisted check-up or prenatal record
        -> scoped BHW or CHO aggregate insights
```

Recorded values must go through the existing field verification and form
validation before screening runs. A network failure in the separate
symptom-guidance service does not prevent the record from being saved with the
local structured screening result.

## Source of truth

The implementation is in
`lib/app/core/services/health_screening_engine.dart`. Its result is stored in
the existing `ai_recovery_plan.structured_screening` map so existing SQLite and
Firestore storage continue to work without a migration. Older recovery-plan
fields and the reviewed symptom-guidance response remain intact.

`HealthScreeningResult` contains:

- screening status and data-quality state
- evaluated measurements
- recorded values, reasons, and suggested actions for each finding
- warnings and missing information
- referral recommendation and reasons
- rule version, timestamp, source, and human-review requirement

Analytics consume persisted structured results. They do not silently
re-evaluate historical raw records, and actual referrals are counted and
displayed separately from AI referral suggestions.

## Conservative rules

The current rule version is `who-iitt-aha-screening-v1`.

- Adult high-risk screening values and emergency warning signs are based on
  WHO Integrated Interagency Triage Tool guidance.
- Pediatric respiratory-rate context uses the age bands implemented from WHO
  pediatric emergency triage guidance. Adult thresholds are not applied to
  children for heart rate, and age is required for respiratory-rate context.
- Adult blood-pressure categories and severe-range handling are based on the
  American Heart Association categories. A severe reading with concerning
  symptoms is escalated for urgent professional assessment; a reading without
  those symptoms is presented for timely professional review.
- Pregnancy-specific escalation is used only when pregnancy context is
  explicit (the prenatal workflow supplies that context).

References:

- [WHO Integrated Interagency Triage Tool for adults](https://cdn.who.int/media/docs/default-source/integrated-health-services-%28ihs%29/csy/iitt/iitt_adult.pdf)
- [WHO triage and treatment for children](https://cdn.who.int/media/docs/default-source/integrated-health-services-%28ihs%29/csy/iitt/triage-and-treatment_pediatric.pdf)
- [WHO emergency triage overview](https://www.who.int/tools/triage)
- [American Heart Association blood-pressure categories](https://www.heart.org/en/health-topics/high-blood-pressure/blood-pressure-explained)

These sources inform screening thresholds; they do not make the application
clinically validated. The engine must be reviewed by the responsible health
professionals before operational adoption, and the UI keeps that limitation
visible.

## Safety boundaries

- Invalid, negative, impossible, or unsupported-unit measurements become data
  quality issues and are not promoted to clinical urgency.
- Missing age or other required context produces a professional-review state;
  the engine does not guess a pediatric or adult interpretation.
- Normal-looking readings are described as `WITHIN EXPECTED RANGE`, never as a
  statement that a person is healthy.
- The disabled legacy disease-prediction endpoint and experimental portable ML
  artifact remain disabled. Deterministic screening is used because its output
  can be explained and reviewed.
- Existing Firebase Authentication, App Check, Firestore scope rules, and
  referral permissions are unchanged. BHW screens remain barangay-scoped and
  CHO insight panels use the already-authorized aggregate query scope.
