-- ============================================================================
-- KOINONIA — Migration 04a : NOUVEAUX RÔLES
-- ⚠️ EXÉCUTER CE FICHIER SEUL, EN PREMIER, puis cliquer Run.
--    Ensuite seulement, exécuter 04b_features.sql.
--
-- PostgreSQL exige qu'une nouvelle valeur d'enum soit validée (commit) AVANT
-- d'être utilisée dans des règles. C'est pourquoi on les ajoute à part.
-- ============================================================================

ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'saisie';        -- saisit membres, départements, publications, affectation des âmes
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'intercession';  -- gère uniquement les demandes de prière
