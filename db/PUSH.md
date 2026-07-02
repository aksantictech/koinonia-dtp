# Activer les notifications push — KOINONIA

La clé publique VAPID est **déjà intégrée** dans `config.js`. Il te reste 2 choses
à faire dans Supabase (une seule fois). Compte ~5 minutes.

Compatibilité : Android/Chrome direct. iPhone : il faut **installer l'app sur
l'écran d'accueil** (Partager → Sur l'écran d'accueil), iOS 16.4+.

────────────────────────────────────────────────────────────────────
## Tes clés VAPID (déjà générées)
- Publique (déjà dans config.js) :
  BF0qOWIELgNYNlMzhSLbSPe62SOoM9HBEeFDEhpS8CLyyVQH5KcxU7R9Hd11GNux-AkOZHImWlIr_JG2bpjzyxs

- Privée (à garder SECRÈTE — ne jamais mettre dans config.js ni sur GitHub) :
  kcDLdRbPQMNU5ByIXXvFoTxZ7FME-mN2crpMJuho0dM
────────────────────────────────────────────────────────────────────

## 1. Enregistrer les secrets + déployer la fonction
Ouvre un terminal dans le dossier du projet (celui qui contient `supabase/`) :

    # une seule fois : installer la CLI si besoin
    npm install -g supabase

    supabase login
    supabase link --project-ref mnfekyswsqvhdvgjfqwx

    # secrets (la clé privée ci-dessus + un email de contact)
    supabase secrets set VAPID_PUBLIC_KEY="BF0qOWIELgNYNlMzhSLbSPe62SOoM9HBEeFDEhpS8CLyyVQH5KcxU7R9Hd11GNux-AkOZHImWlIr_JG2bpjzyxs" VAPID_PRIVATE_KEY="kcDLdRbPQMNU5ByIXXvFoTxZ7FME-mN2crpMJuho0dM" VAPID_SUBJECT="mailto:contact@danstapresence.org"

    # déployer la fonction d'envoi
    supabase functions deploy send-push

(SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement à la fonction.)

## 2. Vérifier la table
La table `push_subscriptions` doit exister — elle est créée par `04b_features.sql`.
Si ce n'est pas encore fait, exécute d'abord 04a puis 04b dans le SQL Editor.

────────────────────────────────────────────────────────────────────
## C'est tout — comment ça marche
1. Un fidèle ouvre la page publique → bouton **🔔 Activer les notifications**
   (son abonnement est enregistré dans `push_subscriptions`).
2. Un pasteur / admin / agent de saisie crée une **publication** avec la case
   « Envoyer une notification » cochée → la fonction `send-push` prévient
   **tous les téléphones abonnés**.

## Dépannage
- Tester l'envoi à la main :
    supabase functions invoke send-push --no-verify-jwt --body '{"title":"Test","body":"Bonjour"}'
- Voir les logs : supabase functions logs send-push
- iPhone : l'app doit être installée sur l'écran d'accueil.
- Les abonnements expirés (404/410) sont nettoyés automatiquement.
