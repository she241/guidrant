-- Guidrent core backend for Supabase/PostgreSQL
-- Run with: supabase db push  OR paste into the Supabase SQL editor.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- Enums ----------------------------------------------------------------------
do $$ begin
  create type public.app_role as enum ('seeker', 'agent', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.account_status as enum ('active', 'suspended', 'deleted');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.verification_status as enum ('unverified', 'pending', 'verified', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.listing_status as enum ('draft', 'pending', 'published', 'rejected', 'rented', 'archived');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.listing_type as enum ('rent', 'short_let', 'sale');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.rent_frequency as enum ('nightly', 'weekly', 'monthly', 'yearly', 'one_time');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tour_type as enum ('in_person', 'video');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tour_status as enum ('requested', 'confirmed', 'rescheduled', 'completed', 'cancelled', 'declined');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.report_status as enum ('open', 'reviewing', 'resolved', 'dismissed');
exception when duplicate_object then null; end $$;

-- Shared trigger -------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- Profiles -------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null default 'seeker',
  full_name text not null default '',
  avatar_url text,
  city text default 'Accra',
  country_code text not null default 'GH',
  bio text,
  status public.account_status not null default 'active',
  last_seen_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.seeker_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone text,
  whatsapp text,
  preferred_areas text[] not null default '{}',
  budget_min numeric(14,2),
  budget_max numeric(14,2),
  currency char(3) not null default 'GHS',
  move_in_date date,
  bedrooms_min smallint check (bedrooms_min is null or bedrooms_min >= 0),
  property_types text[] not null default '{}',
  furnishing_preference text,
  pets boolean,
  notes text,
  alert_enabled boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (budget_min is null or budget_max is null or budget_min <= budget_max)
);

create table if not exists public.agent_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  agency_name text,
  public_phone text,
  public_whatsapp text,
  public_email text,
  website_url text,
  service_areas text[] not null default '{}',
  years_experience smallint check (years_experience is null or years_experience >= 0),
  license_number text,
  verification_status public.verification_status not null default 'unverified',
  verification_note text,
  rating numeric(3,2) not null default 0 check (rating between 0 and 5),
  review_count integer not null default 0 check (review_count >= 0),
  response_time_minutes integer,
  accepts_whatsapp boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.agent_verification_documents (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agent_profiles(user_id) on delete cascade,
  document_type text not null,
  storage_path text not null,
  review_status public.verification_status not null default 'pending',
  reviewer_id uuid references public.profiles(id) on delete set null,
  reviewer_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

-- Listings -------------------------------------------------------------------
create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid references public.agent_profiles(user_id) on delete set null,
  title text not null,
  slug text not null unique,
  description text not null default '',
  listing_type public.listing_type not null default 'rent',
  price numeric(14,2) not null check (price >= 0),
  currency char(3) not null default 'GHS',
  rent_frequency public.rent_frequency not null default 'monthly',
  advance_months smallint check (advance_months is null or advance_months >= 0),
  service_charge numeric(14,2) check (service_charge is null or service_charge >= 0),
  area text not null,
  city text not null default 'Accra',
  region text not null default 'Greater Accra',
  address_text text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  property_type text not null,
  bedrooms smallint not null default 0 check (bedrooms >= 0),
  bathrooms smallint not null default 0 check (bathrooms >= 0),
  toilets smallint not null default 0 check (toilets >= 0),
  parking smallint not null default 0 check (parking >= 0),
  furnished boolean not null default false,
  amenities text[] not null default '{}',
  available_from date,
  status public.listing_status not null default 'draft',
  is_featured boolean not null default false,
  is_verified boolean not null default false,
  view_count bigint not null default 0,
  source_name text,
  source_url text,
  source_external_id text,
  source_agent_name text,
  imported_at timestamptz,
  rejection_reason text,
  published_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180),
  check (agent_id is not null or source_url is not null)
);

create table if not exists public.property_photos (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  storage_path text,
  external_url text,
  alt_text text,
  sort_order integer not null default 0,
  is_cover boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  check (storage_path is not null or external_url is not null)
);

create unique index if not exists property_one_cover_idx
  on public.property_photos(property_id) where is_cover;
create index if not exists properties_status_created_idx on public.properties(status, created_at desc);
create index if not exists properties_area_trgm_idx on public.properties using gin (area gin_trgm_ops);
create index if not exists properties_title_trgm_idx on public.properties using gin (title gin_trgm_ops);
create index if not exists properties_agent_idx on public.properties(agent_id);
create index if not exists property_photos_property_idx on public.property_photos(property_id, sort_order);

-- Marketplace activity -------------------------------------------------------
create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, property_id)
);

