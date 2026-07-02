-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  KOINONIA — Schéma Supabase pour DANS TA PRÉSENCE CHURCH               ║
-- ║  Pasteur Mike Kalambay · Vision : gagner / former / implanter         ║
-- ║                                                                        ║
-- ║  Fichier 1/1 — exécutable tel quel dans Supabase > SQL Editor.         ║
-- ║  Couvre les 5 modules + RLS + vues Module 1 + triggers + seed démo.    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ─────────────────────────────────────────────────────────────────────────
-- 0. EXTENSIONS
-- ─────────────────────────────────────────────────────────────────────────
create extension if not exists pgcrypto;      -- gen_random_uuid()
create extension if not exists pg_cron;        -- jobs planifiés (alertes, SMS)
-- (postgis optionnel pour la cartographie ; ici on stocke lat/lng en numeric)

-- ─────────────────────────────────────────────────────────────────────────
-- 1. ENUMS SYSTÈME (concepts fixes ; le "configurable" passe par des tables)
-- ─────────────────────────────────────────────────────────────────────────
create type app_role as enum (
  'pasteur_titulaire','pasteur_site','responsable_dept',
  'conseiller','admin','comptable','ouvrier','membre'
);
create type church_kind   as enum ('mere','fille','site_missionnaire');
create type church_status  as enum ('active','en_implantation','vision');
create type gender_t       as enum ('h','f');
create type interaction_t  as enum ('visite','appel','rencontre','sms','whatsapp','autre');
create type prayer_status  as enum ('en_attente','en_priere','exauce');
create type content_status as enum ('en_attente','approuve','publie','rejete');
create type attendance_method as enum ('qr','manuel','sms');
create type vision_metric  as enum ('ames','disciples','eglises');
create type notif_channel   as enum ('push','sms','email');
create type notif_status    as enum ('en_attente','envoye','echec');

-- ─────────────────────────────────────────────────────────────────────────
-- 2. UTILITAIRE : updated_at automatique
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. SITES / ÉGLISES (multi-tenant + réseau d'implantation auto-référencé)
-- ─────────────────────────────────────────────────────────────────────────
create table churches (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  kind          church_kind   not null default 'fille',
  status        church_status not null default 'active',
  parent_id     uuid references churches(id) on delete set null,
  city          text,
  country       text,
  lat           numeric(9,6),
  lng           numeric(9,6),
  founded_on    date,
  description   text,
  is_public     boolean not null default true,  -- visible sur la page publique
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on churches(parent_id);
create trigger trg_churches_upd before update on churches
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- 4. PROFILS (lien vers auth.users de Supabase) + RBAC
-- ─────────────────────────────────────────────────────────────────────────
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  role        app_role not null default 'membre',
  church_id   uuid references churches(id) on delete set null,
  phone       text,
  language    text not null default 'fr',   -- fr | ln | ts | en
  member_id   uuid,                          -- lien optionnel vers members
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_profiles_upd before update on profiles
  for each row execute function set_updated_at();

-- Crée automatiquement un profil à l'inscription d'un utilisateur
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), 'membre')
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Helpers RLS (SECURITY DEFINER pour éviter la récursion sur profiles)
create or replace function my_role() returns app_role
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid();
$$;
create or replace function my_church_id() returns uuid
language sql stable security definer set search_path = public as $$
  select church_id from profiles where id = auth.uid();
