-- ============================================================
-- PaintMatch — Painter Role Tables
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- ── 1. painter_profiles ──────────────────────────────────────────────────────

create table if not exists public.painter_profiles (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  company_name        text not null default '',
  contact_name        text not null default '',
  phone               text not null default '',
  email               text not null default '',
  bio                 text not null default '',
  service_areas       text[]    not null default '{}',
  specialties         text[]    not null default '{}',
  years_experience    int       not null default 0,
  license_number      text,
  is_insured          boolean   not null default false,
  is_verified         boolean   not null default false,
  subscription_active boolean   not null default false,
  avg_rating          numeric(3,2) not null default 0.0,
  total_reviews       int       not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- One profile per user
create unique index if not exists painter_profiles_user_id_idx
  on public.painter_profiles(user_id);

-- Index for homeowner directory query (active + verified + rating sort)
create index if not exists painter_profiles_active_idx
  on public.painter_profiles(subscription_active, is_verified, avg_rating desc);

-- Auto-update updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists painter_profiles_updated_at on public.painter_profiles;
create trigger painter_profiles_updated_at
  before update on public.painter_profiles
  for each row execute function public.set_updated_at();

-- ── 2. painter_leads ─────────────────────────────────────────────────────────

create table if not exists public.painter_leads (
  id              uuid primary key default gen_random_uuid(),
  painter_id      uuid not null references public.painter_profiles(id) on delete cascade,
  homeowner_id    uuid references auth.users(id) on delete set null,
  project_id      uuid references public.user_projects(id) on delete set null,
  contact_name    text not null default '',
  contact_email   text not null default '',
  contact_phone   text not null default '',
  message         text not null default '',
  status          text not null default 'new'
                    check (status in ('new', 'viewed', 'responded', 'closed')),
  created_at      timestamptz not null default now()
);

-- Painter sees their own leads (ordered by newest first)
create index if not exists painter_leads_painter_id_idx
  on public.painter_leads(painter_id, created_at desc);

-- ── 3. Row-Level Security ─────────────────────────────────────────────────────

alter table public.painter_profiles enable row level security;
alter table public.painter_leads     enable row level security;

-- painter_profiles: public read of active profiles; owner can manage their own
create policy "active profiles are public"
  on public.painter_profiles for select
  using (subscription_active = true);

create policy "owner can view own profile"
  on public.painter_profiles for select
  using (user_id = auth.uid());

create policy "owner can insert own profile"
  on public.painter_profiles for insert
  with check (user_id = auth.uid());

create policy "owner can update own profile"
  on public.painter_profiles for update
  using (user_id = auth.uid());

-- painter_leads: homeowners insert, painter reads their own leads
create policy "anyone authenticated can send lead"
  on public.painter_leads for insert
  with check (auth.role() = 'authenticated');

create policy "painter sees own leads"
  on public.painter_leads for select
  using (
    painter_id in (
      select id from public.painter_profiles
      where user_id = auth.uid()
    )
  );

create policy "painter updates own lead status"
  on public.painter_leads for update
  using (
    painter_id in (
      select id from public.painter_profiles
      where user_id = auth.uid()
    )
  );

-- ── 4. Supabase Storage — room-images bucket ──────────────────────────────────
-- Run this if you haven't created the bucket yet.
-- Note: bucket creation via SQL requires the storage extension.
-- Alternatively create it in Dashboard → Storage → New Bucket → "room-images" (Public ON)

insert into storage.buckets (id, name, public)
values ('room-images', 'room-images', true)
on conflict (id) do nothing;

-- Policy: authenticated users can upload their own files
create policy "authenticated users upload room images"
  on storage.objects for insert
  with check (
    bucket_id = 'room-images'
    and auth.role() = 'authenticated'
  );

-- Policy: public read
create policy "public read room images"
  on storage.objects for select
  using (bucket_id = 'room-images');

-- Policy: owner can delete their own files
create policy "owner deletes own room images"
  on storage.objects for delete
  using (
    bucket_id = 'room-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
