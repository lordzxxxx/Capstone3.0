import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart'
    as implementation;

void replaceBrowserHistory(String url) {
  implementation.replaceBrowserHistory(url);
}