create table if not exists public.tour_requests (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  seeker_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  agent_id uuid references public.agent_profiles(user_id) on delete set null,
  tour_type public.tour_type not null default 'in_person',
  preferred_start timestamptz not null,
  preferred_end timestamptz,
  status public.tour_status not null default 'requested',
  seeker_message text,
  agent_note text,
  confirmed_start timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (preferred_end is null or preferred_end > preferred_start)
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  seeker_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  agent_id uuid not null references public.agent_profiles(user_id) on delete cascade,
  last_message_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique (property_id, seeker_id, agent_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists messages_conversation_created_idx on public.messages(conversation_id, created_at);
create index if not exists tour_requests_seeker_idx on public.tour_requests(seeker_id, created_at desc);
create index if not exists tour_requests_agent_idx on public.tour_requests(agent_id, created_at desc);

create table if not exists public.agent_reviews (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agent_profiles(user_id) on delete cascade,
  reviewer_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  property_id uuid references public.properties(id) on delete set null,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  status text not null default 'published' check (status in ('pending','published','hidden')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (agent_id, reviewer_id, property_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  agent_id uuid references public.agent_profiles(user_id) on delete cascade,
  reason text not null,
  details text,
  status public.report_status not null default 'open',
  assigned_admin_id uuid references public.profiles(id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (property_id is not null or agent_id is not null)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.audit_logs (
  id bigint generated by default as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

-- Helper functions -----------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin' and status = 'active'
  );
$$;

create or replace function public.is_agent()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'agent' and status = 'active'
  );
$$;

create or replace function public.owns_property(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.properties
    where id = p_property_id and agent_id = (select auth.uid())
  ) or public.is_admin();
$$;

create or replace function public.participates_in_conversation(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversations
    where id = p_conversation_id
      and ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id)
  ) or public.is_admin();
$$;

create or replace function public.make_slug(input_text text)
returns text
language sql
immutable
security invoker
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(input_text,'')), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function public.assign_property_slug()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare base_slug text;
begin
  base_slug := public.make_slug(new.title || '-' || new.area);
  if new.slug is null or new.slug = '' then
    new.slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  end if;
  return new;
end;
$$;

create or replace function public.assign_tour_agent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select agent_id into new.agent_id from public.properties where id = new.property_id;
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare requested_role public.app_role;
begin
  requested_role := case
    when new.raw_user_meta_data->>'role' = 'agent' then 'agent'::public.app_role
    else 'seeker'::public.app_role
  end;

  insert into public.profiles (id, role, full_name, avatar_url)
  values (
    new.id,
    requested_role,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;

  if requested_role = 'agent' then
    insert into public.agent_profiles (user_id) values (new.id) on conflict do nothing;
  else
    insert into public.seeker_profiles (user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end;
$$;

create or replace function public.refresh_agent_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare target_agent uuid;
begin
  if tg_op = 'DELETE' then target_agent := old.agent_id; else target_agent := new.agent_id; end if;
  update public.agent_profiles a
  set rating = coalesce(s.avg_rating, 0),
      review_count = coalesce(s.review_count, 0),
      updated_at = timezone('utc', now())
  from (
    select agent_id, round(avg(rating)::numeric, 2) avg_rating, count(*)::int review_count
    from public.agent_reviews
    where agent_id = target_agent and status = 'published'
    group by agent_id
  ) s
  where a.user_id = target_agent;

  if not found then
    update public.agent_profiles set rating = 0, review_count = 0 where user_id = target_agent;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_admin() or auth.role() = 'service_role') and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'Only an administrator can change account role or status';
  end if;
  return new;
end;
$$;

create or replace function public.protect_agent_moderation_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() <= 1 and not (public.is_admin() or auth.role() = 'service_role') and (
    new.verification_status is distinct from old.verification_status or
    new.verification_note is distinct from old.verification_note or
    new.rating is distinct from old.rating or
    new.review_count is distinct from old.review_count
  ) then
    raise exception 'Only an administrator can change agent verification or rating fields';
  end if;
  return new;
end;
$$;

create or replace function public.protect_property_moderation_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_admin() or auth.role() = 'service_role') then
    if new.agent_id is distinct from old.agent_id or
       new.is_verified is distinct from old.is_verified or
       new.is_featured is distinct from old.is_featured or
       new.rejection_reason is distinct from old.rejection_reason or
       new.published_at is distinct from old.published_at or
       new.source_name is distinct from old.source_name or
       new.source_url is distinct from old.source_url or
       new.source_external_id is distinct from old.source_external_id or
       new.source_agent_name is distinct from old.source_agent_name or
       new.imported_at is distinct from old.imported_at then
      raise exception 'Only an administrator can change moderation or import fields';
    end if;
    if new.status in ('published','rejected') and new.status is distinct from old.status then
      raise exception 'Only an administrator can publish or reject a listing';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.protect_tour_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.property_id is distinct from old.property_id or new.seeker_id is distinct from old.seeker_id or new.agent_id is distinct from old.agent_id then
    raise exception 'Tour participants and property cannot be changed';
  end if;
  if not (public.is_admin() or auth.role() = 'service_role') and (select auth.uid()) = old.seeker_id then
    if new.status not in (old.status, 'cancelled') or
       new.agent_note is distinct from old.agent_note or
       new.confirmed_start is distinct from old.confirmed_start then
      raise exception 'Seekers may only edit their message or cancel a tour';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.protect_message_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.conversation_id is distinct from old.conversation_id or new.sender_id is distinct from old.sender_id or new.body is distinct from old.body then
    raise exception 'Only message read status can be updated';
  end if;
  return new;
end;
$$;

create or replace function public.protect_conversation_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.property_id is distinct from old.property_id or new.seeker_id is distinct from old.seeker_id or new.agent_id is distinct from old.agent_id then
    raise exception 'Conversation participants and property cannot be changed';
  end if;
  return new;
end;
$$;

create or replace function public.protect_review_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_admin() or auth.role() = 'service_role') and (
    new.agent_id is distinct from old.agent_id or
    new.reviewer_id is distinct from old.reviewer_id or
    new.property_id is distinct from old.property_id or
    new.status is distinct from old.status
  ) then
    raise exception 'Review ownership and moderation fields cannot be changed';
  end if;
  return new;
end;
$$;

create or replace function public.search_properties(
  p_query text default null,
  p_area text default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_bedrooms smallint default null,
  p_property_type text default null,
  p_furnished boolean default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  id uuid,
  title text,
  slug text,
  area text,
  city text,
  price numeric,
  currency char(3),
  rent_frequency public.rent_frequency,
  bedrooms smallint,
  bathrooms smallint,
  property_type text,
  furnished boolean,
  is_featured boolean,
  is_verified boolean,
  cover_url text,
  source_url text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    p.id, p.title, p.slug, p.area, p.city, p.price, p.currency,
    p.rent_frequency, p.bedrooms, p.bathrooms, p.property_type,
    p.furnished, p.is_featured, p.is_verified,
    coalesce(pp.external_url,
      case when pp.storage_path is not null then
        current_setting('app.settings.supabase_url', true) || '/storage/v1/object/public/property-images/' || pp.storage_path
      end
    ) as cover_url,
    p.source_url, p.created_at
  from public.properties p
  left join lateral (
    select storage_path, external_url
    from public.property_photos
    where property_id = p.id
    order by is_cover desc, sort_order asc, created_at asc
    limit 1
  ) pp on true
  where p.status = 'published'
    and (p_query is null or p_query = '' or p.title % p_query or p.area % p_query or p.description ilike '%' || p_query || '%')
    and (p_area is null or p_area = '' or p.area ilike '%' || p_area || '%')
    and (p_min_price is null or p.price >= p_min_price)
    and (p_max_price is null or p.price <= p_max_price)
    and (p_bedrooms is null or p.bedrooms >= p_bedrooms)
    and (p_property_type is null or p_property_type = '' or lower(p.property_type) = lower(p_property_type))
    and (p_furnished is null or p.furnished = p_furnished)
  order by p.is_featured desc, p.created_at desc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
$$;

-- Views ----------------------------------------------------------------------
create or replace view public.public_agents
with (security_invoker = true)
as
select
  p.id,
  p.full_name,
  p.avatar_url,
  p.bio,
  p.city,
  a.agency_name,
  a.public_phone,
  a.public_whatsapp,
  a.public_email,
  a.website_url,
  a.service_areas,
  a.years_experience,
  a.verification_status,
  a.rating,
  a.review_count,
  a.response_time_minutes,
  a.accepts_whatsapp
from public.profiles p
join public.agent_profiles a on a.user_id = p.id
where p.role = 'agent' and p.status = 'active';

create or replace view public.property_cards
with (security_invoker = true)
as
select
  p.id,
  p.agent_id,
  p.title,
  p.slug,
  p.description,
  p.listing_type,
  p.price,
  p.currency,
  p.rent_frequency,
  p.advance_months,
  p.area,
  p.city,
  p.region,
  p.latitude,
  p.longitude,
  p.property_type,
  p.bedrooms,
  p.bathrooms,
  p.toilets,
  p.parking,
  p.furnished,
  p.amenities,
  p.available_from,
  p.is_featured,
  p.is_verified,
  p.source_name,
  p.source_url,
  p.source_agent_name,
  p.created_at,
  coalesce(pp.external_url,
    case when pp.storage_path is not null then
      current_setting('app.settings.supabase_url', true) || '/storage/v1/object/public/property-images/' || pp.storage_path
    end
  ) as cover_url,
  coalesce(pa.full_name, p.source_agent_name) as agent_name,
  pa.avatar_url as agent_avatar_url,
  ap.verification_status as agent_verification_status
from public.properties p
left join lateral (
  select storage_path, external_url
  from public.property_photos
  where property_id = p.id
  order by is_cover desc, sort_order asc, created_at asc
  limit 1
) pp on true
left join public.profiles pa on pa.id = p.agent_id
left join public.agent_profiles ap on ap.user_id = p.agent_id
where p.status = 'published';

-- Triggers -------------------------------------------------------------------
drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists profiles_protect_fields on public.profiles;
create trigger profiles_protect_fields before update on public.profiles
for each row execute function public.protect_profile_fields();

drop trigger if exists seeker_profiles_updated_at on public.seeker_profiles;
create trigger seeker_profiles_updated_at before update on public.seeker_profiles
for each row execute function public.set_updated_at();

drop trigger if exists agent_profiles_updated_at on public.agent_profiles;
create trigger agent_profiles_updated_at before update on public.agent_profiles
for each row execute function public.set_updated_at();
drop trigger if exists agent_profiles_protect_fields on public.agent_profiles;
create trigger agent_profiles_protect_fields before update on public.agent_profiles
for each row execute function public.protect_agent_moderation_fields();

drop trigger if exists properties_updated_at on public.properties;
create trigger properties_updated_at before update on public.properties
for each row execute function public.set_updated_at();
drop trigger if exists properties_protect_fields on public.properties;
create trigger properties_protect_fields before update on public.properties
for each row execute function public.protect_property_moderation_fields();

drop trigger if exists properties_assign_slug on public.properties;
create trigger properties_assign_slug before insert or update of title, area, slug on public.properties
for each row execute function public.assign_property_slug();

drop trigger if exists tour_requests_updated_at on public.tour_requests;
create trigger tour_requests_updated_at before update on public.tour_requests
for each row execute function public.set_updated_at();
drop trigger if exists tour_requests_protect_fields on public.tour_requests;
create trigger tour_requests_protect_fields before update on public.tour_requests
for each row execute function public.protect_tour_fields();

drop trigger if exists tour_requests_assign_agent on public.tour_requests;
create trigger tour_requests_assign_agent before insert or update of property_id on public.tour_requests
for each row execute function public.assign_tour_agent();

drop trigger if exists reviews_updated_at on public.agent_reviews;
create trigger reviews_updated_at before update on public.agent_reviews
for each row execute function public.set_updated_at();
drop trigger if exists reviews_protect_fields on public.agent_reviews;
create trigger reviews_protect_fields before update on public.agent_reviews
for each row execute function public.protect_review_fields();

drop trigger if exists reviews_refresh_rating on public.agent_reviews;
create trigger reviews_refresh_rating after insert or update or delete on public.agent_reviews
for each row execute function public.refresh_agent_rating();

drop trigger if exists messages_protect_fields on public.messages;
create trigger messages_protect_fields before update on public.messages
for each row execute function public.protect_message_fields();

drop trigger if exists conversations_protect_fields on public.conversations;
create trigger conversations_protect_fields before update on public.conversations
for each row execute function public.protect_conversation_fields();

drop trigger if exists reports_updated_at on public.reports;
create trigger reports_updated_at before update on public.reports
for each row execute function public.set_updated_at();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Row level security ---------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.seeker_profiles enable row level security;
alter table public.agent_profiles enable row level security;
alter table public.agent_verification_documents enable row level security;
alter table public.properties enable row level security;
alter table public.property_photos enable row level security;
alter table public.favorites enable row level security;
alter table public.tour_requests enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.agent_reviews enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

-- Drop policies so migration can be re-run safely.
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies
           where schemaname = 'public' and tablename in (
             'profiles','seeker_profiles','agent_profiles','agent_verification_documents',
             'properties','property_photos','favorites','tour_requests','conversations',
             'messages','agent_reviews','reports','notifications','audit_logs'
           )
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

create policy "public can view active agent profiles"
on public.profiles for select
to anon, authenticated
using (role = 'agent' and status = 'active');

create policy "users can view own profile"
on public.profiles for select
to authenticated
using ((select auth.uid()) = id or public.is_admin());

create policy "users can update own profile"
on public.profiles for update
to authenticated
using ((select auth.uid()) = id or public.is_admin())
with check ((select auth.uid()) = id or public.is_admin());

create policy "seekers manage own seeker profile"
on public.seeker_profiles for all
to authenticated
using ((select auth.uid()) = user_id or public.is_admin())
with check ((select auth.uid()) = user_id or public.is_admin());

create policy "public can view verified agents"
on public.agent_profiles for select
to anon, authenticated
using (verification_status = 'verified' or (select auth.uid()) = user_id or public.is_admin());

create policy "agents manage own agent profile"
on public.agent_profiles for all
to authenticated
using ((select auth.uid()) = user_id or public.is_admin())
with check (
  (
    (select auth.uid()) = user_id and public.is_agent()
    and verification_status = 'unverified' and rating = 0 and review_count = 0
  ) or public.is_admin()
);

create policy "agents manage own verification documents"
on public.agent_verification_documents for all
to authenticated
using ((select auth.uid()) = agent_id or public.is_admin())
with check ((select auth.uid()) = agent_id or public.is_admin());

create policy "published properties are public"
on public.properties for select
to anon, authenticated
using (status = 'published' or agent_id = (select auth.uid()) or public.is_admin());

create policy "agents create own properties"
on public.properties for insert
to authenticated
with check (
  (
    (select auth.uid()) = agent_id and public.is_agent()
    and status in ('draft','pending')
    and is_verified = false and is_featured = false
    and source_name is null and source_url is null and source_external_id is null
    and source_agent_name is null and imported_at is null and published_at is null
  ) or public.is_admin()
);

create policy "agents update own properties"
on public.properties for update
to authenticated
using (agent_id = (select auth.uid()) or public.is_admin())
with check (agent_id = (select auth.uid()) or public.is_admin());

create policy "agents delete own draft properties"
on public.properties for delete
to authenticated
using ((agent_id = (select auth.uid()) and status in ('draft','rejected','archived')) or public.is_admin());

create policy "public can view published property photos"
on public.property_photos for select
to anon, authenticated
using (
  exists (select 1 from public.properties p where p.id = property_id and (p.status = 'published' or p.agent_id = (select auth.uid())))
  or public.is_admin()
);

create policy "agents manage own property photos"
on public.property_photos for all
to authenticated
using (public.owns_property(property_id))
with check (public.owns_property(property_id));

create policy "users manage own favorites"
on public.favorites for all
to authenticated
using ((select auth.uid()) = user_id or public.is_admin())
with check ((select auth.uid()) = user_id or public.is_admin());

create policy "participants view tours"
on public.tour_requests for select
to authenticated
using ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id or public.is_admin());

create policy "seekers request tours"
on public.tour_requests for insert
to authenticated
with check (
  (select auth.uid()) = seeker_id
  and status = 'requested'
  and agent_note is null
  and confirmed_start is null
);

create policy "tour participants update tours"
on public.tour_requests for update
to authenticated
using ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id or public.is_admin())
with check ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id or public.is_admin());

