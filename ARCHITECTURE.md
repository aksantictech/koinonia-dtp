# Architecture technique — Koinonia / Dans Ta Présence Church

Ce document tranche les trois décisions que vous avez signalées comme importantes : **le socle backend (Nest vs Django)**, **la stratégie offline**, **la stratégie SMS**, et trace le **chemin vers l'APK**.

---

## 1. Décision backend : **Supabase-first**, pas de monolithe Nest/Django

**Verdict : on ne construit ni serveur NestJS ni serveur Django comme backend principal. Supabase EST le backend.**

Supabase fournit, sans serveur à maintenir :
- **PostgreSQL** (la base que vous venez de créer) ;
- **Auth** (email/mot de passe, OTP, magic link) → les rôles RBAC vivent dans `profiles.role` ;
- **RLS** (sécurité par ligne) → déjà écrite dans le schéma, c'est elle qui protège chaque âme ;
- **Storage** (photos de membres, documents, audios de témoignage) ;
- **Realtime** (le dashboard se met à jour en direct quand un converti est enregistré) ;
- **Edge Functions** (TypeScript/Deno) pour la logique sur-mesure : envoi SMS, génération de rapports, QR ;
- **pg_cron** pour les tâches planifiées (job anti-décrochage déjà écrit : `enqueue_followup_sms`).

Cela couvre ~90 % des besoins des 5 modules **sans aucun serveur applicatif à héberger** — décisif pour une église qui n'a pas d'équipe DevOps dédiée.

### Et si un jour il faut un vrai serveur ? → alors **NestJS, pas Django**
Le seul cas qui justifierait un service applicatif séparé : intégrations lourdes (comptabilité externe, batchs financiers complexes, moteur de rapports PDF volumineux). Dans ce cas, on choisit **NestJS (Node/TypeScript)** pour une raison simple et décisive :

> **Une seule langue sur toute la pile.** Le frontend (React), les Edge Functions Supabase (Deno/TS) et le futur backend seraient tous en **TypeScript**. Un seul vivier de compétences, des **types partagés** entre client et serveur, zéro friction. Django (Python) introduirait une deuxième langue et casserait cette unité.

**Résumé de la décision :** Supabase d'abord → Edge Functions (TS) pour le sur-mesure → NestJS (TS) seulement si un service dédié devient nécessaire. Django est écarté ici par cohérence de pile.

---

## 2. Stratégie offline (indispensable RDC + campagnes terrain)

Un ouvrier enregistre un nouveau converti pendant une campagne, **sans réseau**. Cas non négociable.

### Deux niveaux

**a) Lecture hors-ligne — déjà en place.**
Le `service worker` (`sw.js`) met en cache l'« app shell ». L'application **s'ouvre sans connexion** et réaffiche les dernières données vues.

**b) Écriture hors-ligne — pattern « outbox » (file d'attente locale).**
Les écritures (inscription visiteur, check-in présence, note de suivi) sont d'abord stockées **en local dans IndexedDB**, puis **synchronisées** dès le retour du réseau.

```js
// outbox.js — esquisse du pattern à intégrer dans l'app
import { openDB } from 'idb';
const db = await openDB('koinonia', 1, {
  upgrade(d){ d.createObjectStore('outbox', { keyPath:'id', autoIncrement:true }); }
});

// 1) On écrit toujours en local d'abord
export async function queueWrite(table, row){
  await db.add('outbox', { table, row, ts: Date.now() });
  if (navigator.onLine) flush();
}

// 2) Quand le réseau revient, on vide la file vers Supabase
export async function flush(){
  const all = await db.getAll('outbox');
  for (const item of all){
    const { error } = await supabase.from(item.table).insert(item.row);
    if (!error) await db.delete('outbox', item.id);   // sinon on réessaiera
  }
}
window.addEventListener('online', flush);
```

**Conflits :** *last-write-wins* sur l'horodatage serveur. Les doublons de présence sont déjà bloqués par la contrainte `unique (member_id, service_date, event_kind)` du schéma — un même check-in rejoué hors-ligne ne crée pas de doublon.

**Pour aller plus loin (option) :** si vous voulez une vraie synchro bidirectionnelle robuste, **PowerSync** s'intègre nativement à Supabase et gère la réplication locale. Recommandé seulement quand le volume terrain le justifie ; l'outbox suffit pour démarrer.

---

## 3. Stratégie SMS (atteindre ceux qui n'ont pas de smartphone)

Tous les membres n'ont pas l'application. Le **SMS** garantit que l'alerte atteint le conseiller, que la confirmation atteint le visiteur.

### Passerelle
- **Primaire : Africa's Talking** — meilleure couverture et tarification en RDC / Afrique.
- **Secours / diaspora : Twilio** — pour l'Europe (Paris, Bruxelles).

### Architecture (déjà câblée dans la base)
1. `pg_cron` lance chaque matin `enqueue_followup_sms()` → repère les âmes sans contact et **remplit la table `notifications_outbox`**.
2. Une **Edge Function** lit les SMS `en_attente`, appelle la passerelle, met à jour le statut.

```ts
// supabase/functions/send-sms/index.ts  (Deno)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supa = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const AT_KEY = Deno.env.get('AT_API_KEY')!;
const AT_USER = Deno.env.get('AT_USERNAME')!;

const templates: Record<string,(p:any)=>string> = {
  followup: p => `Bonjour, ${p.soul} n'a pas été contacté(e) depuis ${p.days} jours. Merci de prendre des nouvelles. — DTP Church`,
  welcome:  p => `Bienvenue ${p.name} à Dans Ta Présence Church ! Nous sommes heureux de vous accueillir.`,
};

