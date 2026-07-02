/* KOINONIA — Abonnement aux notifications push (v2, avec messages d'erreur clairs) */
(function () {
  const K = window.KOINONIA;

  function urlB64ToUint8Array(base64) {
    const pad = '='.repeat((4 - base64.length % 4) % 4);
    const b64 = (base64 + pad).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(b64); const arr = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
    return arr;
  }

  // Toujours défini, pour pouvoir renvoyer un message d'erreur précis.
  window.koinoniaEnablePush = async function () {
    if (!('serviceWorker' in navigator) || !('PushManager' in window))
      throw new Error("Ce navigateur ne gère pas les notifications push. Sur iPhone, installe d'abord l'app sur l'écran d'accueil (Partager → Sur l'écran d'accueil), puis rouvre-la.");
    if (!K || !K.VAPID_PUBLIC_KEY)
      throw new Error("Clé VAPID absente (config.js pas à jour dans le cache). Videz le cache et rechargez.");

    const perm = await Notification.requestPermission();
    if (perm !== 'granted')
      throw new Error("Permission des notifications non accordée (état : " + perm + ").");

    const reg = await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlB64ToUint8Array(K.VAPID_PUBLIC_KEY)
      });
    }

    const j = sub.toJSON();
    const sb = K.isConfigured() && K.client();
    if (!sb) throw new Error("Supabase non configuré côté application.");

    const { error } = await sb.from('push_subscriptions').upsert({
      endpoint: j.endpoint,
      p256dh: j.keys && j.keys.p256dh,
      auth: j.keys && j.keys.auth,
      user_agent: navigator.userAgent
    }, { onConflict: 'endpoint', ignoreDuplicates: true });
    if (error) throw new Error("Enregistrement en base échoué : " + (error.message || JSON.stringify(error)));

    return true;
  };

  // Si l'autorisation est déjà accordée, on (ré)enregistre l'abonnement en silence
  if (K && K.VAPID_PUBLIC_KEY && ('serviceWorker' in navigator) && ('PushManager' in window)
      && typeof Notification !== 'undefined' && Notification.permission === 'granted') {
    window.koinoniaEnablePush().catch(function (e) { console.warn('Push auto:', e); });
  }
})();