create policy "conversation participants view"
on public.conversations for select
to authenticated
using ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id or public.is_admin());

create policy "seekers start conversations"
on public.conversations for insert
to authenticated
with check (
  (select auth.uid()) = seeker_id
  and agent_id is not null
  and exists (select 1 from public.properties p where p.id = property_id and p.agent_id = agent_id and p.status = 'published')
);

create policy "conversation participants update"
on public.conversations for update
to authenticated
using ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id or public.is_admin())
with check ((select auth.uid()) = seeker_id or (select auth.uid()) = agent_id or public.is_admin());

create policy "conversation participants view messages"
on public.messages for select
to authenticated
using (public.participates_in_conversation(conversation_id));

create policy "conversation participants send messages"
on public.messages for insert
to authenticated
with check ((select auth.uid()) = sender_id and public.participates_in_conversation(conversation_id));

create policy "recipients mark messages read"
on public.messages for update
to authenticated
using (public.participates_in_conversation(conversation_id))
with check (public.participates_in_conversation(conversation_id));

create policy "published reviews are public"
on public.agent_reviews for select
to anon, authenticated
using (status = 'published' or reviewer_id = (select auth.uid()) or agent_id = (select auth.uid()) or public.is_admin());

create policy "seekers create own reviews"
on public.agent_reviews for insert
to authenticated
with check ((select auth.uid()) = reviewer_id and reviewer_id <> agent_id and status = 'published');

