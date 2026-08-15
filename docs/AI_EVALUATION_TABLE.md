# AI evaluation table

The active product path is Firestore-backed symptom guidance. The Random
Forest metrics below are offline evaluation evidence only and are not clinical
accuracy or diagnostic certainty.

| Evaluation item | Result | Scope/limitation |
| --- | ---: | --- |
| Usable source records | 93,993 | Below the 150,000 project target; no synthetic padding |
| Raw source rows | 96,088 | Structural preprocessing and duplicate handling documented |
| Model classes | 100 | Offline Random Forest artifact only |
| Ordered input features | 228 | Offline Random Forest artifact only |
| Group-safe held-out top-1 | 89.3399% | Agreement with held-out dataset labels |
| Group-safe held-out top-2 | 96.5424% | True label in top two ranked classes |
| Group-safe held-out top-3 | 98.5052% | True label in top three ranked classes |
| Five-fold training-only CV mean | 89.1082% | Robustness estimate, not a replacement for held-out result |
| Exact feature-vector overlap | 0 groups | No exact vector crossed the split |
| Clinical validation | Not established | Qualified reviewer and field testing remain open |

Lowest-recall classes include COPD (54.32%), skin pigmentation disorder
(60.87%), personality disorder (64.42%), noninfectious gastroenteritis
(67.22%), and skin polyp (68.32%). These weaknesses are one reason the
Random Forest remains outside the active `/guidance` product path.

Canonical details: `docs/AI_VALIDATION_REPORT.md` and
`backend/reports/ai_requirements_verification.json`.
