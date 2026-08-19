import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Document capture service for hardcopy clinical records.
///
/// Provides optimized camera and gallery intake with high resolution
/// and automatic orientation handling.
class OcrDocumentScannerService {
  OcrDocumentScannerService._();

  static final ImagePicker _picker = ImagePicker();

  /// Captures a hardcopy document from camera with maximum clarity.
  static Future<File?> scanDocument({ImageSource source = ImageSource.camera}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 3200,
        imageQuality: 100,
      );
      if (image != null) {
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