create policy "seekers update own reviews"
on public.agent_reviews for update
to authenticated
using ((select auth.uid()) = reviewer_id or public.is_admin())
with check ((select auth.uid()) = reviewer_id or public.is_admin());

create policy "users create and view own reports"
on public.reports for select
to authenticated
using ((select auth.uid()) = reporter_id or public.is_admin());

create policy "users create reports"
on public.reports for insert
to authenticated
with check ((select auth.uid()) = reporter_id);

create policy "admins manage reports"
on public.reports for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "users view own notifications"
on public.notifications for select
to authenticated
using ((select auth.uid()) = user_id or public.is_admin());

create policy "users update own notifications"
on public.notifications for update
to authenticated
using ((select auth.uid()) = user_id or public.is_admin())
with check ((select auth.uid()) = user_id or public.is_admin());

create policy "admins create notifications"
on public.notifications for insert
to authenticated
with check (public.is_admin());

create policy "admins view audit logs"
on public.audit_logs for select
to authenticated
using (public.is_admin());

-- Grants ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select on public.public_agents, public.property_cards to anon, authenticated;
grant select on public.properties, public.property_photos, public.agent_profiles, public.profiles, public.agent_reviews to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.search_properties(text,text,numeric,numeric,smallint,text,boolean,integer,integer) to anon, authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_agent() to authenticated;
grant execute on function public.owns_property(uuid) to authenticated;
grant execute on function public.participates_in_conversation(uuid) to authenticated;

