import 'login_success_sweet_alert_stub.dart'
    if (dart.library.html) 'login_success_sweet_alert_web.dart' as impl;

Future<bool> showLoginSuccessSweetAlert({
  required String title,
  required String message,
  required String confirmButtonText,
}) {
  return impl.showLoginSuccessSweetAlert(
    title: title,
    message: message,
    confirmButtonText: confirmButtonText,
  );
}
