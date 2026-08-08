import 'dart:js_interop';

@JS('Swal.fire')
external JSPromise<_SweetAlertResult> _showSweetAlert(JSObject options);

@JS()
extension type _SweetAlertResult._(JSObject _) implements JSObject {
  external bool? get isConfirmed;
}

Future<bool> showLoginSuccessSweetAlert({
  required String title,
  required String message,
  required String confirmButtonText,
}) async {
  try {
    final options =
        <String, Object?>{
              'title': title,
              'text': message,
              'icon': 'success',
              'confirmButtonText': confirmButtonText,
              'confirmButtonColor': '#00A8B5',
              'background': '#0E2F34',
              'color': '#F5F5F5',
              'backdrop': 'rgba(6, 25, 32, 0.82)',
              'allowOutsideClick': false,
              'allowEscapeKey': false,
            }.jsify()
            as JSObject;
    final result = await _showSweetAlert(options).toDart;
    return result.isConfirmed ?? true;
  } catch (_) {
    return true;
  }
}
