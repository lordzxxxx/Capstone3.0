import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Document capture service for hardcopy clinical records.
///
/// Provides document-oriented camera and gallery intake with high resolution
/// and automatic orientation handling. Recognition remains review-first: OCR
/// can assist with handwriting, but no captured value is treated as clinical
/// truth without the user confirming it in the form.
class OcrDocumentScannerService {
  OcrDocumentScannerService._();

  static final ImagePicker _picker = ImagePicker();

  /// Captures a hardcopy document from camera with maximum clarity.
  static Future<File?> scanDocument({
    ImageSource source = ImageSource.camera,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        // Preserve enough character detail for small printed labels and
        // handwritten entries while placing a reasonable ceiling on memory.
        maxWidth: 3000,
        maxHeight: 4000,
        imageQuality: 100,
      );
      if (image != null && image.path.trim().isNotEmpty) {
        return File(image.path);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('OcrDocumentScannerService error: $e');
      }
    }
    return null;
  }
}
