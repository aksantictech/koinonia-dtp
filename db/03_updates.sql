-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  KOINONIA — Migration 03 (à exécuter APRÈS 01 et 02)                   ║
-- ║  • Demandes de rendez-vous avec le pasteur (page publique)            ║
-- ║  • Téléphone sur les demandes de prière                              ║
-- ║  • Accès "Demandes" réservé aux pasteurs (RLS)                       ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- 1) Téléphone optionnel sur les demandes de prière -------------------------
alter table prayer_requests add column if not exists phone text;

-- 2) Demandes de rendez-vous avec le pasteur --------------------------------
create table if not exists appointment_requests (
  id            uuid primary key default gen_random_uuid(),
  church_id     uuid references churches(id) on delete set null,
  full_name     text not null,
  phone         text,
  email         text,
  preferred_date date,
  preferred_slot text,                       -- matin | apres_midi | soir
  reason        text,
  status        text not null default 'en_attente',  -- en_attente | planifie | refuse
  handled_by    uuid references profiles(id),
  created_at    timestamptz not null default now()
);
create index if not exists idx_appt_req on appointment_requests(status, created_at);
alter table appointment_requests enable row level security;

-- Le public (anon) peut SOUMETTRE une demande, jamais lire
drop policy if exists appt_req_anon_insert on appointment_requests;
create policy appt_req_anon_insert on appointment_requests
  for insert to anon with check (true);

-- Lecture / traitement réservés au STAFF du site (pasteurs, admin)
drop policy if exists appt_req_staff_read on appointment_requests;
create policy appt_req_staff_read on appointment_requests
  for select to authenticated using (can_see_church(church_id));
drop policy if exists appt_req_staff_upd on appointment_requests;
create policy appt_req_staff_upd on appointment_requests
  for update to authenticated
  using (my_role() in ('pasteur_titulaire','pasteur_site','admin'))
  with check (my_role() in ('pasteur_titulaire','pasteur_site','admin'));

-- 3) Resserrer l'accès aux DEMANDES sur les pasteurs/admin -------------------
-- (auparavant tout le staff pouvait lire visiteurs & prières ; on réserve
--  désormais ces "boîtes de réception" aux pasteurs et à l'admin)
drop policy if exists visit_staff_read on visitor_registrations;
create policy visit_staff_read on visitor_registrations
  for select to authenticated
  using (can_see_church(church_id) and my_role() in ('pasteur_titulaire','pasteur_site','admin'));
drop policy if exists visit_staff_upd on visitor_registrations;
create policy visit_staff_upd on visitor_registrations
  for update to authenticated
  using (my_role() in ('pasteur_titulaire','pasteur_site','admin'))
  with check (my_role() in ('pasteur_titulaire','pasteur_site','admin'));

drop policy if exists pray_staff_read on prayer_requests;
create policy pray_staff_read on prayer_requests
  for select to authenticated
  using (can_see_church(church_id) and my_role() in ('pasteur_titulaire','pasteur_site','admin'));
drop policy if exists pray_staff_upd on prayer_requests;
create policy pray_staff_upd on prayer_requests
  for update to authenticated
  using (my_role() in ('pasteur_titulaire','pasteur_site','admin'))
  with check (my_role() in ('pasteur_titulaire','pasteur_site','admin'));

-- 4) Quelques demandes de démo (facultatif) ---------------------------------
insert into appointment_requests(church_id,full_name,phone,preferred_date,preferred_slot,reason)
values
 ('11111111-1111-1111-1111-111111111111','Patrick Mwamba','+243900111222',current_date+3,'soir','Conseil sur le mariage'),
 ('11111111-1111-1111-1111-111111111111','Sandra Lukusa','+243900333444',current_date+5,'matin','Accompagnement spirituel')
on conflict do nothing;

-- ✔ Terminé. Vérifier : select * from appointment_requests;
