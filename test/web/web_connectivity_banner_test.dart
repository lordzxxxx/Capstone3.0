import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/widgets/web_connectivity_banner.dart';

void main() {
  test('only a complete lack of network interfaces is reported offline', () {
    expect(
      WebConnectivityBanner.isPotentiallyOnline([ConnectivityResult.none]),
      isFalse,
    );
    expect(
      WebConnectivityBanner.isPotentiallyOnline([
        ConnectivityResult.none,
        ConnectivityResult.wifi,
      ]),
      isTrue,
    );
    expect(
      WebConnectivityBanner.isPotentiallyOnline([ConnectivityResult.ethernet]),
      isTrue,
    );
  });

  test('browser offline state wins over a connected network interface', () {
    expect(
      WebConnectivityBanner.isOnline([
        ConnectivityResult.wifi,
      ], browserOnline: false),
      isFalse,
    );
    expect(
      WebConnectivityBanner.isOnline([
        ConnectivityResult.wifi,
      ], browserOnline: true),
      isTrue,
    );
  });
}
