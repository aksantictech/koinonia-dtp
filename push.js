/* KOINONIA — Abonnement aux notifications push
   Nécessite window.KOINONIA.VAPID_PUBLIC_KEY (voir db/PUSH.md).
   Tant que la clé n'est pas définie, ce script ne fait rien (silencieux). */
(function () {
  const K = window.KOINONIA;
  if (!K || !K.VAPID_PUBLIC_KEY || !('serviceWorker' in navigator) || !('PushManager' in window)) return;

  function urlB64ToUint8Array(base64) {
    const pad = '='.repeat((4 - base64.length % 4) % 4);
    const b64 = (base64 + pad).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(b64); const arr = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
    return arr;
  }

  window.koinoniaEnablePush = async function () {
    try {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') return false;
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
      if (sb) {
        await sb.from('push_subscriptions').upsert({
          endpoint: j.endpoint,
          p256dh: j.keys && j.keys.p256dh,
          auth: j.keys && j.keys.auth,
          user_agent: navigator.userAgent
        }, { onConflict: 'endpoint', ignoreDuplicates: true });
      }
      return true;
    } catch (e) { console.warn('Push:', e); return false; }
  };

  // Si déjà autorisé, on (ré)enregistre l'abonnement en silence
  if (Notification.permission === 'granted') window.koinoniaEnablePush();
})();
