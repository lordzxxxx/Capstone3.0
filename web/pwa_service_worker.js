'use strict';

const CACHE_NAME = 'aidsuhis-pwa-shell-v1';

// The worker is intentionally limited to the app shell. Firebase Auth,
// Firestore, Storage, Functions, and any future API requests are never cached
// here; their own SDKs remain responsible for persistence and synchronization.
const isShellRequest = (request, url) => {
  if (request.method !== 'GET' || url.origin !== self.location.origin) {
    return false;
  }

  return request.mode === 'navigate' || [
    'script',
    'style',
    'image',
    'font',
    'manifest',
  ].includes(request.destination);
};

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(
        keys
          .filter((key) => key.startsWith('aidsuhis-pwa-shell-') && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (!isShellRequest(event.request, url)) return;

  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put('/index.html', copy));
          }
          return response;
        })
        .catch(() => caches.match('/index.html')),
    );
    return;
  }

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        }
        return response;
      })
      .catch(() => caches.match(event.request)),
  );
});
