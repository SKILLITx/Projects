-- Phase 4 / Workflow 03 controlled-pilot authorization.
--
-- The Google marks form captures the signed-in submitter email. The current
-- pilot operator already has an active staff profile, but is not assigned to a
-- class. The marks RPC correctly rejects such submissions.
--
-- This migration grants only the minimum additional pilot scope:
--   staff:       zaidrizwan.278@gmail.com
--   institution: DMU
--   campus:      ISB
--   offering:    FALL-BA101-ISB
--   section:     A
--
-- It does not remove or replace the existing demo teacher assignment.

begin;

do $migration$
declare
  v_staff_profile_id uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_offering_id uuid;
  v_section_id uuid;
begin
  select sp.id
    into strict v_staff_profile_id
  from public.staff_profiles sp
  where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
    and sp.status = 'active';

  select i.id
    into strict v_institution_id
  from public.institutions i
  where i.code = 'DMU'
    and i.status = 'active';

  select c.id
    into strict v_campus_id
  from public.campuses c
  where c.institution_id = v_institution_id
    and c.code = 'ISB'
    and c.status = 'active';

  select co.id
    into strict v_offering_id
  from public.course_offerings co
  where co.institution_id = v_institution_id
    and co.campus_id = v_campus_id
    and co.offering_code = 'FALL-BA101-ISB'
    and co.status in ('open', 'completed');

  select s.id
    into strict v_section_id
  from public.sections s
  where s.institution_id = v_institution_id
    and s.campus_id = v_campus_id
    and s.offering_id = v_offering_id
    and s.code = 'A'
    and s.status in ('open', 'completed');

  if not exists (
    select 1
    from public.role_assignments ra
    where ra.staff_profile_id = v_staff_profile_id
      and ra.institution_id = v_institution_id
      and ra.role = 'teacher'
      and ra.status = 'active'
      and ra.valid_from <= timezone('utc', now())
      and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
  ) then
    insert into public.role_assignments (
      staff_profile_id,
      institution_id,
      role,
      status,
      valid_from
    )
    values (
      v_staff_profile_id,
      v_institution_id,
      'teacher',
      'active',
      timestamptz '2026-07-18 00:00:00+00'
    );
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    where ta.staff_profile_id = v_staff_profile_id
      and ta.institution_id = v_institution_id
      and ta.campus_id = v_campus_id
      and ta.offering_id = v_offering_id
      and ta.section_id = v_section_id
      and ta.role_label = 'teacher'
      and ta.status = 'active'
      and (ta.valid_from is null or ta.valid_from <= current_date)
      and (ta.valid_to is null or ta.valid_to >= current_date)
  ) then
    insert into public.teacher_assignments (
      institution_id,
      campus_id,
      staff_profile_id,
      offering_id,
      section_id,
      role_label,
      valid_from,
      status
    )
    values (
      v_institution_id,
      v_campus_id,
      v_staff_profile_id,
      v_offering_id,
      v_section_id,
      'teacher',
      date '2026-07-18',
      'active'
    );
  end if;
end;
$migration$;

commit;
