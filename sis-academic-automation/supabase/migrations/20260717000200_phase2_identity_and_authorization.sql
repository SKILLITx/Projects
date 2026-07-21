-- Phase 2, database tranche 2:
-- staff identity, role assignments, campus scope, permission overrides,
-- authorization helpers, and scoped read policies.
--
-- No staff account is bootstrapped by this migration. The first authenticated
-- administrator is created later through a separate, narrowly controlled step.

begin;

create type public.staff_role as enum (
  'teacher',
  'registrar_admin',
  'campus_administrator',
  'super_administrator'
);

create type public.assignment_status as enum (
  'pending',
  'active',
  'suspended',
  'revoked',
  'expired'
);

create type public.permission_effect as enum (
  'allow',
  'deny'
);

create table public.staff_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  email text not null,
  full_name text not null,
  employee_code text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint staff_profiles_email_not_blank_chk
    check (btrim(email) <> ''),
  constraint staff_profiles_full_name_not_blank_chk
    check (btrim(full_name) <> ''),
  constraint staff_profiles_email_shape_chk
    check (position('@' in email) > 1)
);

create unique index staff_profiles_email_uq
  on public.staff_profiles (lower(email));

create index staff_profiles_auth_user_idx
  on public.staff_profiles (auth_user_id)
  where auth_user_id is not null;

create index staff_profiles_status_idx
  on public.staff_profiles (status);

create trigger staff_profiles_set_updated_at
before update on public.staff_profiles
for each row execute function app.set_updated_at();

create table public.role_assignments (
  id uuid primary key default gen_random_uuid(),
  staff_profile_id uuid not null
    references public.staff_profiles(id) on delete cascade,
  institution_id uuid
    references public.institutions(id) on delete cascade,
  role public.staff_role not null,
  status public.assignment_status not null default 'active',
  valid_from timestamptz not null default timezone('utc', now()),
  valid_to timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint role_assignments_scope_chk
    check (
      (role = 'super_administrator' and institution_id is null)
      or
      (role <> 'super_administrator' and institution_id is not null)
    ),
  constraint role_assignments_validity_chk
    check (valid_to is null or valid_to > valid_from),
  constraint role_assignments_institution_id_id_uq
    unique (institution_id, id)
);

create unique index role_assignments_identity_scope_uq
  on public.role_assignments (
    staff_profile_id,
    role,
    coalesce(
      institution_id,
      '00000000-0000-0000-0000-000000000000'::uuid
    ),
    valid_from
  );

create index role_assignments_staff_status_idx
  on public.role_assignments (
    staff_profile_id,
    status,
    valid_from,
    valid_to
  );

create index role_assignments_institution_role_idx
  on public.role_assignments (
    institution_id,
    role,
    status
  );

create trigger role_assignments_set_updated_at
before update on public.role_assignments
for each row execute function app.set_updated_at();

create table public.campus_assignments (
  id uuid primary key default gen_random_uuid(),
  role_assignment_id uuid not null,
  institution_id uuid not null,
  campus_id uuid not null,
  status public.assignment_status not null default 'active',
  valid_from timestamptz not null default timezone('utc', now()),
  valid_to timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint campus_assignments_role_scope_fk
    foreign key (institution_id, role_assignment_id)
    references public.role_assignments(institution_id, id)
    on delete cascade,
  constraint campus_assignments_campus_scope_fk
    foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id)
    on delete cascade,
  constraint campus_assignments_validity_chk
    check (valid_to is null or valid_to > valid_from)
);

create unique index campus_assignments_role_campus_uq
  on public.campus_assignments (
    role_assignment_id,
    campus_id,
    valid_from
  );

create index campus_assignments_scope_status_idx
  on public.campus_assignments (
    institution_id,
    campus_id,
    status,
    valid_from,
    valid_to
  );

create trigger campus_assignments_set_updated_at
before update on public.campus_assignments
for each row execute function app.set_updated_at();

