-- Phase 2, database tranche 1:
-- foundational schemas, tenant configuration, and academic calendar.
--
-- This migration intentionally exposes no direct anon/authenticated table access.
-- Identity, authorization policies, public RPCs, and domain tables are added only
-- after this foundation is applied and verified.

begin;

create extension if not exists pgcrypto;

create schema if not exists app;
create schema if not exists audit;
create schema if not exists ops;
create schema if not exists reporting;

comment on schema app is
  'Internal transactional helpers; never treated as a direct PostgREST API.';
comment on schema audit is
  'Immutable audit and authorization history.';
comment on schema ops is
  'Operational state such as idempotency, notifications, workflow runs and incidents.';
comment on schema reporting is
  'Internal reporting models; never queried directly through PostgREST by n8n.';

revoke all on schema app from public, anon, authenticated;
revoke all on schema audit from public, anon, authenticated;
revoke all on schema ops from public, anon, authenticated;
revoke all on schema reporting from public, anon, authenticated;

create type public.institution_type as enum (
  'university',
  'school',
  'college',
  'cambridge_school',
  'other'
);

create type public.academic_model as enum (
  'credit_hour',
  'subject_based',
  'cambridge',
  'hybrid'
);

create type public.record_status as enum (
  'draft',
  'active',
  'inactive',
  'archived'
);

create type public.term_type as enum (
  'semester',
  'trimester',
  'quarter',
  'term',
  'annual',
  'session'
);

create or replace function app.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$function$;

revoke all on function app.set_updated_at() from public, anon, authenticated;

create table public.institutions (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  institution_type public.institution_type not null,
  academic_model public.academic_model not null,
  timezone text not null default 'Asia/Karachi',
  logo_url text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint institutions_code_format_chk
    check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint institutions_name_not_blank_chk
    check (btrim(name) <> ''),
  constraint institutions_timezone_not_blank_chk
    check (btrim(timezone) <> '')
);

create unique index institutions_code_uq
  on public.institutions (upper(code));

create index institutions_status_idx
  on public.institutions (status);

create trigger institutions_set_updated_at
before update on public.institutions
for each row execute function app.set_updated_at();

create table public.campuses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null
    references public.institutions(id) on delete restrict,
  code text not null,
  name text not null,
  timezone text,
  address_line text,
  city text,
  country_code text not null default 'PK',
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint campuses_code_format_chk
    check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint campuses_name_not_blank_chk
    check (btrim(name) <> ''),
  constraint campuses_country_code_chk
    check (country_code ~ '^[A-Z]{2}$'),
  constraint campuses_institution_id_id_uq
    unique (institution_id, id)
);

create unique index campuses_institution_code_uq
  on public.campuses (institution_id, upper(code));

create index campuses_institution_status_idx
  on public.campuses (institution_id, status);

create trigger campuses_set_updated_at
before update on public.campuses
for each row execute function app.set_updated_at();

create table public.institution_settings (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null
    references public.institutions(id) on delete cascade,
  version integer not null,
  effective_from date not null,
  effective_to date,
  enrollment_policy jsonb not null default '{}'::jsonb,
  waitlist_behavior text not null default 'waitlist',
  maximum_credit_load numeric(6,2),
  transcript_disclaimer text,
  transcript_settings jsonb not null default '{}'::jsonb,
  hec_report_settings jsonb not null default '{}'::jsonb,
  notification_settings jsonb not null default '{}'::jsonb,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint institution_settings_version_positive_chk
    check (version > 0),
  constraint institution_settings_date_order_chk
    check (effective_to is null or effective_to >= effective_from),
  constraint institution_settings_waitlist_behavior_chk
    check (waitlist_behavior in ('reject', 'waitlist', 'manual_review')),
  constraint institution_settings_maximum_credit_load_chk
    check (maximum_credit_load is null or maximum_credit_load > 0),
  constraint institution_settings_json_objects_chk
    check (
      jsonb_typeof(enrollment_policy) = 'object'
      and jsonb_typeof(transcript_settings) = 'object'
      and jsonb_typeof(hec_report_settings) = 'object'
      and jsonb_typeof(notification_settings) = 'object'
    )
);

create unique index institution_settings_version_uq
  on public.institution_settings (institution_id, version);

create index institution_settings_effective_idx
  on public.institution_settings (
    institution_id,
    effective_from,
    effective_to
  );

create trigger institution_settings_set_updated_at
before update on public.institution_settings
for each row execute function app.set_updated_at();

