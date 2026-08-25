import 'package:web/web.dart' as web;

void replaceBrowserHistory(String url) {
  web.window.history.replaceState(null, '', url);
}