create table public.permission_grants (
  id uuid primary key default gen_random_uuid(),
  role_assignment_id uuid not null,
  institution_id uuid not null,
  campus_id uuid,
  permission_code text not null,
  effect public.permission_effect not null default 'allow',
  status public.assignment_status not null default 'active',
  valid_from timestamptz not null default timezone('utc', now()),
  valid_to timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint permission_grants_role_scope_fk
    foreign key (institution_id, role_assignment_id)
    references public.role_assignments(institution_id, id)
    on delete cascade,
  constraint permission_grants_campus_scope_fk
    foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id)
    on delete cascade,
  constraint permission_grants_code_chk
    check (permission_code ~ '^[a-z][a-z0-9_.:-]{2,99}$'),
  constraint permission_grants_validity_chk
    check (valid_to is null or valid_to > valid_from)
);

create unique index permission_grants_scope_uq
  on public.permission_grants (
    role_assignment_id,
    coalesce(
      campus_id,
      '00000000-0000-0000-0000-000000000000'::uuid
    ),
    permission_code,
    effect,
    valid_from
  );

create index permission_grants_lookup_idx
  on public.permission_grants (
    institution_id,
    campus_id,
    permission_code,
    status
  );

create trigger permission_grants_set_updated_at
before update on public.permission_grants
for each row execute function app.set_updated_at();

create table audit.authorization_events (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default timezone('utc', now()),
  auth_user_id uuid references auth.users(id) on delete set null,
  staff_profile_id uuid references public.staff_profiles(id) on delete set null,
  operation text not null,
  institution_id uuid references public.institutions(id) on delete set null,
  campus_id uuid references public.campuses(id) on delete set null,
  allowed boolean not null,
  reason_code text not null,
  correlation_id uuid,
  details jsonb not null default '{}'::jsonb,
  constraint authorization_events_operation_not_blank_chk
    check (btrim(operation) <> ''),
  constraint authorization_events_reason_not_blank_chk
    check (btrim(reason_code) <> ''),
  constraint authorization_events_details_object_chk
    check (jsonb_typeof(details) = 'object')
);

create index authorization_events_actor_time_idx
  on audit.authorization_events (auth_user_id, occurred_at desc);

create index authorization_events_scope_time_idx
  on audit.authorization_events (
    institution_id,
    campus_id,
    occurred_at desc
  );

create or replace function app.validate_campus_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role public.staff_role;
begin
  select ra.role
    into v_role
  from public.role_assignments ra
  where ra.id = new.role_assignment_id
    and ra.institution_id = new.institution_id;

  if v_role is null then
    raise exception using
      errcode = '23503',
      message = 'Role assignment was not found in the supplied institution.';
  end if;

  if v_role not in ('registrar_admin', 'campus_administrator') then
    raise exception using
      errcode = '23514',
      message = 'Campus assignments are allowed only for registrar or campus administrator roles.';
  end if;

  return new;
end;
$function$;

revoke all on function app.validate_campus_assignment()
  from public, anon, authenticated;

create trigger campus_assignments_validate_role
before insert or update of role_assignment_id, institution_id
on public.campus_assignments
for each row execute function app.validate_campus_assignment();

create or replace function app.current_staff_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select sp.id
  from public.staff_profiles sp
  where sp.auth_user_id = (select auth.uid())
    and sp.status = 'active'
  limit 1;
$function$;

create or replace function app.is_super_administrator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.role_assignments ra
    where ra.staff_profile_id = app.current_staff_profile_id()
      and ra.role = 'super_administrator'
      and ra.institution_id is null
      and ra.status = 'active'
      and ra.valid_from <= timezone('utc', now())
      and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
  );
$function$;

