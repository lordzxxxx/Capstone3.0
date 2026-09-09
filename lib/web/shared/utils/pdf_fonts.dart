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
  final fontResults = await Future.wait([
    _loadFontData('Roboto-Regular.ttf'),
    _loadFontData('Roboto-Bold.ttf'),
    _loadFontData('Roboto-Italic.ttf'),
    _loadFontData('Roboto-BoldItalic.ttf'),
  ]);

  return PdfFontBundle(
    base: pw.Font.ttf(fontResults[0]),
    bold: pw.Font.ttf(fontResults[1]),
    italic: pw.Font.ttf(fontResults[2]),
    boldItalic: pw.Font.ttf(fontResults[3]),
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
