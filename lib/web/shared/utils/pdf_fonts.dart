import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/widgets.dart' as pw;

class PdfFontBundle {
  final pw.Font base;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  const PdfFontBundle({
    required this.base,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });
}

Future<PdfFontBundle>? _cachedPdfFontBundle;

Future<PdfFontBundle> loadPdfFontBundle() {
  final cached = _cachedPdfFontBundle;
  if (cached != null) {
    return cached;
  }

  final future = _loadPdfFontBundle();
  _cachedPdfFontBundle = future.then(
    (bundle) => bundle,
    onError: (Object error, StackTrace stackTrace) {
      _cachedPdfFontBundle = null;
      throw error;
    },
  );
  return _cachedPdfFontBundle!;
}

Future<PdfFontBundle> _loadPdfFontBundle() async {
  final regularData = await _loadFontData('Roboto-Regular.ttf');
  final boldData = await _loadFontData('Roboto-Bold.ttf');
  final italicData = await _loadFontData('Roboto-Italic.ttf');
  final boldItalicData = await _loadFontData('Roboto-BoldItalic.ttf');

  return PdfFontBundle(
    base: pw.Font.ttf(regularData),
    bold: pw.Font.ttf(boldData),
    italic: pw.Font.ttf(italicData),
    boldItalic: pw.Font.ttf(boldItalicData),
  );
}

Future<ByteData> _loadFontData(String filename) async {
  final assetPath = 'fonts/$filename';
  try {
    return await rootBundle.load(assetPath);
  } catch (error) {
    throw StateError(
      'Unable to load PDF font asset: "$assetPath". Error: $error',
    );
  }
}
