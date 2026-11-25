// Replaces Flutter's service worker after `flutter build web` (bousla deploy).
// Flutter's worker kept a copy of the app on the phone, so after a deploy
// Safari went on showing the previous version. Phones that still have it
// fetch this file on their next visit: it deletes the stored copy,
// unregisters itself and reloads the page once onto the latest version.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k.startsWith('flutter')).map((k) => caches.delete(k)));
    await self.registration.unregister();
    const pages = await self.clients.matchAll({ type: 'window' });
    pages.forEach((page) => page.navigate(page.url));
  })());
});
