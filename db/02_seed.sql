-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  KOINONIA — Données de démonstration (02_seed.sql)                     ║
-- ║  À exécuter APRÈS 01_schema.sql. Fait apparaître des chiffres réels    ║
-- ║  dans le tableau de bord (Module 1) et la page publique.              ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- 1. Référentiels configurables ------------------------------------------------
insert into member_statuses(code,label,rank,color) values
  ('visiteur','Visiteur',1,'#7fa8d4'),
  ('nouveau_converti','Nouveau converti',2,'#9b7fd4'),
  ('membre','Membre',3,'#e8b85f'),
  ('ouvrier','Ouvrier',4,'#6bbf8a'),
  ('responsable','Responsable',5,'#6bbf8a'),
  ('ancien','Ancien',6,'#cf9a3d'),
  ('pasteur','Pasteur',7,'#e8b85f');

insert into discipleship_stages(code,label,order_index) values
  ('accueil','Accueil / 1er contact',1),
  ('decision','Décision pour Christ',2),
  ('formation_base','Cours nouveaux convertis',3),
  ('bapteme','Baptême',4),
  ('cellule','Intégration en cellule',5),
  ('service','Engagement au service',6);

insert into finance_categories(code,label) values
  ('dime','Dîme'),('offrande','Offrande'),
  ('projet','Projet spécial'),('don','Don / Semence');

-- 2. Réseau d'églises (site mère + filles + vision) ---------------------------
insert into churches(id,name,kind,status,city,country,lat,lng,founded_on,is_public,description) values
  ('11111111-1111-1111-1111-111111111111','Dans Ta Présence Church — Kinshasa','mere','active','Kinshasa','RD Congo',-4.325,15.322,'2009-01-01',true,'Église mère. Nouveau temple inauguré en 2026.'),
  ('22222222-2222-2222-2222-222222222222','DTP Lubumbashi','fille','active','Lubumbashi','RD Congo',-11.66,27.48,'2021-06-01',true,'Église fille active.'),
  ('33333333-3333-3333-3333-333333333333','DTP Goma','fille','active','Goma','RD Congo',-1.68,29.22,'2023-03-01',true,'Église fille active.'),
  ('44444444-4444-4444-4444-444444444444','DTP Abidjan','fille','active','Abidjan','Côte d''Ivoire',5.36,-4.00,'2024-05-01',true,'Église fille — Afrique de l''Ouest.'),
  ('55555555-5555-5555-5555-555555555555','DTP Paris (diaspora)','fille','en_implantation','Paris','France',48.85,2.35,null,true,'Cellule diaspora en croissance.'),
  ('66666666-6666-6666-6666-666666666666','DTP Bruxelles (diaspora)','fille','en_implantation','Bruxelles','Belgique',50.85,4.35,null,true,'Cellule diaspora en croissance.'),
  ('77777777-7777-7777-7777-777777777777','Champ missionnaire — Brazzaville','site_missionnaire','vision','Brazzaville','Congo',-4.27,15.27,null,true,'Site missionnaire ciblé 2026-2027.');

-- 3. Départements du site mère (les 8 + extensible) ---------------------------
insert into departments(church_id,code,name) values
  ('11111111-1111-1111-1111-111111111111','femmes','Femmes'),
  ('11111111-1111-1111-1111-111111111111','jeunesse','Jeunesse'),
  ('11111111-1111-1111-1111-111111111111','intercession','Intercession'),
  ('11111111-1111-1111-1111-111111111111','evangelisation','Évangélisation'),
  ('11111111-1111-1111-1111-111111111111','chorale','Chorale'),
  ('11111111-1111-1111-1111-111111111111','communication','Communication chrétienne'),
  ('11111111-1111-1111-1111-111111111111','accueil','Accueil'),
  ('11111111-1111-1111-1111-111111111111','conseil','Conseil pastoral'),
  ('11111111-1111-1111-1111-111111111111','media','Média & Production');

-- 4. Membres de démo répartis sur le parcours ---------------------------------
-- Génère 4820 membres pour le site mère, répartis sur les statuts & étapes,
-- avec des dates de contact variées (certaines anciennes -> alertes).
do $$
declare
  v_church uuid := '11111111-1111-1111-1111-111111111111';
  s_visit uuid; s_conv uuid; s_memb uuid; s_ouvr uuid; s_resp uuid;
  st1 uuid; st2 uuid; st3 uuid; st4 uuid; st5 uuid; st6 uuid;
  i int; r numeric; status_id uuid; stage_id uuid; lc timestamptz;