-- Storage buckets and policies ----------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('property-images', 'property-images', true, 10485760, array['image/jpeg','image/png','image/webp']),
  ('verification-documents', 'verification-documents', false, 10485760, array['image/jpeg','image/png','application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Recreate storage policies.
do $$
declare r record;
begin
  for r in select policyname from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and policyname like 'Guidrent:%'
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy "Guidrent: public avatar reads"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'avatars');

create policy "Guidrent: users upload own avatars"
on storage.objects for insert
to authenticated
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Guidrent: users update own avatars"
on storage.objects for update
to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Guidrent: users delete own avatars"
on storage.objects for delete
to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Guidrent: public property image reads"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'property-images');

create policy "Guidrent: agents upload property images"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'property-images'
  and public.owns_property(((storage.foldername(name))[1])::uuid)
);

create policy "Guidrent: agents update property images"
on storage.objects for update
to authenticated
using (
  bucket_id = 'property-images'
  and public.owns_property(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'property-images'
  and public.owns_property(((storage.foldername(name))[1])::uuid)
);

create policy "Guidrent: agents delete property images"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'property-images'
  and public.owns_property(((storage.foldername(name))[1])::uuid)
);

create policy "Guidrent: agents manage own verification files"
on storage.objects for all
to authenticated
using (
  bucket_id = 'verification-documents'
  and ((storage.foldername(name))[1] = (select auth.uid())::text or public.is_admin())
)
with check (
  bucket_id = 'verification-documents'
  and ((storage.foldername(name))[1] = (select auth.uid())::text or public.is_admin())
);

-- Realtime -------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.tour_requests;
exception when duplicate_object then null; end $$;


-- ===== PRODUCTION ENHANCEMENTS =====

-- Guidrent production enhancements
-- Apply after 202607270001_guidrent_core.sql

create extension if not exists pgcrypto;

