import 'package:web/web.dart' as web;

String browserLocationRoute() {
  final location = web.window.location;
  final path = location.pathname.isEmpty ? '/' : location.pathname;
  return '$path${location.search}';
}
