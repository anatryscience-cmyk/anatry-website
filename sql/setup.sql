-- Anatry database: paste once in Supabase SQL Editor. Review before running.
create extension if not exists pgcrypto;
create table if not exists public.admin_users (user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (char_length(display_name) between 2 and 70),
 account_type text not null default 'student' check(account_type in ('student','mentor')),
 discipline text not null default 'Biology' check(discipline in ('Medicine','Biology','Chemistry','Physics')),
 country text not null default 'Other' check(country in ('Bahrain','Other')),
 school text check(char_length(school)<=100),
 bio text not null default '' check(char_length(bio)<=350),
 created_at timestamptz not null default now()
);
create table if not exists public.mentor_applications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 institution text not null check(char_length(institution) between 2 and 150),
 expertise text not null check(char_length(expertise) between 2 and 120),
 motivation text not null check(char_length(motivation) between 20 and 2000),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), reviewed_at timestamptz,
 unique(user_id)
);
create table if not exists public.projects (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id),
 title text not null check(char_length(title) between 5 and 140),
 discipline text not null check(discipline in ('Medicine','Biology','Chemistry','Physics')),
 description text not null check(char_length(description) between 30 and 2500),
 status text not null default 'pending' check(status in ('pending','open','closed','rejected')),
 created_at timestamptz not null default now()
);
create table if not exists public.team_applications (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 statement text not null check(char_length(statement) between 20 and 1000),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), unique(project_id,user_id)
);
create table if not exists public.team_notes (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id) on delete cascade,
 author_id uuid not null references public.profiles(id),
 content text not null check(char_length(content) between 1 and 2000),
 created_at timestamptz not null default now()
);
create table if not exists public.publications (
 id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles(id),
 project_id uuid references public.projects(id),
 title text not null check(char_length(title) between 5 and 160),
 discipline text not null check(discipline in ('Medicine','Biology','Chemistry','Physics')),
 abstract text not null check(char_length(abstract) between 30 and 2000),
 body text not null check(char_length(body) between 100 and 50000),
 doc_url text check(doc_url is null or (doc_url ~ '^https://docs[.]google[.]com/' and char_length(doc_url)<=1000)),
 status text not null default 'draft' check(status in ('draft','submitted','published','rejected')),
 published_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.reports (
 id uuid primary key default gen_random_uuid(), reporter_id uuid not null references public.profiles(id),
 category text not null check(category in ('harassment','privacy','misconduct','plagiarism','other')),
 details text not null check(char_length(details) between 10 and 2000),
 reference text check(char_length(reference)<=300),
 status text not null default 'open' check(status in ('open','reviewed','resolved')),
 created_at timestamptz not null default now()
);
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.admin_users where user_id=(select auth.uid()));
$$;
create or replace function public.is_verified_mentor(uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.mentor_applications where user_id=uid and status='approved');
$$;
create or replace function public.is_team_member(pid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.projects where id=pid and owner_id=(select auth.uid()))
 or exists(select 1 from public.team_applications where project_id=pid and user_id=(select auth.uid()) and status='approved')
 or public.is_admin();
$$;
-- Server-side status protection: clients cannot approve themselves or publish directly.
create or replace function public.guard_workflow() returns trigger language plpgsql set search_path = '' as $$
begin
 if not public.is_admin() then
  if tg_table_name='mentor_applications' then
   if tg_op='UPDATE' then raise exception 'Mentor applications can only be reviewed by admins'; end if;
   new.status := 'pending'; new.reviewed_at := null;
  elsif tg_table_name='projects' then
   if tg_op='UPDATE' then
    if old.owner_id <> (select auth.uid()) then raise exception 'Not owner'; end if;
    new.status := old.status; new.owner_id := old.owner_id;
   else new.status := 'pending'; end if;
  elsif tg_table_name='team_applications' then
   if tg_op='UPDATE' then
    if not exists(select 1 from public.projects where id=old.project_id and owner_id=(select auth.uid()) and public.is_verified_mentor((select auth.uid()))) then
     raise exception 'Only verified project mentors can review applications'; end if;
    new.user_id := old.user_id; new.project_id := old.project_id; new.statement := old.statement;
   else new.status := 'pending'; end if;
  elsif tg_table_name='publications' then
   if tg_op='UPDATE' then
    new.author_id := old.author_id;
    if old.status in ('published','submitted') then raise exception 'Submitted or published articles are locked for review'; end if;
    if new.status not in ('draft','submitted') then raise exception 'Cannot publish directly'; end if;
   else new.status := 'draft'; end if;
  elsif tg_table_name='reports' then
   if tg_op='UPDATE' then raise exception 'Only admins review reports'; end if;
   new.status := 'open';
  end if;
 end if;
 if tg_table_name='publications' then new.updated_at := now(); end if;
 return new;
end $$;
create or replace function public.guard_profile() returns trigger language plpgsql set search_path = '' as $$
begin
 if not public.is_admin() then
  if tg_op='UPDATE' then new.account_type := old.account_type; end if;
 end if;
 return new;