$$;
create or replace function is_pastor_global() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_role() = 'pasteur_titulaire', false);
$$;
-- Accès à un site : pasteur global OU même église
create or replace function can_see_church(target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_pastor_global() or target = my_church_id();
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 5. TABLES DE RÉFÉRENCE CONFIGURABLES (modifiables sans migration)
-- ─────────────────────────────────────────────────────────────────────────

-- 5.1 Statuts de membre (Module 2)
create table member_statuses (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  label       text not null,
  rank        int  not null,          -- ordre hiérarchique
  color       text default '#e8b85f',
  is_active   boolean not null default true
);

-- 5.2 Étapes du parcours d'intégration / discipulat (Module 3)
create table discipleship_stages (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  label       text not null,
  order_index int  not null,
  is_active   boolean not null default true
);

-- 5.3 Catégories financières (Module 5)
create table finance_categories (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  label       text not null,
  is_active   boolean not null default true
);

-- ─────────────────────────────────────────────────────────────────────────
-- 6. MODULE 2 — MEMBRES, FAMILLES, CARTES QR, PRÉSENCES
-- ─────────────────────────────────────────────────────────────────────────
create table families (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references churches(id) on delete cascade,
  name        text not null,
  head_member_id uuid,
  created_at  timestamptz not null default now()
);

create sequence if not exists member_seq start 1001;

create table members (
  id            uuid primary key default gen_random_uuid(),
  church_id     uuid not null references churches(id) on delete cascade,
  member_code   text unique,                         -- ex: DTP-2026-01001
  qr_token      text unique default encode(gen_random_bytes(16),'hex'),
  first_name    text not null,
  last_name     text not null,
  gender        gender_t,
  birth_date    date,
  phone         text,
  email         text,
  address       text,
  lat           numeric(9,6),
  lng           numeric(9,6),
  photo_url     text,
  language      text default 'fr',
  family_id     uuid references families(id) on delete set null,
  status_id     uuid references member_statuses(id),
  -- Suivi spirituel (Module 3 dénormalisé pour rapidité dashboard)
  current_stage_id uuid references discipleship_stages(id),
  counselor_id  uuid references members(id) on delete set null,
  last_contact_at timestamptz,
  joined_on     date default current_date,
  profile_id    uuid references profiles(id) on delete set null, -- s'il a un compte app
  notes         text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on members(church_id);
create index on members(status_id);
create index on members(current_stage_id);
create index on members(counselor_id);
create index on members(last_contact_at);
create trigger trg_members_upd before update on members
  for each row execute function set_updated_at();

alter table families add constraint fk_family_head
  foreign key (head_member_id) references members(id) on delete set null;

-- Génère member_code lisible à l'insertion
create or replace function gen_member_code() returns trigger
language plpgsql as $$
begin
  if new.member_code is null then
    new.member_code := 'DTP-' || to_char(now(),'YYYY') || '-' ||
      lpad(nextval('member_seq')::text, 5, '0');
  end if;
  return new;
end $$;
create trigger trg_member_code before insert on members
  for each row execute function gen_member_code();

create table attendance (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references churches(id) on delete cascade,
  member_id   uuid references members(id) on delete cascade,
  service_date date not null default current_date,
  event_kind  text default 'culte',          -- culte | priere | jeunesse | ...
  method      attendance_method default 'qr',
  checked_at  timestamptz not null default now(),
  unique (member_id, service_date, event_kind)  -- anti-doublon (utile offline)
);
create index on attendance(church_id, service_date);

-- ─────────────────────────────────────────────────────────────────────────
-- 7. MODULE 3 — SUIVI DES ÂMES & DISCIPULAT
-- ─────────────────────────────────────────────────────────────────────────

-- Historique de progression spirituelle
create table stage_history (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid not null references members(id) on delete cascade,
  stage_id    uuid not null references discipleship_stages(id),
  reached_at  timestamptz not null default now(),
  note        text
);
create index on stage_history(member_id);

-- Interactions de suivi (notes confidentielles)
create table interactions (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid not null references members(id) on delete cascade,
  counselor_id uuid references members(id) on delete set null,
  kind         interaction_t not null default 'appel',
  occurred_at  timestamptz not null default now(),
  note         text,
  is_confidential boolean not null default true,
  created_at   timestamptz not null default now()
);
create index on interactions(member_id);

-- Met à jour members.last_contact_at à chaque interaction
create or replace function touch_last_contact() returns trigger
language plpgsql as $$
begin
  update members set last_contact_at = new.occurred_at where id = new.member_id;
  return new;
end $$;
create trigger trg_touch_contact after insert on interactions
  for each row execute function touch_last_contact();

create table baptisms (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid not null references members(id) on delete cascade,
  scheduled_on date,
  baptized_on  date,
  officiant    text,
  status       text default 'prevu',   -- prevu | effectue | annule
  created_at   timestamptz not null default now()
);

-- Cellules / groupes de maison
create table cells (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references churches(id) on delete cascade,
  name        text not null,
  leader_id   uuid references members(id) on delete set null,
  address     text,
  lat         numeric(9,6),
  lng         numeric(9,6),
  meeting_day text,
  created_at  timestamptz not null default now()
);
create table cell_members (
  cell_id   uuid references cells(id) on delete cascade,
  member_id uuid references members(id) on delete cascade,
  joined_on date default current_date,
  primary key (cell_id, member_id)
);

-- Demandes de prière (la page PUBLIQUE écrit ici)
create table prayer_requests (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete set null,
  member_id   uuid references members(id) on delete set null,
  author_name text,                       -- si soumis par un visiteur anonyme
  content     text not null,
  is_urgent   boolean not null default false,
  is_public   boolean not null default false,
  status      prayer_status not null default 'en_attente',
  created_at  timestamptz not null default now()
);
create index on prayer_requests(church_id, status);

-- Témoignages (page publique + validation pastorale)
create table testimonies (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete set null,
  member_id   uuid references members(id) on delete set null,
  author_name text,
  content     text not null,
  status      content_status not null default 'en_attente',
  created_at  timestamptz not null default now()
);

-- Enregistrement des visiteurs depuis la page publique (anonyme autorisé)
create table visitor_registrations (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete set null,
  full_name   text not null,
  phone       text,
  email       text,
  how_heard   text,
  prayer_note text,
  language    text default 'fr',
  processed   boolean not null default false,   -- converti en membre par le staff
  created_at  timestamptz not null default now()
);
create index on visitor_registrations(processed, created_at);

-- ─────────────────────────────────────────────────────────────────────────
-- 8. MODULE 4 — DÉPARTEMENTS & OUVRIERS
-- ─────────────────────────────────────────────────────────────────────────
create table departments (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references churches(id) on delete cascade,
  code        text not null,
  name        text not null,
  description text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (church_id, code)
);
create table department_members (
  department_id uuid references departments(id) on delete cascade,
  member_id     uuid references members(id) on delete cascade,
  is_leader     boolean not null default false,
  joined_on     date default current_date,
  primary key (department_id, member_id)
);
create table service_schedules (
  id          uuid primary key default gen_random_uuid(),
  department_id uuid not null references departments(id) on delete cascade,
  title       text not null,
  service_date date not null,
  note        text,
  created_at  timestamptz not null default now()
);
create table service_assignments (
  schedule_id uuid references service_schedules(id) on delete cascade,
  member_id   uuid references members(id) on delete cascade,
  role        text,
  primary key (schedule_id, member_id)
);
create table worker_attendance (
  id          uuid primary key default gen_random_uuid(),
  department_id uuid references departments(id) on delete cascade,
  member_id   uuid references members(id) on delete cascade,
  service_date date not null default current_date,
  present     boolean not null default true,
  unique (department_id, member_id, service_date)
);

-- ─────────────────────────────────────────────────────────────────────────
-- 9. MODULE 5 — ADMINISTRATION, MISSION, FINANCES
-- ─────────────────────────────────────────────────────────────────────────
create table events (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete cascade,
  title       text not null,
  description text,
  kind        text default 'culte',      -- culte | conference | campagne
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  location    text,
  lat         numeric(9,6),
  lng         numeric(9,6),
  is_public   boolean not null default true,
  created_at  timestamptz not null default now()
);
create index on events(starts_at);

create table documents (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete cascade,
  title       text not null,
  category    text,
  file_url    text,
  uploaded_by uuid references profiles(id),
  created_at  timestamptz not null default now()
);

create table trainings (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete cascade,
  title       text not null,
  description text,
  kind        text default 'formation_de_base',
  created_at  timestamptz not null default now()
);
create table training_enrollments (
  training_id uuid references trainings(id) on delete cascade,
  member_id   uuid references members(id) on delete cascade,
  status      text default 'inscrit',     -- inscrit | en_cours | certifie
  completed_on date,
  primary key (training_id, member_id)
);

create table contributions (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references churches(id) on delete cascade,
  member_id   uuid references members(id) on delete set null,
  category_id uuid references finance_categories(id),
  amount      numeric(14,2) not null,
  currency    text not null default 'USD',
  method      text default 'especes',     -- especes | mobile_money | virement
  received_on date not null default current_date,
  receipt_no  text,
  recorded_by uuid references profiles(id),
  created_at  timestamptz not null default now()
);
create index on contributions(church_id, received_on);

create table projects (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete cascade,
  name        text not null,
  goal_amount numeric(14,2),
  raised_amount numeric(14,2) default 0,
  status      text default 'en_cours',
  created_at  timestamptz not null default now()
);

-- Campagnes d'évangélisation
create table campaigns (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete cascade,
  name        text not null,
  location    text,
  lat         numeric(9,6),
  lng         numeric(9,6),
  starts_on   date,
  ends_on     date,
  target_souls int default 0,
  souls_won   int default 0,
  status      text default 'planifiee',
  created_at  timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────
-- 10. MODULE 1 — PILOTAGE PASTORAL : objectifs de vision & agenda
-- ─────────────────────────────────────────────────────────────────────────
create table vision_goals (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references churches(id) on delete cascade,
  year        int not null,
  metric      vision_metric not null,
  target      int not null,
  achieved    int not null default 0,    -- peut être recalculé par job
  unique (church_id, year, metric)
);

create table pastoral_appointments (
  id           uuid primary key default gen_random_uuid(),
  church_id    uuid references churches(id) on delete cascade,
  pastor_id    uuid references profiles(id) on delete set null,
  member_id    uuid references members(id) on delete set null,
  title        text not null,
  starts_at    timestamptz not null,
  kind         text default 'rendez_vous',  -- rendez_vous | accompagnement | reunion
  is_confidential boolean not null default false,
  created_at   timestamptz not null default now()
);
create index on pastoral_appointments(church_id, starts_at);

-- File des notifications (alimentée par jobs ; vidée par Edge Function SMS/push)
create table notifications_outbox (
  id          uuid primary key default gen_random_uuid(),
  channel     notif_channel not null default 'sms',
  recipient   text not null,            -- téléphone, token push ou email
  payload     jsonb not null,
  status      notif_status not null default 'en_attente',
  attempts    int not null default 0,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index on notifications_outbox(status, created_at);

-- ─────────────────────────────────────────────────────────────────────────
-- 11. MODULE 1 — VUES D'AGRÉGATION POUR LE TABLEAU DE BORD
--     (le dashboard interroge ces vues, pas les tables brutes)
-- ─────────────────────────────────────────────────────────────────────────

-- 11.1 KPI globaux par église
create or replace view v_church_kpis as
select
  c.id as church_id,
  c.name,
  (select count(*) from members m
     where m.church_id = c.id and m.is_active) as members_count,
  (select count(*) from members m
     join member_statuses s on s.id = m.status_id
     where m.church_id = c.id and s.code = 'nouveau_converti') as new_converts_count,
  (select count(*) from members m
     join member_statuses s on s.id = m.status_id
     where m.church_id = c.id and s.code in ('ouvrier','responsable')) as workers_count,
  (select count(*) from departments d
     where d.church_id = c.id and d.is_active) as departments_count
from churches c;

-- 11.2 Entonnoir du parcours de l'âme (signature du dashboard)
create or replace view v_soul_funnel as
select
  m.church_id,
  st.code  as stage_code,
  st.label as stage_label,
  st.order_index,
  count(m.id) as souls
from discipleship_stages st
left join members m
  on m.current_stage_id = st.id and m.is_active
where st.is_active
group by m.church_id, st.code, st.label, st.order_index
order by st.order_index;

-- 11.3 Progression de la vision (objectifs annuels)
create or replace view v_vision_progress as
select
  vg.church_id,
  vg.year,
  vg.metric,
  vg.target,
  vg.achieved,
  round(100.0 * least(vg.achieved, vg.target) / nullif(vg.target,0), 0) as pct
from vision_goals vg;

-- 11.4 Courbe de croissance hebdomadaire (présence + nouveaux convertis)
create or replace view v_growth_weekly as
select
  church_id,
  date_trunc('week', service_date)::date as week,
  count(*) as attendance
from attendance
group by church_id, date_trunc('week', service_date)
order by week;

-- 11.5 Alertes de suivi : âmes sans contact (anti-décrochage)
create or replace view v_followup_alerts as
select
  m.id, m.church_id, m.first_name, m.last_name, m.phone,
  m.last_contact_at,
  st.label as stage_label,
  coalesce(extract(day from now() - m.last_contact_at)::int, 999) as days_since_contact,
  cn.first_name || ' ' || cn.last_name as counselor_name
from members m
left join discipleship_stages st on st.id = m.current_stage_id
left join members cn on cn.id = m.counselor_id
where m.is_active
  and (m.last_contact_at is null or m.last_contact_at < now() - interval '7 days')
  and st.order_index <= 3                       -- âmes encore en début de parcours
order by days_since_contact desc;

-- ─────────────────────────────────────────────────────────────────────────
-- 12. JOB ANTI-DÉCROCHAGE → remplit la file SMS (consommée par Edge Function)
-- ─────────────────────────────────────────────────────────────────────────
create or replace function enqueue_followup_sms() returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in
    select a.*, cn.phone as counselor_phone
    from v_followup_alerts a
    join members cn on cn.id = (select counselor_id from members where id = a.id)
    where a.days_since_contact between 7 and 30
      and cn.phone is not null
  loop
    insert into notifications_outbox(channel, recipient, payload)
    values ('sms', r.counselor_phone, jsonb_build_object(
      'template','followup',
      'soul', r.first_name || ' ' || r.last_name,
      'days', r.days_since_contact
    ));
    n := n + 1;
  end loop;
  return n;
end $$;

-- Planifie le job tous les jours à 06:00 (décommenter après déploiement)
-- select cron.schedule('followup-sms-daily','0 6 * * *', $$select enqueue_followup_sms()$$);

-- ─────────────────────────────────────────────────────────────────────────
-- 13. RLS — SÉCURITÉ AU NIVEAU DES LIGNES
-- ─────────────────────────────────────────────────────────────────────────
alter table churches               enable row level security;
alter table profiles               enable row level security;
alter table members                enable row level security;
alter table families               enable row level security;
alter table attendance             enable row level security;
alter table stage_history          enable row level security;
alter table interactions           enable row level security;
alter table baptisms               enable row level security;
alter table cells                  enable row level security;
alter table cell_members           enable row level security;
alter table prayer_requests        enable row level security;
alter table testimonies            enable row level security;
alter table visitor_registrations  enable row level security;
alter table departments            enable row level security;
alter table department_members     enable row level security;
alter table service_schedules      enable row level security;
alter table service_assignments    enable row level security;
alter table worker_attendance      enable row level security;
alter table events                 enable row level security;
alter table documents              enable row level security;
alter table trainings              enable row level security;
alter table training_enrollments   enable row level security;
alter table contributions          enable row level security;
alter table projects               enable row level security;
alter table campaigns              enable row level security;
alter table vision_goals           enable row level security;
alter table pastoral_appointments  enable row level security;
alter table member_statuses        enable row level security;
alter table discipleship_stages    enable row level security;
alter table finance_categories     enable row level security;

-- 13.1 Référentiels : lecture pour tout utilisateur authentifié, écriture admin/pasteur
create policy ref_read_status  on member_statuses     for select to authenticated using (true);
create policy ref_read_stages  on discipleship_stages for select to authenticated using (true);
create policy ref_read_fin     on finance_categories  for select to authenticated using (true);
create policy ref_write_status on member_statuses     for all to authenticated
  using (my_role() in ('pasteur_titulaire','admin')) with check (my_role() in ('pasteur_titulaire','admin'));
create policy ref_write_stages on discipleship_stages for all to authenticated
  using (my_role() in ('pasteur_titulaire','admin')) with check (my_role() in ('pasteur_titulaire','admin'));
create policy ref_write_fin    on finance_categories  for all to authenticated
  using (my_role() in ('pasteur_titulaire','admin','comptable')) with check (my_role() in ('pasteur_titulaire','admin','comptable'));

-- 13.2 Profils : on lit/écrit son propre profil ; pasteur global voit tout
create policy prof_self  on profiles for select to authenticated
  using (id = auth.uid() or is_pastor_global());
create policy prof_upd   on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- 13.3 Églises : lecture publique des sites publics + scope authentifié
create policy church_public on churches for select to anon using (is_public);
create policy church_auth   on churches for select to authenticated using (true);
create policy church_write  on churches for all to authenticated
  using (my_role() in ('pasteur_titulaire','admin'))
  with check (my_role() in ('pasteur_titulaire','admin'));

-- 13.4 Membres : périmètre par église (pasteur global = tout)
create policy members_scope on members for select to authenticated
  using (can_see_church(church_id));
create policy members_write on members for all to authenticated
  using (can_see_church(church_id) and my_role() in
        ('pasteur_titulaire','pasteur_site','admin','responsable_dept'))
  with check (can_see_church(church_id));

-- 13.5 Interactions de suivi : conseiller assigné + pasteur uniquement (confidentiel)
create policy inter_read on interactions for select to authenticated
  using (
    is_pastor_global()
    or counselor_id in (select id from members where profile_id = auth.uid())
  );
create policy inter_write on interactions for insert to authenticated
  with check (my_role() in ('pasteur_titulaire','pasteur_site','conseiller','responsable_dept'));

-- 13.6 Données de site (modèle générique : voir si même église)
create policy att_scope    on attendance            for all to authenticated using (can_see_church(church_id)) with check (can_see_church(church_id));
create policy dept_scope   on departments           for all to authenticated using (can_see_church(church_id)) with check (can_see_church(church_id));
create policy cells_scope  on cells                 for all to authenticated using (can_see_church(church_id)) with check (can_see_church(church_id));
create policy ev_auth      on events                for select to authenticated using (true);
create policy ev_write     on events                for all to authenticated using (my_role() in ('pasteur_titulaire','pasteur_site','admin')) with check (true);
create policy vg_scope     on vision_goals          for all to authenticated using (can_see_church(church_id)) with check (can_see_church(church_id));
create policy appt_scope   on pastoral_appointments for all to authenticated using (can_see_church(church_id)) with check (can_see_church(church_id));
create policy camp_scope   on campaigns             for all to authenticated using (can_see_church(church_id)) with check (can_see_church(church_id));

-- 13.7 Finances : comptable / pasteur / admin
create policy fin_scope on contributions for all to authenticated
  using (can_see_church(church_id) and my_role() in ('pasteur_titulaire','pasteur_site','admin','comptable'))
  with check (can_see_church(church_id));

-- 13.8 PAGE PUBLIQUE — anon autorisé à SOUMETTRE (jamais à lire les données privées)
create policy ev_public_read   on events            for select to anon using (is_public);
create policy visit_anon_insert on visitor_registrations for insert to anon with check (true);
create policy visit_staff_read  on visitor_registrations for select to authenticated using (can_see_church(church_id));
create policy pray_anon_insert  on prayer_requests   for insert to anon with check (true);
create policy pray_staff_read   on prayer_requests   for select to authenticated using (can_see_church(church_id));
create policy pray_public_read  on prayer_requests   for select to anon using (is_public and status <> 'en_attente');
create policy testi_anon_insert on testimonies       for insert to anon with check (true);
create policy testi_public_read on testimonies       for select to anon using (status = 'publie');
create policy testi_staff       on testimonies       for select to authenticated using (can_see_church(church_id));

-- Note : les vues v_* héritent de la RLS des tables sous-jacentes (security_invoker).

-- Les vues appliquent la RLS de l'utilisateur qui interroge (Postgres 15+)
alter view v_church_kpis     set (security_invoker = true);
alter view v_soul_funnel     set (security_invoker = true);
alter view v_vision_progress set (security_invoker = true);
alter view v_growth_weekly   set (security_invoker = true);
alter view v_followup_alerts set (security_invoker = true);

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FIN DU SCHÉMA. Exécuter ensuite 02_seed.sql pour les données démo.    ║
-- ╚══════════════════════════════════════════════════════════════════════╝
