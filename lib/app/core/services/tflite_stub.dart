// Stub for TensorFlow Lite on web platform
// TFLite is not supported on web, so we provide empty stubs

/// Stub class for Interpreter when running on web
class Interpreter {
  static Future<Interpreter> fromAsset(String assetName) async {
    throw UnsupportedError('TensorFlow Lite is not supported on web platform');
  }

  void runForMultipleInputs(List inputs, Map<int, Object> outputs) {
    throw UnsupportedError('TensorFlow Lite is not supported on web platform');
  }

  void close() {
    // No-op on web
  }
}
