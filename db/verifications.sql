-- ============================================================================
-- KOINONIA — Vérifications (à coller dans le SQL Editor, après 04a + 04b)
-- Chaque requête doit renvoyer un résultat "OK". Sinon, relance le SQL manquant.
-- ============================================================================

-- 1) Les rôles saisie & intercession existent-ils ?
SELECT 'Rôles' AS verif,
       bool_or(enumlabel='saisie')       AS a_saisie,
       bool_or(enumlabel='intercession') AS a_intercession
FROM pg_enum WHERE enumtypid = 'app_role'::regtype;
-- attendu : a_saisie = true, a_intercession = true

-- 2) Les tables clés existent-elles ?
SELECT 'Tables' AS verif,
       to_regclass('public.publications')       AS publications,
       to_regclass('public.push_subscriptions') AS push_subscriptions;
-- attendu : deux noms de tables (pas de NULL)

-- 3) Les nouvelles colonnes existent-elles ?
SELECT 'Colonnes' AS verif,
  (SELECT count(*) FROM information_schema.columns WHERE table_name='churches'        AND column_name='is_active')   AS churches_is_active,
  (SELECT count(*) FROM information_schema.columns WHERE table_name='prayer_requests' AND column_name='prayed_at')   AS pr_prayed_at,
  (SELECT count(*) FROM information_schema.columns WHERE table_name='prayer_requests' AND column_name='answered_at') AS pr_answered_at;
-- attendu : 1, 1, 1

-- 4) La vue de statistiques de prière répond-elle ?
SELECT * FROM v_prayer_stats;
-- attendu : une ligne par église (peut être vide si aucune demande)

-- 5) Les règles d'accès (policies) sont-elles créées ?
SELECT policyname, tablename FROM pg_policies
WHERE policyname IN ('pub_read','pub_write','push_insert','push_read',
                     'saisie_members','saisie_departments','saisie_dept_members',
                     'interc_select','interc_update')
ORDER BY tablename, policyname;
-- attendu : 9 lignes

-- 6) L'église mère est-elle bien renommée ?
SELECT name FROM churches WHERE id='11111111-1111-1111-1111-111111111111';
-- attendu : "Dans Ta Présence Church"


-- ============================================================================
-- ATTRIBUTION DES RÔLES (point 1 - étape 3)
-- ============================================================================

-- Voir tous les comptes et leur rôle actuel :
SELECT u.email, p.role
FROM profiles p JOIN auth.users u ON u.id = p.id
ORDER BY u.email;

-- Attribuer un rôle (remplace l'email par le vrai) :
-- UPDATE profiles SET role='saisie'
--  WHERE id = (SELECT id FROM auth.users WHERE email='agent-saisie@exemple.org');

-- UPDATE profiles SET role='intercession'
--  WHERE id = (SELECT id FROM auth.users WHERE email='intercesseur@exemple.org');

-- (Le compte doit d'abord exister : crée-le dans Authentication > Users,
--  ou fais-le s'inscrire, puis exécute le UPDATE ci-dessus.)
