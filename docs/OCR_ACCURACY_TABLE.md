# OCR accuracy table

## Scope note

No representative set of photographed printed health forms has been collected
and manually labeled in this repository. Therefore, a numeric Google ML Kit
field-accuracy percentage would be fabricated if reported now. The results
below are parser/validation checks, not OCR accuracy measurements.

## Automated behavior evidence

| Scenario | Expected behavior | Evidence | Result |
| --- | --- | --- | --- |
| Explicit labels and varied spacing | Extract name, birth date, contact, email, address | `ocr_extraction_test.dart` | Passed |
| Field order and line breaks vary | Parse by content, not image position | `ocr_extraction_test.dart` | Passed |
| Date and Philippine mobile formats | Normalize to ISO date and local mobile format | `ocr_extraction_test.dart` | Passed |
| Missing/implicit labels | Use conservative context parsing | `ocr_extraction_test.dart` | Passed |
| Invalid email or implausible age | Require manual review and do not seed invalid value | `ocr_extraction_test.dart` | Passed |
| Low ML Kit line confidence | Force manual review below 0.75 | `ocr_extraction_test.dart` | Passed |
| Empty/unreadable text | Return no fields and zero confidence | `ocr_extraction_test.dart` | Passed |
| OCR action entry point | Expose OCR and manual creation choices | `ocr_record_action_test.dart` | Passed |

## Field-study table for completion before final defense

| Form/module | Labeled images | Fields labeled | Correct fields | Field accuracy | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| Patient registration | — | — | — | — | Collect real printed forms |
| Check-up | — | — | — | — | Collect real printed forms |
| Prenatal | — | — | — | — | Collect real printed forms |
| Immunization | — | — | — | — | Collect real printed forms |
| Surveillance records | — | — | — | — | Collect real printed forms |

Recommended calculation after collection: `correctly extracted labeled fields /
all labeled fields`, reported per field and per form, with unreadable fields
counted separately. Do not use parser unit-test pass rates as OCR accuracy.
