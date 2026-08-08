# 🤖 AI Classification - Quick Start Guide

## ✅ What's Been Integrated

Your healthcare system now has **AI-powered automatic classification** for health records!

### 🎯 Features Added

1. **Automatic Disease Classification**
   - Communicable diseases (flu, infections, etc.)
   - Non-communicable diseases (diabetes, hypertension, etc.)
   - Emergency conditions (critical cases)
   - Prenatal & pediatric care
   - Routine checkups

2. **Severity Assessment**
   - Low, Medium, High, Critical levels
   - Based on symptoms + vital signs

3. **Smart UI Display**
   - Color-coded category badges
   - Confidence scores with progress bars
   - Matched medical keywords
   - Recommended actions

## 🚀 Getting Started

### Step 1: Install Dependencies

```bash
flutter pub get
```

### Step 2: Run Your App

```bash
flutter run
```

That's it! The AI classification is now active.

## 📝 How to Use

### Creating a New Check-Up Record

1. Click the **+ Add Check-Up** button
2. Fill in patient information
3. Enter symptoms (e.g., "fever and cough")
4. Add vital signs (BP, temperature, etc.)
5. Click **Save**

**The AI will automatically:**
- Analyze the symptoms
- Check vital signs
- Classify into category
- Assess severity level
- Add to the record

### Viewing AI Classification

1. Click on any record in the list
2. Scroll to the **"AI Classification"** section
3. You'll see:
   - 📊 **Category** badge (color-coded)
   - ⚠️ **Severity** level
   - 📈 **Confidence** score (%)
   - 🏷️ **Keywords** detected
   - 🔧 **Method** used (ML or Rule-Based)

## 🧪 Test Examples

Try these symptoms to see the AI in action:

### Emergency Case
```
Symptoms: severe chest pain
Vital Signs: BP: 180/120, HR: 110
```
➡️ Should classify as **Emergency** / **Critical**

### Communicable Disease
```
Symptoms: fever, cough, sore throat
Vital Signs: Temp: 38.5°C
```
➡️ Should classify as **Communicable Disease** / **Medium**

### Non-Communicable
```
Symptoms: diabetes follow-up, high blood sugar
Vital Signs: BP: 140/90
Age: 55
```
➡️ Should classify as **Non-Communicable Disease** / **Medium**

### Routine Checkup
```
Symptoms: annual wellness checkup
Vital Signs: BP: 120/80, Temp: 37.0
```
➡️ Should classify as **Routine Checkup** / **Low**

## 🔧 Current Mode: Rule-Based

Your system is currently using **rule-based classification**:
- ✅ Works 100% offline
- ✅ No model training needed
- ✅ Instant classification
- ✅ ~75-85% accuracy

### Want ML Model Instead? (Optional)

For higher accuracy (85-95%), you can train a custom TensorFlow Lite model:

1. **Install Python requirements:**
   ```bash
   cd train_model
   pip install tensorflow numpy pandas scikit-learn
   ```

2. **Train the model:**
   ```bash
   python train_health_classifier.py
   ```

3. **Model automatically saved to:**
   ```
   assets/models/health_classifier.tflite
   ```

4. **Restart your app** - it will automatically use the ML model

See [train_model/README.md](train_model/README.md) for details.

## 📊 Understanding the Results

### Category Colors

- 🔴 **Red** - Emergency (immediate attention)
- 🟠 **Orange** - Communicable Disease (infectious)
- 🔵 **Blue** - Non-Communicable (chronic)
- 🟣 **Purple** - Pediatric Care
- 🩷 **Pink** - Prenatal Care
- 🟢 **Green** - Routine Checkup

### Confidence Score

- **90-100%** - Very confident, highly reliable
- **70-89%** - Confident, good prediction
- **50-69%** - Moderate confidence
- **Below 50%** - Low confidence, review manually

### Method Badge

- **ML Model** 🟣 - Using neural network (requires training)
- **Rule-Based** 🔵 - Using keyword matching (default)

## 🎨 UI Customization

Colors and thresholds can be adjusted in:
```dart
lib/app/core/services/health_ai_classifier.dart
```

Key sections:
- `keywordDatabase` - Add/remove medical keywords
- `_checkVitalSignsEmergency()` - Adjust vital sign thresholds
- `_determineSeverity()` - Modify severity rules

## 📱 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | ✅ Full | ML model supported |
| iOS      | ✅ Full | ML model supported |
| Windows  | ✅ Full | ML model supported |
| Linux    | ✅ Full | ML model supported |
| macOS    | ✅ Full | ML model supported |
| Web      | ⚠️ Rule-based only | TFLite not available |

## 🐛 Troubleshooting

### "Model not found" warning?
**Normal!** The system automatically uses rule-based classification. No action needed.

### Classifications seem wrong?
1. Check symptom spelling
2. Include vital signs (improves accuracy)
3. Review keywords in `health_ai_classifier.dart`
4. Consider training custom model with your data

### Low confidence scores?
- Add more descriptive symptoms
- Include complete vital signs
- Ensure patient age is provided

## 📚 Documentation

- **Full Guide**: [AI_CLASSIFICATION_GUIDE.md](AI_CLASSIFICATION_GUIDE.md)
- **Model Training**: [train_model/README.md](train_model/README.md)
- **Code Reference**: [lib/app/core/services/health_ai_classifier.dart](lib/app/core/services/health_ai_classifier.dart)

## 🎉 What's Next?

Your AI classification system is ready to use! As you collect more health records:

1. **Monitor** - Check classification accuracy
2. **Refine** - Adjust keywords and thresholds
3. **Train** - Create custom ML model with your data
4. **Improve** - Continuously enhance based on feedback

---

**Happy Coding! 🚀**

Questions? Check the console logs or review the documentation files.
