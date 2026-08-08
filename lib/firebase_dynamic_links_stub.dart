// Minimal stub for firebase_dynamic_links to allow building without the package.
// This mirrors only the small subset used by the app: PendingDynamicLinkData,
// FirebaseDynamicLinks.instance.getInitialLink(), and onLink stream.

class PendingDynamicLinkData {
  final Uri? link;
  const PendingDynamicLinkData({this.link});
}

class FirebaseDynamicLinks {
  FirebaseDynamicLinks._();
  static final FirebaseDynamicLinks instance = FirebaseDynamicLinks._();

  Future<PendingDynamicLinkData?> getInitialLink() async => null;

  // Returns an empty stream by default.
  Stream<PendingDynamicLinkData> get onLink => const Stream<PendingDynamicLinkData>.empty();
}