end $$;
drop trigger if exists profile_guard on public.profiles;
create trigger profile_guard before update on public.profiles for each row execute function public.guard_profile();
do $$ declare t text; begin
 foreach t in array array['mentor_applications','projects','team_applications','publications','reports'] loop
 execute format('drop trigger if exists workflow_guard on public.%I',t);
 execute format('create trigger workflow_guard before insert or update on public.%I for each row execute function public.guard_workflow()',t);
 end loop;
end $$;
-- Profiles created on signup; only non-sensitive profile information stored.
create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,display_name,account_type,discipline,country)
 values(new.id, left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),'New member'),70),
 case when new.raw_user_meta_data->>'account_type'='mentor' then 'mentor' else 'student' end,
 case when new.raw_user_meta_data->>'discipline' in ('Medicine','Biology','Chemistry','Physics') then new.raw_user_meta_data->>'discipline' else 'Biology' end,
 case when new.raw_user_meta_data->>'country'='Bahrain' then 'Bahrain' else 'Other' end);
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_user_profile();
-- RLS everywhere; no public email exposure.
alter table public.admin_users enable row level security;
alter table public.profiles enable row level security;
alter table public.mentor_applications enable row level security;
alter table public.projects enable row level security;
alter table public.team_applications enable row level security;
alter table public.team_notes enable row level security;
alter table public.publications enable row level security;
alter table public.reports enable row level security;
create policy admin_self on public.admin_users for select to authenticated using(user_id=(select auth.uid()));
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or public.is_admin());
create policy profiles_update on public.profiles for update to authenticated using(id=(select auth.uid()) or public.is_admin()) with check(id=(select auth.uid()) or public.is_admin());
create policy mentor_read on public.mentor_applications for select to authenticated using(user_id=(select auth.uid()) or public.is_admin());
create policy mentor_create on public.mentor_applications for insert to authenticated with check(user_id=(select auth.uid()));
create policy mentor_review on public.mentor_applications for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy project_read on public.projects for select to anon,authenticated using(status in ('open','closed') or owner_id=(select auth.uid()) or public.is_admin());
create policy project_create on public.projects for insert to authenticated with check(owner_id=(select auth.uid()) and public.is_verified_mentor((select auth.uid())));
create policy project_update on public.projects for update to authenticated using(owner_id=(select auth.uid()) or public.is_admin()) with check(owner_id=(select auth.uid()) or public.is_admin());
create policy applications_read on public.team_applications for select to authenticated using(user_id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.projects p where p.id=project_id and p.owner_id=(select auth.uid())));
create policy applications_create on public.team_applications for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.projects p where p.id=project_id and p.status='open' and p.owner_id<>(select auth.uid())));
create policy applications_review on public.team_applications for update to authenticated using(public.is_admin() or exists(select 1 from public.projects p where p.id=project_id and p.owner_id=(select auth.uid()) and public.is_verified_mentor((select auth.uid())))) with check(public.is_admin() or exists(select 1 from public.projects p where p.id=project_id and p.owner_id=(select auth.uid()) and public.is_verified_mentor((select auth.uid()))));
create policy notes_read on public.team_notes for select to authenticated using(public.is_team_member(project_id));
create policy notes_create on public.team_notes for insert to authenticated with check(author_id=(select auth.uid()) and public.is_team_member(project_id));
create policy publications_read on public.publications for select to anon,authenticated using(status='published' or author_id=(select auth.uid()) or public.is_admin());
create policy publications_create on public.publications for insert to authenticated with check(author_id=(select auth.uid()));
create policy publications_update on public.publications for update to authenticated using(author_id=(select auth.uid()) or public.is_admin()) with check(author_id=(select auth.uid()) or public.is_admin());
create policy reports_create on public.reports for insert to authenticated with check(reporter_id=(select auth.uid()));
create policy reports_read on public.reports for select to authenticated using(reporter_id=(select auth.uid()) or public.is_admin());
create policy reports_review on public.reports for update to authenticated using(public.is_admin()) with check(public.is_admin());
-- Aggregated metrics only, no individual schools or student profiles revealed.
create or replace function public.community_stats() returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('members',(select count(*) from public.profiles),
 'publications',(select count(*) from public.publications where status='published'),
 'projects',(select count(*) from public.projects where status='open'),
 'bahrain',(select count(*) from public.profiles where country='Bahrain'),
 'schools',(select count(distinct lower(trim(school))) from public.profiles where school is not null and length(trim(school))>0));
$$;
grant execute on function public.community_stats() to anon, authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_verified_mentor(uuid) to authenticated;
grant execute on function public.is_team_member(uuid) to authenticated;
-- Founder: AFTER signing up, replace the UUID below with your auth.users.id and run manually:
-- insert into public.admin_users(user_id) values ('YOUR-USER-UUID');