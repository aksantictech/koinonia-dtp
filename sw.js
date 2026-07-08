/* Koinonia — Service Worker (offline-first, app shell)
   Stratégie :
   • App shell (HTML/JS/icônes) en cache-first → l'app s'ouvre hors-ligne.
   • Requêtes Supabase (réseau) en network-first → données fraîches si en ligne,
     repli silencieux géré côté page (mode démo / cache).
   Pour l'offline d'écriture (file d'attente), voir ARCHITECTURE.md (outbox IndexedDB).
*/
const CACHE = 'koinonia-v25';
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

  // Réseau d'abord pour les API (Supabase)
  if (url.hostname.endsWith('supabase.co') || url.pathname.includes('/rest/') || url.pathname.includes('/auth/')) {
    e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
    return;
  }

  // Médias (images, vidéos, polices) : cache d'abord (rapide + hors-ligne)
  if (/\.(png|jpe?g|webp|gif|svg|ico|mp4|webm|woff2?|ttf)$/i.test(url.pathname)) {
    e.respondWith(
      caches.match(e.request).then(c => c || fetch(e.request).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(ch => ch.put(e.request, copy)).catch(() => {});
        return res;
      }))
    );
    return;
  }

  // HTML / JS / le reste : RÉSEAU D'ABORD → toujours la dernière version en ligne,
  // cache seulement en secours (hors-ligne).
  e.respondWith(
    fetch(e.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(ch => ch.put(e.request, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match(e.request).then(c => c || caches.match('./index.html')))
  );
});

/* ---- Notifications push ---- */
self.addEventListener('push', e => {
  let d = { title: 'Dans Sa Présence Church', body: 'Nouvelle publication', kind: '' };
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
  const target = (e.notification.data && e.notification.data.url) || '/index.html';
  e.waitUntil((async () => {
    const list = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    let client = list.find(c => c.url && c.url.indexOf('/index.html') !== -1) || list[0];
    if (client) {
      await client.focus();
      // Dit à la page publique quelle publication ouvrir (marche même si déjà ouverte)
      client.postMessage({ type: 'openpub', url: target });
      // Si la fenêtre ouverte n'est PAS la page publique, on l'y amène
      if ('navigate' in client && (!client.url || client.url.indexOf('/index.html') === -1)) {
        try { await client.navigate(target); } catch (_) {}
      }
      return;
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});
