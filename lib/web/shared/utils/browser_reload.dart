import 'browser_reload_stub.dart'
    if (dart.library.js_interop) 'browser_reload_web.dart'
    as implementation;

void reloadBrowserPage() => implementation.reloadBrowserPage();
