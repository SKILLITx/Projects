select jsonb_build_object(
  'staff_email', sp.email,
  'staff_status', sp.status,
  'teacher_role_active',
    exists (
      select 1
      from public.role_assignments ra
      where ra.staff_profile_id = sp.id
        and ra.institution_id = i.id
        and ra.role = 'teacher'
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    ),
  'teacher_assignment_active',
    exists (
      select 1
      from public.teacher_assignments ta
      where ta.staff_profile_id = sp.id
        and ta.institution_id = i.id
        and ta.campus_id = c.id
        and ta.offering_id = co.id
        and ta.section_id = s.id
        and ta.status = 'active'
        and (ta.valid_from is null or ta.valid_from <= current_date)
        and (ta.valid_to is null or ta.valid_to >= current_date)
    ),
  'institution_code', i.code,
  'campus_code', c.code,
  'offering_code', co.offering_code,
  'section_code', s.code
) as workflow03_pilot_teacher_verification
from public.staff_profiles sp
join public.institutions i
  on i.code = 'DMU'
join public.campuses c
  on c.institution_id = i.id
 and c.code = 'ISB'
join public.course_offerings co
  on co.institution_id = i.id
 and co.campus_id = c.id
 and co.offering_code = 'FALL-BA101-ISB'
join public.sections s
  on s.institution_id = i.id
 and s.campus_id = c.id
 and s.offering_id = co.id
 and s.code = 'A'
where lower(sp.email) = lower('zaidrizwan.278@gmail.com');
