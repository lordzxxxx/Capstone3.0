# Health Model Assets

This directory stores AI model files used by the app.

## Files

1. `health_classifier.tflite`
- Native/mobile/desktop TensorFlow Lite model

2. `health_classifier_weights.json`
- Portable model weights for Flutter Web
- Runs in pure Dart (no TFLite runtime on web)

3. `encoders.json`
- Category and severity label metadata

## Generate / Refresh

Run:

```bash
cd ../train_model
python train_health_classifier.py
```

## Runtime Behavior

- If portable weights are available, the classifier uses `ml_model` mode.
- If model files are missing or invalid, classifier falls back to `rule_based` mode.

## Notes

- Keep `assets/models/` listed in `pubspec.yaml`.
- Web does not use `tflite_flutter`; it uses `health_classifier_weights.json`.
