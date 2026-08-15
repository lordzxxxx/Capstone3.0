# Defense scope matrix

## Required demonstration scope

1. Authenticated BHW sign-in and role-aware navigation.
2. Patient/check-up record creation with OCR review and normal validation.
3. Mobile offline save behavior and synchronization evidence.
4. Non-prescriptive `/guidance` response with disclaimer and emergency
   referral wording, or the safe unavailable state when the staging service is
   intentionally stopped.
5. BHW → CHO → doctor referral and continuity-of-care workflow.

## Supporting evidence, not a live product claim

- Group-safe Random Forest top-1/top-2/top-3 evaluation metrics.
- Firestore rules emulator and backend test results.
- OCR parser unit tests and the real-form accuracy-study plan.
- Architecture, security, and limitation documents.

## Explicitly optional or out of final product scope

- The disabled `/predict` disease-probability endpoint.
- The portable model as a production clinical model.
- iOS field testing if the team confirms Android-only scope.
- Live production AI hosting until the Firebase/App Check and qualified
  review gates are closed.

This scope keeps the defense centered on usable records, safe guidance,
offline resilience, and role workflow instead of unsupported model claims.
