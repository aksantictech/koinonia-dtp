/* Koinonia — Service Worker (offline-first, app shell)
   Stratégie :
   • App shell (HTML/JS/icônes) en cache-first → l'app s'ouvre hors-ligne.
   • Requêtes Supabase (réseau) en network-first → données fraîches si en ligne,
     repli silencieux géré côté page (mode démo / cache).
   Pour l'offline d'écriture (file d'attente), voir ARCHITECTURE.md (outbox IndexedDB).
*/
const CACHE = 'koinonia-v18';
const SHELL = [
  './', './index.html', './dashboard.html', './members.html', './souls.html', './departments.html', './mission.html', './requests.html', './publications.html', './diagnostic.html', './push.js', './config.js',
  './manifest.webmanifest', './icon-192.png', './icon-512.png',
  './logo-circle.png', './logo-mark.png', './pasteur.jpg', './pasteur-portrait.jpg'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Laisser passer tout ce qui est cross-origin (YouTube, CDN, fonts...) sans interférer
  if (url.origin !== location.origin) return;

  // Réseau d'abord pour les API (Supabase) — ne pas servir des données périmées
  if (url.hostname.endsWith('supabase.co') || url.pathname.includes('/rest/') || url.pathname.includes('/auth/')) {
    e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
    return;
  }

  // Cache d'abord pour le shell — ouverture instantanée et hors-ligne
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match('./index.html')))
  );
});

/* ---- Notifications push ---- */
self.addEventListener('push', e => {
  let d = { title: 'Dans Ta Présence Church', body: 'Nouvelle publication', kind: '' };
  try { if (e.data) d = Object.assign(d, e.data.json()); } catch (_) {}
  const icons = { actualite:'📰', activite:'📅', video:'▶', message:'🕊', audio:'🎧' };
  const prefix = icons[d.kind] ? icons[d.kind] + ' ' : '';
  e.waitUntil(self.registration.showNotification(prefix + d.title, {
    body: d.body || '',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    data: { url: d.url || './index.html' }
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const target = (e.notification.data && e.notification.data.url) || './index.html';
  e.waitUntil(clients.matchAll({ type:'window', includeUncontrolled:true }).then(list => {
    for (const c of list) { if ('focus' in c) return c.focus(); }
    if (clients.openWindow) return clients.openWindow(target);
  }));
});
