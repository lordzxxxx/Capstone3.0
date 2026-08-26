{{flutter_js}}
{{flutter_build_config}}

// Use Flutter's current loader without the deprecated service-worker hook.
// Vercel already serves immutable Flutter assets with long-lived cache headers;
// Firebase Auth/Firestore remain responsible for session and data persistence.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: '/canvaskit/',
  },
});
