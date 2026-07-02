# Mise en place — Point 1 : consolider l'existant

Objectif : passer de « ça marche en démo » à « ça marche pour de vrai ».
Suis les étapes dans l'ordre. Compte 20–30 min. Coche au fur et à mesure.

---

## Étape A — Base de données (le socle)

1. Ouvre **Supabase → SQL Editor**.
2. Exécute les fichiers **dans cet ordre**, un par un (colle → Run) :
   - `db/01_schema.sql`   (si pas déjà fait)
   - `db/02_seed.sql`     (données de démo — facultatif en production)
   - `db/03_updates.sql`
   - `db/04a_roles.sql`   ← **seul, en premier** (ajoute les rôles)
   - `db/04b_features.sql` ← ensuite (tables, colonnes, règles)
3. Colle `db/verifications.sql` et exécute-le : chaque bloc doit renvoyer un
   résultat « OK » (détails dans le fichier). Si une croix apparaît, c'est que
   le fichier correspondant n'a pas été exécuté.

> ⚠️ Si tu vois l'erreur *"unsafe use of new value 'saisie'"*, c'est que tu as
> lancé 04a et 04b **ensemble**. Lance `04a_roles.sql` SEUL d'abord, puis `04b`.

---

## Étape B — Vérifier dans l'application (le plus simple)

1. Déploie la dernière version (réextrais le ZIP, vide le cache, `vercel --prod`).
2. Connecte-toi avec le compte pasteur, puis ouvre **`/diagnostic.html`**
   (ou menu **Plus → 🔧 Diagnostic**).
3. La page teste tout automatiquement :
   - ✅ vert partout = base OK.
   - ❌ rouge sur une table/colonne = un SQL manque (retour Étape A).
   - ⚠️ orange sur le push = normal tant que l'Étape D n'est pas faite.
4. Teste ensuite à la main :
   - **Publications** : crée une actualité → elle doit apparaître sur la page publique (section « Actualités »).
   - **Départements** : ajoute / modifie / désactive un département.
   - **Mission** : ajoute / modifie / désactive une implantation.
   - **Demandes de prière** : marque une demande « Prière faite » puis « Exaucée »
     → le compteur d'intercession bouge sur le tableau de bord.

---

## Étape C — Les deux nouveaux rôles

1. Crée les comptes dans **Supabase → Authentication → Users** (ou fais-les s'inscrire).
2. Dans le **SQL Editor**, attribue le rôle (voir la fin de `verifications.sql`) :
   ```sql
   UPDATE profiles SET role='saisie'
     WHERE id = (SELECT id FROM auth.users WHERE email='agent-saisie@exemple.org');

   UPDATE profiles SET role='intercession'
     WHERE id = (SELECT id FROM auth.users WHERE email='intercesseur@exemple.org');
   ```
3. Vérifie que chacun ne voit que ce qu'il doit :
   - **saisie** : accède à Membres, Départements, Publications, affectation des âmes.
   - **intercession** : dans « Demandes », ne voit **que** l'onglet Prières.

---

## Étape D — Notifications push (bout en bout)

1. Suis `db/PUSH.md` (clés déjà générées) : `supabase secrets set …` puis
   `supabase functions deploy send-push`.
2. Sur un téléphone : page publique → **🔔 Activer les notifications**
   (iPhone : installe d'abord l'app sur l'écran d'accueil).
3. Crée une publication avec « Envoyer une notification » cochée → le téléphone
   doit recevoir l'alerte.
4. Relance `/diagnostic.html` : la ligne « Fonction send-push » doit passer au vert.

---

## Quand tout est vert
Le point 1 est bouclé : on peut attaquer le **module Dons (mobile money)**.
