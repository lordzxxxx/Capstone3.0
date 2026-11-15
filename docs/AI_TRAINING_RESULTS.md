# AI-DSUHIS Training and Accuracy Results

## Figure-ready title

**Training and Validation Performance Metrics of the Disease Classification Model**

## Important interpretation

The current model is a 200-tree Random Forest, so it does not produce epoch-by-epoch
training and validation curves like a neural-network or YOLO model. The values below
are the recorded five-fold training-only cross-validation results and the final locked,
group-safe held-out evaluation.

The percentages describe agreement with the labels in the local held-out dataset. They
are not clinical accuracy, diagnostic certainty, or evidence of clinical validation.

## Model and dataset

| Item | Value |
| --- | ---: |
| Model | `disease_model_v4` Random Forest |
| Dataset | `merged_dataset_v3` |
| Total records | 93,993 |
| Training records | 75,194 |
| Held-out test records | 18,799 |
| Input features | 228 binary symptom features |
| Disease classes | 100 |
| Split | 5-fold `StratifiedGroupKFold`, grouped by identical feature vector |
| Exact feature-vector overlap between train and test | 0 groups |

## Final held-out evaluation data

Copy this table into a charting application as a percentage bar chart.

```csv
metric,value_percent,correct_or_covered,total,interpretation
Top-1 accuracy,89.3399,16795,18799,Predicted label exactly matched the held-out label
Balanced accuracy,89.6946,,,Mean recall across the 100 disease classes
Weighted precision,89.8701,,,Precision weighted by class support
Weighted recall,89.3399,,,Recall weighted by class support
Weighted F1-score,89.3328,,,F1-score weighted by class support
Macro precision,89.1112,,,Unweighted mean precision across classes
Macro recall,89.6946,,,Unweighted mean recall across classes
Macro F1-score,89.1264,,,Unweighted mean F1-score across classes
Top-2 coverage,96.5424,18149,18799,True label appeared in the two highest-ranked classes
Top-3 coverage,98.5052,18518,18799,True label appeared in the three highest-ranked classes
```

Top-2 and Top-3 are coverage metrics, not ordinary single-label accuracy. They must
not be presented as if the system correctly identified one diagnosis at those rates.

## Five-fold training-only cross-validation data

Use this for a line chart or validation-stability chart.

```csv
fold,accuracy_percent,weighted_f1_percent,macro_f1_percent
Fold 1,89.4075,89.3805,89.1555
Fold 2,89.3019,89.2539,89.0022
Fold 3,88.7958,88.7470,88.5092
Fold 4,88.8756,88.8737,88.6485
Fold 5,89.1601,89.1342,88.8700
Mean,89.1082,89.0778,88.8371
Standard deviation,0.2373,0.2353,0.2336
```

## Dataset split data

```csv
partition,records,percentage_of_total
Training,75194,80.0
Held-out test,18799,20.0
Total,93993,100.0
```

## Suggested figure caption

**Figure 5.1. Training-only cross-validation and held-out evaluation results of the
disease classification model.** The Random Forest was trained using 75,194 records
with 228 binary symptom features covering 100 disease classes. Five-fold,
group-aware cross-validation produced a mean accuracy of 89.1082% (SD = 0.2373%).
On the locked held-out set of 18,799 records, the model achieved 89.3399% Top-1
accuracy, with 96.5424% Top-2 coverage and 98.5052% Top-3 coverage. These results
represent agreement with the available dataset labels and do not establish clinical
validity or diagnostic safety.

## Source files

- `backend/models/training_metrics.json`
- `backend/reports/accuracy_statistics_audit.json`
- `docs/AI_VALIDATION_REPORT.md`