Deno.serve(async () => {
  const { data: pending } = await supa.from('notifications_outbox')
    .select('*').eq('channel','sms').eq('status','en_attente').limit(50);

  for (const n of pending ?? []) {
    const body = templates[n.payload.template]?.(n.payload) ?? n.payload.text;
    const res = await fetch('https://api.africastalking.com/version1/messaging', {
      method:'POST',
      headers:{ 'apiKey':AT_KEY, 'Content-Type':'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ username:AT_USER, to:n.recipient, message:body })
    });
    await supa.from('notifications_outbox')
      .update({ status: res.ok ? 'envoye':'echec', attempts:(n.attempts??0)+1, sent_at:new Date().toISOString() })
      .eq('id', n.id);
  }
  return new Response('ok');
});
```

Déploiement : `supabase functions deploy send-sms`, puis planifier son appel via `pg_cron` (ou un cron Supabase) toutes les 5 min.

**SMS entrant (bonus) :** un webhook de la passerelle → Edge Function → on enregistre la réponse comme une `interaction` (kind = `sms`), ce qui met à jour `last_contact_at` et éteint l'alerte. La boucle de suivi se referme.

**Usages SMS :** alerte anti-décrochage (auto), confirmation d'inscription visiteur, rappel d'événement, relance de baptême.

---

## 4. Du web à l'**APK** : un seul code, deux sorties

L'application est une **PWA** (manifest + service worker, déjà fournis). Deux chemins vers le `.apk` :

### Recommandé — **Capacitor** (accès natif : caméra QR + notifications push)
```bash
npm i @capacitor/core @capacitor/cli @capacitor/android
npx cap init "DTP Church" cd.dtpchurch.app --web-dir=app
npx cap add android
npx cap copy
npx cap open android      # ouvre Android Studio → Build > Build APK(s)
```
Capacitor encapsule **exactement** les fichiers de `app/` dans une coque Android. Le scan QR (cartes de membre) et les notifications push passent par les plugins `@capacitor/camera` et `@capacitor/push-notifications`. Le même projet produit aussi l'app iOS.

### Plus léger — **TWA / Bubblewrap** (si pas besoin de natif)
```bash
npm i -g @bubblewrap/cli
bubblewrap init --manifest https://votredomaine.org/manifest.webmanifest
bubblewrap build           # produit l'APK signé pour le Play Store
```
La PWA déployée (HTTPS) devient une APK « Trusted Web Activity ». Idéal pour publier vite la page publique + le dashboard.

**Conseil :** démarrez en **TWA** pour livrer l'APK rapidement, basculez sur **Capacitor** quand le scan QR natif devient nécessaire.

---

## 5. Mise en route (ordre des opérations)

1. **Créer le projet Supabase** (supabase.com).
2. **SQL Editor** → coller et exécuter `db/01_schema.sql`, puis `db/02_seed.sql`.
3. **Settings ▸ API** → copier l'URL et la clé `anon public` dans `app/config.js`.
4. Ouvrir `app/index.html` (page publique) et `app/dashboard.html` → ils passent en **DONNÉES LIVE**.
5. **Créer un compte pasteur** : Authentication ▸ Users ▸ Add user, puis dans SQL :
   `update profiles set role='pasteur_titulaire', church_id='11111111-1111-1111-1111-111111111111' where id='<user_id>';`
6. Se connecter via le dashboard (encart « Connexion ») → le tableau de bord lit les vraies vues.
7. (Plus tard) Déployer les Edge Functions SMS, planifier `pg_cron`, packager l'APK.

---

## 6. Carte des fichiers livrés

```
db/
  01_schema.sql      ← base complète : 5 modules, RLS, vues Module 1, triggers
  02_seed.sql        ← données de démo (4 820 membres, présences, vision…)
app/
  index.html         ← PAGE PUBLIQUE (accueil, visiteur, prière, témoignages)
  dashboard.html     ← MODULE 1 : tableau de bord pastoral (live + démo)
  config.js          ← vos clés Supabase
  manifest.webmanifest, sw.js, icon-*.png  ← PWA → APK
ARCHITECTURE.md      ← ce document
```

Tout est connecté : la page publique **écrit** dans Supabase (visiteurs → entonnoir des âmes, prières, témoignages) ; le dashboard **lit** les vues qui agrègent ces mêmes données. Une âme enregistrée à l'accueil apparaît dans le « Parcours de l'âme » du pasteur.