create table public.academic_years (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null
    references public.institutions(id) on delete cascade,
  code text not null,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint academic_years_date_order_chk
    check (ends_on > starts_on),
  constraint academic_years_name_not_blank_chk
    check (btrim(name) <> ''),
  constraint academic_years_institution_id_id_uq
    unique (institution_id, id)
);

create unique index academic_years_code_uq
  on public.academic_years (institution_id, upper(code));

create index academic_years_dates_idx
  on public.academic_years (institution_id, starts_on, ends_on);

create trigger academic_years_set_updated_at
before update on public.academic_years
for each row execute function app.set_updated_at();

create table public.terms (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  academic_year_id uuid not null,
  code text not null,
  name text not null,
  term_type public.term_type not null,
  sequence_number integer not null,
  starts_on date not null,
  ends_on date not null,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint terms_institution_fk
    foreign key (institution_id)
    references public.institutions(id) on delete cascade,
  constraint terms_academic_year_scope_fk
    foreign key (institution_id, academic_year_id)
    references public.academic_years(institution_id, id) on delete cascade,
  constraint terms_sequence_positive_chk
    check (sequence_number > 0),
  constraint terms_date_order_chk
    check (ends_on > starts_on),
  constraint terms_name_not_blank_chk
    check (btrim(name) <> ''),
  constraint terms_institution_id_id_uq
    unique (institution_id, id)
);

create unique index terms_code_uq
  on public.terms (institution_id, academic_year_id, upper(code));

create unique index terms_sequence_uq
  on public.terms (academic_year_id, sequence_number);

create index terms_dates_idx
  on public.terms (institution_id, starts_on, ends_on);

create trigger terms_set_updated_at
before update on public.terms
for each row execute function app.set_updated_at();

create table public.enrollment_periods (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid,
  term_id uuid not null,
  name text not null,
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  settings_version integer not null,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint enrollment_periods_institution_fk
    foreign key (institution_id)
    references public.institutions(id) on delete cascade,
  constraint enrollment_periods_campus_scope_fk
    foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint enrollment_periods_term_scope_fk
    foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete cascade,
  constraint enrollment_periods_settings_version_fk
    foreign key (institution_id, settings_version)
    references public.institution_settings(institution_id, version) on delete restrict,
  constraint enrollment_periods_time_order_chk
    check (closes_at > opens_at),
  constraint enrollment_periods_settings_version_positive_chk
    check (settings_version > 0),
  constraint enrollment_periods_name_not_blank_chk
    check (btrim(name) <> '')
);

create index enrollment_periods_scope_idx
  on public.enrollment_periods (
    institution_id,
    campus_id,
    term_id,
    status
  );

create index enrollment_periods_window_idx
  on public.enrollment_periods (opens_at, closes_at);

create trigger enrollment_periods_set_updated_at
before update on public.enrollment_periods
for each row execute function app.set_updated_at();

alter table public.institutions enable row level security;
alter table public.campuses enable row level security;
alter table public.institution_settings enable row level security;
alter table public.academic_years enable row level security;
alter table public.terms enable row level security;
alter table public.enrollment_periods enable row level security;

-- Scoped policies are intentionally deferred until staff identities and role
-- assignments exist. Until then, direct client roles have no table privileges.
revoke all on table public.institutions from anon, authenticated;
revoke all on table public.campuses from anon, authenticated;
revoke all on table public.institution_settings from anon, authenticated;
revoke all on table public.academic_years from anon, authenticated;
revoke all on table public.terms from anon, authenticated;
revoke all on table public.enrollment_periods from anon, authenticated;

grant select, insert, update, delete on table public.institutions to service_role;
grant select, insert, update, delete on table public.campuses to service_role;
grant select, insert, update, delete on table public.institution_settings to service_role;
grant select, insert, update, delete on table public.academic_years to service_role;
grant select, insert, update, delete on table public.terms to service_role;
grant select, insert, update, delete on table public.enrollment_periods to service_role;

comment on table public.institutions is
  'Tenant root for each supported institution.';
comment on table public.campuses is
  'Institution-scoped campuses.';
comment on table public.institution_settings is
  'Versioned institution configuration and behaviour.';
comment on table public.academic_years is
  'Institution-scoped academic-year definitions.';
comment on table public.terms is
  'Semester, term, session or equivalent academic period.';
comment on table public.enrollment_periods is
  'Enrollment request windows bound to a configuration version.';

commit;
