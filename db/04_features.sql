-- ============================================================================
-- KOINONIA — Migration 04 : nouveaux rôles, publications, intercession, push
-- À EXÉCUTER APRÈS 01_schema.sql, 02_seed.sql, 03_updates.sql
-- ============================================================================

-- ── 1. NOUVEAUX RÔLES ───────────────────────────────────────────────────────
-- saisie        : saisit membres, départements, publications, affecte les âmes
-- intercession  : gère uniquement les demandes de prière
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'saisie';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'intercession';

-- Renommer l'église mère (cohérence d'affichage)
UPDATE churches SET name = 'Dans Ta Présence Church'
 WHERE id = '11111111-1111-1111-1111-111111111111';

-- ── 2. ÉGLISES : activation/désactivation (Mission) ─────────────────────────
ALTER TABLE churches ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

-- ── 3. INTERCESSION : suivi de la prière ────────────────────────────────────
ALTER TABLE prayer_requests ADD COLUMN IF NOT EXISTS prayed_at        timestamptz;
ALTER TABLE prayer_requests ADD COLUMN IF NOT EXISTS prayed_by        uuid REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE prayer_requests ADD COLUMN IF NOT EXISTS answered_at      timestamptz;
ALTER TABLE prayer_requests ADD COLUMN IF NOT EXISTS intercessor_note text;

-- Vue de statistiques de prière (pour le tableau de bord du pasteur)
CREATE OR REPLACE VIEW v_prayer_stats
WITH (security_invoker = true) AS
SELECT church_id,
       count(*) FILTER (WHERE status = 'en_attente') AS waiting,
       count(*) FILTER (WHERE status = 'en_priere')  AS praying,
       count(*) FILTER (WHERE status = 'exauce')     AS answered
FROM prayer_requests
GROUP BY church_id;

-- ── 4. PUBLICATIONS (actualités, activités, vidéos, messages, audio) ─────────
DO $$ BEGIN
  CREATE TYPE pub_kind AS ENUM ('actualite','activite','video','message','audio');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS publications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id    uuid REFERENCES churches(id) ON DELETE CASCADE,
  kind         pub_kind NOT NULL DEFAULT 'actualite',
  title        text NOT NULL,
  body         text,
  media_url    text,            -- lien vidéo/audio (YouTube, mp3, ...)
  image_url    text,            -- vignette éventuelle
  is_published boolean NOT NULL DEFAULT true,
  published_at timestamptz DEFAULT now(),
  created_by   uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS publications_church_idx ON publications(church_id, published_at DESC);

ALTER TABLE publications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pub_read   ON publications;
DROP POLICY IF EXISTS pub_write  ON publications;
-- Lecture publique des publications publiées (page publique + app)
CREATE POLICY pub_read ON publications FOR SELECT TO anon, authenticated
  USING (is_published = true OR my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie'));
-- Écriture : pasteurs, admin et saisie
CREATE POLICY pub_write ON publications FOR ALL TO authenticated
  USING      (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie'))
  WITH CHECK (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie'));

-- ── 5. ABONNEMENTS PUSH (notifications navigateur / app) ─────────────────────
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint   text UNIQUE NOT NULL,
  p256dh     text,
  auth       text,
  user_id    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS push_insert ON push_subscriptions;
DROP POLICY IF EXISTS push_read   ON push_subscriptions;
-- N'importe quel visiteur peut enregistrer son abonnement
CREATE POLICY push_insert ON push_subscriptions FOR INSERT TO anon, authenticated WITH CHECK (true);
-- Seuls pasteurs/admin peuvent lister les abonnements (pour l'envoi)
CREATE POLICY push_read ON push_subscriptions FOR SELECT TO authenticated
  USING (my_role() IN ('pasteur_titulaire','pasteur_site','admin'));

-- ── 6. DROITS DU RÔLE « saisie » (membres, départements, affectation âmes) ──
DROP POLICY IF EXISTS saisie_members ON members;
CREATE POLICY saisie_members ON members FOR ALL TO authenticated
  USING      (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie','conseiller'))
  WITH CHECK (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie','conseiller'));

DROP POLICY IF EXISTS saisie_departments ON departments;
CREATE POLICY saisie_departments ON departments FOR ALL TO authenticated
  USING      (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie','responsable_dept'))
  WITH CHECK (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie','responsable_dept'));

DROP POLICY IF EXISTS saisie_dept_members ON department_members;
CREATE POLICY saisie_dept_members ON department_members FOR ALL TO authenticated
  USING      (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie','responsable_dept'))
  WITH CHECK (my_role() IN ('pasteur_titulaire','pasteur_site','admin','saisie','responsable_dept'));

-- ── 7. DROITS DU RÔLE « intercession » (demandes de prière) ─────────────────
DROP POLICY IF EXISTS interc_select ON prayer_requests;
DROP POLICY IF EXISTS interc_update ON prayer_requests;
CREATE POLICY interc_select ON prayer_requests FOR SELECT TO authenticated
  USING (my_role() IN ('pasteur_titulaire','pasteur_site','admin','intercession'));
CREATE POLICY interc_update ON prayer_requests FOR UPDATE TO authenticated
  USING      (my_role() IN ('pasteur_titulaire','pasteur_site','admin','intercession'))
  WITH CHECK (my_role() IN ('pasteur_titulaire','pasteur_site','admin','intercession'));

-- Fin de la migration 04
