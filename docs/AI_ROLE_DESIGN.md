# AI and decision-support role design

## Intended purpose

The active web workflow provides decision support, not automated diagnosis or
prescribing. The check-up module sends BHW-entered symptom/condition text to
the authenticated guidance endpoint. That endpoint normalizes the text and
returns human-reviewed supportive-care guidance, precautions, escalation
signs, and an administrative health category that always requires human
review. The historical random-forest artifact is an offline evaluation asset;
it is not presented as a live clinical diagnosis.

## Inputs and outputs

- Inputs: authenticated user scope, BHW-entered symptoms or explicitly entered
  conditions, recorded vitals, and existing clinical record fields.
- BHW output: recognized and unrecognized text, patient-level warning signs,
  supportive-care guidance, referral/escalation prompts, and next steps.
- CHO output: scoped aggregate counts, barangay burden comparisons,
  high-priority and pending-validation counts, data-quality gaps, and planning
  prompts.
- Doctor output: the submitted referral context, urgent flags, and cases that
  still need clinical review. The doctor records the clinical decision.
- Administrator output: availability, provenance, access, and artifact
  verification controls. Patient-level clinical suggestions are not shown in
  the administration view.

Raw model confidence is not displayed as medical certainty. Existing legacy
confidence fields remain readable by compatible APIs but are hidden from web
clinical and reporting interfaces.

## Modules using decision support

- BHW Check-ups: active symptom guidance and saved decision-support fields.
- BHW Dashboard, Analytics, Patient History, Morbidity, and disease views:
  patient-level saved flags and follow-up context.
- BHW/CHO/Doctor Referrals: escalation, assignment support, and submitted case
  context, with role-specific actions.
- CHO Analytics, Dashboard, and scoped workspaces: aggregate operational and
  planning views over submitted records.
- Super Admin: governance and configuration status only.

Every interface labels the output as decision support and requires clinical or
authorized human review before action.