create or replace function app.has_institution_role(
  p_institution_id uuid,
  p_roles public.staff_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    app.is_super_administrator()
    or exists (
      select 1
      from public.role_assignments ra
      where ra.staff_profile_id = app.current_staff_profile_id()
        and ra.institution_id = p_institution_id
        and ra.role = any(p_roles)
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    );
$function$;

create or replace function app.can_access_institution(
  p_institution_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    app.is_super_administrator()
    or exists (
      select 1
      from public.role_assignments ra
      where ra.staff_profile_id = app.current_staff_profile_id()
        and ra.institution_id = p_institution_id
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    );
$function$;

create or replace function app.can_administer_institution(
  p_institution_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app.has_institution_role(
    p_institution_id,
    array['registrar_admin']::public.staff_role[]
  );
$function$;

create or replace function app.can_access_campus(
  p_institution_id uuid,
  p_campus_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    app.is_super_administrator()
    or app.has_institution_role(
      p_institution_id,
      array['registrar_admin']::public.staff_role[]
    )
    or exists (
      select 1
      from public.role_assignments ra
      join public.campus_assignments ca
        on ca.role_assignment_id = ra.id
       and ca.institution_id = ra.institution_id
      where ra.staff_profile_id = app.current_staff_profile_id()
        and ra.institution_id = p_institution_id
        and ra.role = 'campus_administrator'
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
        and ca.campus_id = p_campus_id
        and ca.status = 'active'
        and ca.valid_from <= timezone('utc', now())
        and (ca.valid_to is null or ca.valid_to > timezone('utc', now()))
    );
$function$;

create or replace function app.can_view_staff_profile(
  p_staff_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p_staff_profile_id = app.current_staff_profile_id()
    or app.is_super_administrator()
    or exists (
      select 1
      from public.role_assignments target_ra
      where target_ra.staff_profile_id = p_staff_profile_id
        and target_ra.institution_id is not null
        and target_ra.status = 'active'
        and app.can_administer_institution(target_ra.institution_id)
    );
$function$;

create or replace function app.has_permission(
  p_institution_id uuid,
  p_campus_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  with candidate_grants as (
    select pg.effect
    from public.role_assignments ra
    join public.permission_grants pg
      on pg.role_assignment_id = ra.id
     and pg.institution_id = ra.institution_id
    where ra.staff_profile_id = app.current_staff_profile_id()
      and ra.institution_id = p_institution_id
      and ra.status = 'active'
      and ra.valid_from <= timezone('utc', now())
      and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
      and pg.permission_code = p_permission_code
      and (pg.campus_id is null or pg.campus_id = p_campus_id)
      and pg.status = 'active'
      and pg.valid_from <= timezone('utc', now())
      and (pg.valid_to is null or pg.valid_to > timezone('utc', now()))
  )
  select
    app.is_super_administrator()
    or (
      not exists (
        select 1 from candidate_grants where effect = 'deny'
      )
      and exists (
        select 1 from candidate_grants where effect = 'allow'
      )
    );
$function$;

revoke all on function app.current_staff_profile_id()
  from public, anon, authenticated;
revoke all on function app.is_super_administrator()
  from public, anon, authenticated;
revoke all on function app.has_institution_role(uuid, public.staff_role[])
  from public, anon, authenticated;
revoke all on function app.can_access_institution(uuid)
  from public, anon, authenticated;
revoke all on function app.can_administer_institution(uuid)
  from public, anon, authenticated;
revoke all on function app.can_access_campus(uuid, uuid)
  from public, anon, authenticated;
revoke all on function app.can_view_staff_profile(uuid)
  from public, anon, authenticated;
revoke all on function app.has_permission(uuid, uuid, text)
  from public, anon, authenticated;

grant usage on schema app to authenticated, service_role;

grant execute on function app.current_staff_profile_id()
  to authenticated, service_role;
grant execute on function app.is_super_administrator()
  to authenticated, service_role;
grant execute on function app.has_institution_role(uuid, public.staff_role[])
  to authenticated, service_role;
grant execute on function app.can_access_institution(uuid)
  to authenticated, service_role;
grant execute on function app.can_administer_institution(uuid)
  to authenticated, service_role;
grant execute on function app.can_access_campus(uuid, uuid)
  to authenticated, service_role;
grant execute on function app.can_view_staff_profile(uuid)
  to authenticated, service_role;
grant execute on function app.has_permission(uuid, uuid, text)
  to authenticated, service_role;

alter table public.staff_profiles enable row level security;
alter table public.role_assignments enable row level security;
alter table public.campus_assignments enable row level security;
alter table public.permission_grants enable row level security;

revoke all on table public.staff_profiles from anon, authenticated;
revoke all on table public.role_assignments from anon, authenticated;
revoke all on table public.campus_assignments from anon, authenticated;
revoke all on table public.permission_grants from anon, authenticated;

grant select on table public.staff_profiles to authenticated;
grant select on table public.role_assignments to authenticated;
grant select on table public.campus_assignments to authenticated;
grant select on table public.permission_grants to authenticated;

grant select, insert, update, delete on table public.staff_profiles to service_role;
grant select, insert, update, delete on table public.role_assignments to service_role;
grant select, insert, update, delete on table public.campus_assignments to service_role;
grant select, insert, update, delete on table public.permission_grants to service_role;

grant select on table public.institutions to authenticated;
grant select on table public.campuses to authenticated;
grant select on table public.institution_settings to authenticated;
grant select on table public.academic_years to authenticated;
grant select on table public.terms to authenticated;
grant select on table public.enrollment_periods to authenticated;

create policy staff_profiles_select_scoped
on public.staff_profiles
for select
to authenticated
using (app.can_view_staff_profile(id));

create policy role_assignments_select_scoped
on public.role_assignments
for select
to authenticated
using (
  staff_profile_id = app.current_staff_profile_id()
  or app.is_super_administrator()
  or (
    institution_id is not null
    and app.can_administer_institution(institution_id)
  )
);

create policy campus_assignments_select_scoped
on public.campus_assignments
for select
to authenticated
using (
  app.is_super_administrator()
  or app.can_administer_institution(institution_id)
  or role_assignment_id in (
    select ra.id
    from public.role_assignments ra
    where ra.staff_profile_id = app.current_staff_profile_id()
  )
);

create policy permission_grants_select_scoped
on public.permission_grants
for select
to authenticated
using (
  app.is_super_administrator()
  or app.can_administer_institution(institution_id)
  or role_assignment_id in (
    select ra.id
    from public.role_assignments ra
    where ra.staff_profile_id = app.current_staff_profile_id()
  )
);

create policy institutions_select_scoped
on public.institutions
for select
to authenticated
using (app.can_access_institution(id));

create policy campuses_select_scoped
on public.campuses
for select
to authenticated
using (app.can_access_institution(institution_id));

create policy institution_settings_select_admin
on public.institution_settings
for select
to authenticated
using (app.can_administer_institution(institution_id));

create policy academic_years_select_scoped
on public.academic_years
for select
to authenticated
using (app.can_access_institution(institution_id));

create policy terms_select_scoped
on public.terms
for select
to authenticated
using (app.can_access_institution(institution_id));

create policy enrollment_periods_select_scoped
on public.enrollment_periods
for select
to authenticated
using (
  case
    when campus_id is null then app.can_administer_institution(institution_id)
    else app.can_access_campus(institution_id, campus_id)
  end
);

comment on table public.staff_profiles is
  'Staff identity linked optionally to Supabase Auth.';
comment on table public.role_assignments is
  'Time-bounded staff role and institution scope.';
comment on table public.campus_assignments is
  'Explicit campus scope for registrar or campus administrator roles.';
comment on table public.permission_grants is
  'Optional time-bounded permission overrides attached to a role assignment.';
comment on table audit.authorization_events is
  'Private append-only authorization decision evidence.';

commit;