begin
  select id into s_visit from member_statuses where code='visiteur';
  select id into s_conv  from member_statuses where code='nouveau_converti';
  select id into s_memb  from member_statuses where code='membre';
  select id into s_ouvr  from member_statuses where code='ouvrier';
  select id into s_resp  from member_statuses where code='responsable';
  select id into st1 from discipleship_stages where code='accueil';
  select id into st2 from discipleship_stages where code='decision';
  select id into st3 from discipleship_stages where code='formation_base';
  select id into st4 from discipleship_stages where code='bapteme';
  select id into st5 from discipleship_stages where code='cellule';
  select id into st6 from discipleship_stages where code='service';

  for i in 1..4820 loop
    r := random();
    if    r < 0.106 then status_id:=s_visit; stage_id:=st1;          -- ~512 visiteurs
    elsif r < 0.171 then status_id:=s_conv;  stage_id:=st2;          -- ~312 convertis
    elsif r < 0.870 then status_id:=s_memb;  stage_id:=(array[st4,st5])[(1+floor(random()*2))::int];
    else                  status_id:=(array[s_ouvr,s_resp])[(1+floor(random()*2))::int]; stage_id:=st6; -- ~643 ouvriers/resp
    end if;

    -- dates de dernier contact : la majorité récente, quelques-unes anciennes
    if random() < 0.04 then lc := now() - (interval '1 day' * (8 + floor(random()*20)));
    else lc := now() - (interval '1 day' * floor(random()*6)); end if;

    insert into members(church_id,first_name,last_name,gender,status_id,current_stage_id,last_contact_at,phone)
    values (v_church,'Membre','#'||i,(array['h','f'])[(1+floor(random()*2))::int]::gender_t,
            status_id,stage_id,lc,'+24390'||lpad((1000000+i)::text,7,'0'));
  end loop;
end $$;

-- 5. Présences (12 dernières semaines, croissance progressive) ----------------
do $$
declare w int; base int; d date;
begin
  for w in 0..11 loop
    d := (date_trunc('week', current_date) - (w || ' weeks')::interval)::date;
    base := 2600 + (11-w)*55;             -- présence moyenne croissante chaque semaine
    -- N présences distinctes (tirage aléatoire de membres présents ce dimanche)
    insert into attendance(church_id,member_id,service_date,event_kind,method)
    select '11111111-1111-1111-1111-111111111111', id, d, 'culte', 'qr'
    from members
    where church_id = '11111111-1111-1111-1111-111111111111'
    order by random()
    limit base
    on conflict (member_id, service_date, event_kind) do nothing;
  end loop;
end $$;

-- 6. Objectifs de vision 2026 -------------------------------------------------
insert into vision_goals(church_id,year,metric,target,achieved) values
  ('11111111-1111-1111-1111-111111111111',2026,'ames',5000,3240),
  ('11111111-1111-1111-1111-111111111111',2026,'disciples',1200,740),
  ('11111111-1111-1111-1111-111111111111',2026,'eglises',12,7);

-- 7. Demandes de prière & témoignages (dont publics pour la page publique) ----
insert into prayer_requests(church_id,author_name,content,is_urgent,is_public,status) values
  ('11111111-1111-1111-1111-111111111111','Anonyme','Pour la guérison de ma mère.',true,true,'en_priere'),
  ('11111111-1111-1111-1111-111111111111','Anonyme','Direction pour un nouvel emploi.',false,true,'en_priere'),
  ('11111111-1111-1111-1111-111111111111',null,'Pour ma famille.',false,false,'en_attente');

insert into testimonies(church_id,author_name,content,status) values
  ('11111111-1111-1111-1111-111111111111','Grâce M.','Délivrance et restauration dans mon foyer. Gloire à Dieu !','publie'),
  ('11111111-1111-1111-1111-111111111111','Joël K.','Guéri après la prière du dimanche.','publie'),
  ('11111111-1111-1111-1111-111111111111','David I.','Témoignage en attente de validation.','en_attente');

-- 8. Événements publics (affichés sur la page publique) -----------------------
insert into events(church_id,title,description,kind,starts_at,location,is_public) values
  ('11111111-1111-1111-1111-111111111111','Culte de célébration','Adoration, Parole et prière.','culte', now()+interval '3 days' + interval '9 hours','Temple — Kinshasa',true),
  ('11111111-1111-1111-1111-111111111111','Nuit de prière & intercession','Veillée de l''Esprit.','culte', now()+interval '6 days' + interval '20 hours','Temple — Kinshasa',true),
  ('11111111-1111-1111-1111-111111111111','Campagne d''évangélisation Lubumbashi','Gagner des âmes pour Christ.','campagne', now()+interval '20 days','Lubumbashi',true);

-- 9. Campagnes ----------------------------------------------------------------
insert into campaigns(church_id,name,location,starts_on,target_souls,souls_won,status) values
  ('11111111-1111-1111-1111-111111111111','Lumière sur Kinshasa','Kinshasa',current_date-30,1000,612,'en_cours'),
  ('22222222-2222-2222-2222-222222222222','Implantation Lubumbashi','Lubumbashi',current_date-10,500,180,'en_cours');

-- 10. Rendez-vous pastoraux du jour -------------------------------------------
insert into pastoral_appointments(church_id,title,starts_at,kind,is_confidential) values
  ('11111111-1111-1111-1111-111111111111','Réunion du conseil pastoral',current_date+interval '9 hours','reunion',false),
  ('11111111-1111-1111-1111-111111111111','Entretien d''accompagnement — Famille Tshibasu',current_date+interval '11 hours 30 minutes','accompagnement',true),
  ('11111111-1111-1111-1111-111111111111','Validation des baptêmes',current_date+interval '14 hours','reunion',false),
  ('11111111-1111-1111-1111-111111111111','Point responsables de départements',current_date+interval '16 hours','reunion',false);

-- ✔ Données de démo chargées. Vérifier avec :
--   select * from v_church_kpis;
--   select * from v_soul_funnel where church_id='11111111-1111-1111-1111-111111111111';
--   select * from v_vision_progress;
