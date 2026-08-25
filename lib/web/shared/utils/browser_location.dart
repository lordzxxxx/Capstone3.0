import 'browser_location_stub.dart'
    if (dart.library.js_interop) 'browser_location_web.dart'
    as implementation;

/// Returns the browser path and query for the initial web navigation.
///
/// Native platforms deliberately return `null` through the conditional stub,
/// keeping the mobile startup and routing behavior unchanged.
String? browserLocationRoute() => implementation.browserLocationRoute();