-- Additional enums -----------------------------------------------------------
do $$ begin
  create type public.application_status as enum ('draft', 'submitted', 'under_review', 'approved', 'rejected', 'withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.data_request_type as enum ('access', 'export', 'correct', 'delete', 'object');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.data_request_status as enum ('submitted', 'verifying', 'processing', 'completed', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.claim_status as enum ('submitted', 'reviewing', 'approved', 'rejected');
exception when duplicate_object then null; end $$;

-- Existing-table enhancements ------------------------------------------------
alter table public.profiles
  add column if not exists locale text not null default 'en-GH',
  add column if not exists timezone text not null default 'Africa/Accra',
  add column if not exists onboarding_completed boolean not null default false,
  add column if not exists marketing_opt_in boolean not null default false,
  add column if not exists terms_version text,
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists privacy_version text,
  add column if not exists privacy_accepted_at timestamptz,
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists deleted_at timestamptz;

alter table public.properties
  add column if not exists digital_address text,
  add column if not exists landmark text,
  add column if not exists floor_area_sqm numeric(10,2),
  add column if not exists year_built smallint,
  add column if not exists deposit_amount numeric(14,2),
  add column if not exists utilities_included boolean not null default false,
  add column if not exists pets_allowed boolean,
  add column if not exists smoking_allowed boolean,
  add column if not exists minimum_stay_nights integer,
  add column if not exists video_url text,
  add column if not exists virtual_tour_url text,
  add column if not exists moderation_score numeric(5,2),
  add column if not exists moderation_flags jsonb not null default '[]'::jsonb,
  add column if not exists expires_at timestamptz,
  add column if not exists last_verified_at timestamptz,
  add column if not exists unavailable_reason text;

alter table public.messages
  add column if not exists attachments jsonb not null default '[]'::jsonb,
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz;

alter table public.agent_profiles
  add column if not exists languages text[] not null default '{}',
  add column if not exists office_address text,
  add column if not exists digital_address text,
  add column if not exists identity_verified_at timestamptz,
  add column if not exists agency_verified_at timestamptz;

-- Saved searches and notification controls -----------------------------------
create table if not exists public.saved_searches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  filters jsonb not null default '{}'::jsonb,
  alert_frequency text not null default 'daily' check (alert_frequency in ('instant', 'daily', 'weekly', 'off')),
  active boolean not null default true,
  last_run_at timestamptz,
  last_result_count integer,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  in_app boolean not null default true,
  email boolean not null default true,
  sms boolean not null default false,
  whatsapp boolean not null default false,
  tour_updates boolean not null default true,
  message_updates boolean not null default true,
  listing_alerts boolean not null default true,
  application_updates boolean not null default true,
  marketing boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

-- Agent availability and rental applications --------------------------------
create table if not exists public.agent_availability (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agent_profiles(user_id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  tour_type public.tour_type not null default 'in_person',
  capacity smallint not null default 1 check (capacity between 1 and 20),
  booked_count smallint not null default 0 check (booked_count >= 0),
  active boolean not null default true,
  note text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (ends_at > starts_at),
  check (booked_count <= capacity)
);

create table if not exists public.rental_applications (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  applicant_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  agent_id uuid references public.agent_profiles(user_id) on delete set null,
  status public.application_status not null default 'draft',
  move_in_date date,
  lease_months smallint check (lease_months is null or lease_months between 1 and 120),
  occupant_count smallint not null default 1 check (occupant_count between 1 and 30),
  has_pets boolean,
  employment_status text,
  employer_name text,
  monthly_income numeric(14,2),
  income_currency char(3) not null default 'GHS',
  applicant_message text,
  agent_note text,
  submitted_at timestamptz,
  decided_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (property_id, applicant_id)
);

create table if not exists public.application_documents (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.rental_applications(id) on delete cascade,
  applicant_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  document_type text not null,
  storage_path text not null,
  original_filename text,
  mime_type text,
  file_size_bytes bigint,
  created_at timestamptz not null default timezone('utc', now())
);

-- Privacy, consent, safety and ownership -------------------------------------
create table if not exists public.consent_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  consent_type text not null,
  policy_version text not null,
  granted boolean not null,
  source text not null default 'web',
  user_agent text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.data_subject_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_type public.data_request_type not null,
  status public.data_request_status not null default 'submitted',
  details text,
  verification_note text,
  resolution_note text,
  assigned_admin_id uuid references public.profiles(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.blocked_users (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.listing_claims (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  claimant_id uuid not null references public.agent_profiles(user_id) on delete cascade,
  status public.claim_status not null default 'submitted',
  evidence_storage_path text,
  explanation text,
  reviewer_id uuid references public.profiles(id) on delete set null,
  reviewer_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (property_id, claimant_id)
);

create table if not exists public.shortlist_notes (
  user_id uuid not null references public.seeker_profiles(user_id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  note text,
  personal_rating smallint check (personal_rating is null or personal_rating between 1 and 5),
  rank_order integer,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, property_id)
);

-- Pricing and privacy-friendly analytics ------------------------------------
create table if not exists public.property_price_history (
  id bigint generated by default as identity primary key,
  property_id uuid not null references public.properties(id) on delete cascade,
  old_price numeric(14,2),
  new_price numeric(14,2) not null,
  currency char(3) not null,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.property_daily_stats (
  property_id uuid not null references public.properties(id) on delete cascade,
  stat_date date not null default current_date,
  views bigint not null default 0,
  saves bigint not null default 0,
  tour_requests bigint not null default 0,
  applications bigint not null default 0,
  messages_started bigint not null default 0,
  primary key (property_id, stat_date)
);

-- Indexes --------------------------------------------------------------------
create index if not exists saved_searches_user_idx on public.saved_searches(user_id, active);
create index if not exists availability_agent_start_idx on public.agent_availability(agent_id, starts_at);
create index if not exists availability_property_start_idx on public.agent_availability(property_id, starts_at);
create index if not exists applications_applicant_idx on public.rental_applications(applicant_id, created_at desc);
create index if not exists applications_agent_idx on public.rental_applications(agent_id, created_at desc);
create index if not exists applications_property_idx on public.rental_applications(property_id, status);
create index if not exists data_requests_user_idx on public.data_subject_requests(user_id, created_at desc);
create index if not exists claims_status_idx on public.listing_claims(status, created_at desc);
create index if not exists price_history_property_idx on public.property_price_history(property_id, changed_at desc);

-- Updated-at triggers ---------------------------------------------------------
do $$ begin
  create trigger saved_searches_updated_at before update on public.saved_searches
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger notification_preferences_updated_at before update on public.notification_preferences
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger agent_availability_updated_at before update on public.agent_availability
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger rental_applications_updated_at before update on public.rental_applications
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger data_subject_requests_updated_at before update on public.data_subject_requests
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger listing_claims_updated_at before update on public.listing_claims
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger shortlist_notes_updated_at before update on public.shortlist_notes
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

-- Business rules and notifications ------------------------------------------
create or replace function public.assign_application_agent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select agent_id into new.agent_id from public.properties where id = new.property_id;
  if new.status = 'submitted' and new.submitted_at is null then
    new.submitted_at := timezone('utc', now());
  end if;
  return new;
end;
$$;

drop trigger if exists rental_applications_assign_agent on public.rental_applications;
create trigger rental_applications_assign_agent
before insert or update of property_id, status on public.rental_applications
for each row execute function public.assign_application_agent();

create or replace function public.protect_application_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_admin() then return new; end if;

  if auth.uid() = old.applicant_id then
    new.property_id := old.property_id;
    new.applicant_id := old.applicant_id;
    new.agent_id := old.agent_id;
    new.agent_note := old.agent_note;
    new.decided_at := old.decided_at;
    if old.status not in ('draft', 'submitted') then
      raise exception 'This application can no longer be edited by the applicant';
    end if;
    if new.status not in ('draft', 'submitted', 'withdrawn') then
      raise exception 'Applicants may only draft, submit or withdraw an application';
    end if;
  elsif auth.uid() = old.agent_id then
    new.property_id := old.property_id;
    new.applicant_id := old.applicant_id;
    new.agent_id := old.agent_id;
    new.move_in_date := old.move_in_date;
    new.lease_months := old.lease_months;
    new.occupant_count := old.occupant_count;
    new.has_pets := old.has_pets;
    new.employment_status := old.employment_status;
    new.employer_name := old.employer_name;
    new.monthly_income := old.monthly_income;
    new.income_currency := old.income_currency;
    new.applicant_message := old.applicant_message;
    if new.status in ('approved', 'rejected') and old.status is distinct from new.status then
      new.decided_at := timezone('utc', now());
    end if;
  else
    raise exception 'Not permitted to update this application';
  end if;
  return new;
end;
$$;

drop trigger if exists rental_applications_protect_fields on public.rental_applications;
create trigger rental_applications_protect_fields
before update on public.rental_applications
for each row execute function public.protect_application_fields();

create or replace function public.capture_property_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.price is distinct from new.price or old.currency is distinct from new.currency then
    insert into public.property_price_history(property_id, old_price, new_price, currency, changed_by)
    values (new.id, old.price, new.price, new.currency, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists properties_price_history on public.properties;
create trigger properties_price_history
after update of price, currency on public.properties
for each row execute function public.capture_property_price_change();

create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare recipient uuid;
declare property_title text;
begin
  select case when c.seeker_id = new.sender_id then c.agent_id else c.seeker_id end,
         p.title
  into recipient, property_title
  from public.conversations c
  join public.properties p on p.id = c.property_id
  where c.id = new.conversation_id;

  if recipient is not null and not exists (
    select 1 from public.blocked_users b
    where b.blocker_id = recipient and b.blocked_id = new.sender_id
  ) then
    insert into public.notifications(user_id, type, title, body, data)
    values (recipient, 'message', 'New Guidrent message',
      'You received a new message about ' || coalesce(property_title, 'a property') || '.',
      jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id));
  end if;
  return new;
end;
$$;

drop trigger if exists messages_create_notification on public.messages;
create trigger messages_create_notification
after insert on public.messages
for each row execute function public.notify_new_message();

create or replace function public.notify_application_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare property_title text;
declare recipient uuid;
declare notice_title text;
begin
  select title into property_title from public.properties where id = new.property_id;

  if tg_op = 'INSERT' and new.status = 'submitted' then
    recipient := new.agent_id;
    notice_title := 'New rental application';
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    recipient := case when auth.uid() = new.agent_id then new.applicant_id else new.agent_id end;
    notice_title := 'Application status updated';
  else
    return new;
  end if;

  if recipient is not null then
    insert into public.notifications(user_id, type, title, body, data)
    values (recipient, 'application', notice_title,
      'Application for ' || coalesce(property_title, 'a Guidrent property') || ' is now ' || replace(new.status::text, '_', ' ') || '.',
      jsonb_build_object('application_id', new.id, 'property_id', new.property_id, 'status', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists applications_create_notification on public.rental_applications;
create trigger applications_create_notification
after insert or update of status on public.rental_applications
for each row execute function public.notify_application_change();

create or replace function public.record_property_event(p_property_id uuid, p_event text default 'view')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.properties where id = p_property_id and status = 'published') then
    return;
  end if;

  insert into public.property_daily_stats(property_id, stat_date, views, saves, tour_requests, applications, messages_started)
  values (
    p_property_id,
    current_date,
    case when p_event = 'view' then 1 else 0 end,
    case when p_event = 'save' then 1 else 0 end,
    case when p_event = 'tour' then 1 else 0 end,
    case when p_event = 'application' then 1 else 0 end,
    case when p_event = 'message' then 1 else 0 end
  )
  on conflict (property_id, stat_date) do update set
    views = public.property_daily_stats.views + excluded.views,
    saves = public.property_daily_stats.saves + excluded.saves,
    tour_requests = public.property_daily_stats.tour_requests + excluded.tour_requests,
    applications = public.property_daily_stats.applications + excluded.applications,
    messages_started = public.property_daily_stats.messages_started + excluded.messages_started;

  if p_event = 'view' then
    update public.properties set view_count = view_count + 1 where id = p_property_id;
  end if;
end;
$$;

grant execute on function public.record_property_event(uuid, text) to anon, authenticated;

-- Row-level security ----------------------------------------------------------
alter table public.saved_searches enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.agent_availability enable row level security;
alter table public.rental_applications enable row level security;
alter table public.application_documents enable row level security;
alter table public.consent_records enable row level security;
alter table public.data_subject_requests enable row level security;
alter table public.blocked_users enable row level security;
alter table public.listing_claims enable row level security;
alter table public.shortlist_notes enable row level security;
alter table public.property_price_history enable row level security;
alter table public.property_daily_stats enable row level security;

create policy "users manage own saved searches" on public.saved_searches
for all using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create policy "users manage own notification preferences" on public.notification_preferences
for all using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create policy "public views active availability" on public.agent_availability
for select using (
  active = true and starts_at > timezone('utc', now()) and
  (property_id is null or exists (select 1 from public.properties p where p.id = property_id and p.status = 'published'))
  or agent_id = auth.uid() or public.is_admin()
);

create policy "agents manage own availability" on public.agent_availability
for all using (agent_id = auth.uid() or public.is_admin())
with check (agent_id = auth.uid() or public.is_admin());

create policy "application participants view" on public.rental_applications
for select using (applicant_id = auth.uid() or agent_id = auth.uid() or public.is_admin());

create policy "seekers create applications" on public.rental_applications
for insert with check (
  applicant_id = auth.uid() and status in ('draft', 'submitted') and
  exists (select 1 from public.properties p where p.id = property_id and p.status = 'published')
);

create policy "application participants update" on public.rental_applications
for update using (applicant_id = auth.uid() or agent_id = auth.uid() or public.is_admin())
with check (applicant_id = auth.uid() or agent_id = auth.uid() or public.is_admin());

create policy "application participants view documents" on public.application_documents
for select using (
  applicant_id = auth.uid() or public.is_admin() or exists (
    select 1 from public.rental_applications a
    where a.id = application_id and a.agent_id = auth.uid()
  )
);

create policy "applicants manage own application documents" on public.application_documents
for all using (applicant_id = auth.uid() or public.is_admin())
with check (applicant_id = auth.uid() or public.is_admin());

create policy "users manage own consent records" on public.consent_records
for select using (user_id = auth.uid() or public.is_admin());
create policy "users create own consent records" on public.consent_records
for insert with check (user_id = auth.uid() or public.is_admin());

create policy "users create and view own data requests" on public.data_subject_requests
for select using (user_id = auth.uid() or public.is_admin());
create policy "users submit own data requests" on public.data_subject_requests
for insert with check (user_id = auth.uid());
create policy "admins manage data requests" on public.data_subject_requests
for update using (public.is_admin()) with check (public.is_admin());

create policy "users manage own blocks" on public.blocked_users
for all using (blocker_id = auth.uid() or public.is_admin())
with check (blocker_id = auth.uid() or public.is_admin());

create policy "claimants view own claims" on public.listing_claims
for select using (claimant_id = auth.uid() or public.is_admin());
create policy "agents submit claims" on public.listing_claims
for insert with check (claimant_id = auth.uid() and public.is_agent());
create policy "admins manage claims" on public.listing_claims
for update using (public.is_admin()) with check (public.is_admin());

create policy "seekers manage shortlist notes" on public.shortlist_notes
for all using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create policy "public views published price history" on public.property_price_history
for select using (
  exists (select 1 from public.properties p where p.id = property_id and p.status = 'published')
  or exists (select 1 from public.properties p where p.id = property_id and p.agent_id = auth.uid())
  or public.is_admin()
);

create policy "agents view own property analytics" on public.property_daily_stats
for select using (
  exists (select 1 from public.properties p where p.id = property_id and p.agent_id = auth.uid())
  or public.is_admin()
);

-- Storage --------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('application-documents', 'application-documents', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp']),
  ('message-attachments', 'message-attachments', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Guidrent: applicants upload own application documents"
on storage.objects for insert to authenticated
with check (bucket_id = 'application-documents' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Guidrent: application participants read documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'application-documents' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or exists (
      select 1 from public.rental_applications a
      where a.id = case when (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$' then ((storage.foldername(name))[2])::uuid else null end and a.agent_id = auth.uid()
    )
  )
);

create policy "Guidrent: applicants delete own application documents"
on storage.objects for delete to authenticated
using (bucket_id = 'application-documents' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

create policy "Guidrent: users upload own message attachments"
on storage.objects for insert to authenticated
with check (bucket_id = 'message-attachments' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Guidrent: conversation participants read message attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'message-attachments' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or public.participates_in_conversation(case when (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$' then ((storage.foldername(name))[2])::uuid else null end)
  )
);

create policy "Guidrent: users delete own message attachments"
on storage.objects for delete to authenticated
using (bucket_id = 'message-attachments' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- Realtime -------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.rental_applications;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.agent_availability;
exception when duplicate_object then null; end $$;

-- Privileges for tables created by this migration -----------------------------
grant select, insert, update, delete on public.saved_searches to authenticated;
grant select, insert, update, delete on public.notification_preferences to authenticated;
grant select on public.agent_availability to anon;
grant select, insert, update, delete on public.agent_availability to authenticated;
grant select, insert, update, delete on public.rental_applications to authenticated;
grant select, insert, update, delete on public.application_documents to authenticated;
grant select, insert on public.consent_records to authenticated;
grant select, insert, update on public.data_subject_requests to authenticated;
grant select, insert, update, delete on public.blocked_users to authenticated;
grant select, insert, update on public.listing_claims to authenticated;
grant select, insert, update, delete on public.shortlist_notes to authenticated;
grant select on public.property_price_history to anon, authenticated;
grant select on public.property_daily_stats to authenticated;
grant usage, select on all sequences in schema public to authenticated;
