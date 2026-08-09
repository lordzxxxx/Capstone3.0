import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

typedef OcrRecordCallback = Future<void> Function(String recognizedText);

/// Shared mobile record actions. OCR is intentionally an assistive workflow;
/// the existing manual forms remain the source of truth for validation.
class RecordCreationFabGroup extends StatelessWidget {
  const RecordCreationFabGroup({
    super.key,
    required this.moduleLabel,
    required this.manualLabel,
    required this.onManualCreate,
    this.onOcrReady,
    this.accentColor = AppDesign.blue,
    this.foregroundColor = Colors.white,
  });

  final String moduleLabel;
  final String manualLabel;
  final VoidCallback onManualCreate;
  final OcrRecordCallback? onOcrReady;
  final Color accentColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'ocr-$moduleLabel',
          onPressed: () => OcrRecordCapture.start(
            context: context,
            moduleLabel: moduleLabel,
            onOcrReady: onOcrReady ?? (_) async => onManualCreate(),
          ),
          backgroundColor: AppDesign.navy,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('OCR'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'manual-$moduleLabel',
          onPressed: onManualCreate,
          backgroundColor: accentColor,
          foregroundColor: foregroundColor,
          icon: const Icon(Icons.add),
          label: Text(manualLabel),
        ),
      ],
    );
  }
}

class OcrRecordButton extends StatelessWidget {
  const OcrRecordButton({
    super.key,
    required this.moduleLabel,
    required this.onOcrReady,
    this.expanded = true,
  });

  final String moduleLabel;
  final OcrRecordCallback onOcrReady;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: () => OcrRecordCapture.start(
        context: context,
        moduleLabel: moduleLabel,
        onOcrReady: onOcrReady,
      ),
      icon: const Icon(Icons.document_scanner_outlined),
      label: const Text('Create with OCR'),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class OcrRecordCapture {
  OcrRecordCapture._();

  static Future<void> start({
    required BuildContext context,
    required String moduleLabel,
    required OcrRecordCallback onOcrReady,
  }) async {
    if (kIsWeb) {
      _message(
        context,
        'On-device OCR is available in the Android and iOS mobile app.',
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppDesign.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$moduleLabel OCR',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                'Scan a clear printed form or choose an existing image.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppDesign.blue,
                ),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppDesign.blue,
                ),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    var loadingDialogVisible = false;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 92,
      );
      if (image == null || !context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppDesign.blue),
        ),
      );
      loadingDialogVisible = true;

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      late final String recognizedText;
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        recognizedText = result.text.trim();
      } finally {
        await recognizer.close();
      }
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingDialogVisible = false;
      if (recognizedText.isEmpty) {
        _message(
          context,
          'No readable text was detected. Retake the photo in better lighting.',
        );
        return;
      }
      await _review(
        context: context,
        moduleLabel: moduleLabel,
        recognizedText: recognizedText,
        onOcrReady: onOcrReady,
      );
    } catch (_) {
      if (!context.mounted) return;
      if (loadingDialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _message(context, 'OCR could not read this image. Please try again.');
    }
  }

  static Future<void> _review({
    required BuildContext context,
    required String moduleLabel,
    required String recognizedText,
    required OcrRecordCallback onOcrReady,
  }) async {
    final controller = TextEditingController(text: recognizedText);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: AppDesign.page,
        child: Scaffold(
          backgroundColor: AppDesign.page,
          appBar: AppBar(
            title: Text('Review $moduleLabel OCR'),
            leading: IconButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppDesign.blueSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Verify all extracted text before saving. OCR assists data entry and does not validate clinical information.',
                      style: TextStyle(color: AppDesign.muted, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(color: AppDesign.ink),
                      decoration: const InputDecoration(
                        labelText: 'Recognized text',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Continue to new record'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final editedText = controller.text.trim();
    controller.dispose();
    if (accepted != true || editedText.isEmpty || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: editedText));
    await onOcrReady(editedText);
    if (context.mounted) {
      _message(
        context,
        'OCR text copied. Verify it while completing the new record.',
      );
    }
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppDesign.navy),
    );
  }
}
