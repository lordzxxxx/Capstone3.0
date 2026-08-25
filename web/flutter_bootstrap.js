{{flutter_js}}
{{flutter_build_config}}

// Flutter 3.44 no longer ships a durable offline worker by default. Keep the
// PWA shell worker explicit so its scope and cache policy stay reviewable.
_flutter.loader.load({
  serviceWorkerSettings: {
    // Use an origin-root URL so deep links such as /bhw/login do not resolve
    // the worker against /bhw/pwa_service_worker.js and receive index.html.
    serviceWorkerUrl: '/pwa_service_worker.js',
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
