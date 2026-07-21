select jsonb_build_object(
  'staff_actor', (
    select jsonb_build_object(
      'email', sp.email,
      'full_name', sp.full_name,
      'roles', coalesce((
        select jsonb_agg(ra.role order by ra.role)
        from public.role_assignments ra
        where ra.staff_profile_id = sp.id
          and ra.status = 'active'
      ), '[]'::jsonb)
    )
    from public.staff_profiles sp
    where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
    limit 1
  ),
  'pilot_scope', (
    select jsonb_build_object(
      'institution_id', i.id,
      'institution_code', i.code,
      'institution_name', i.name,
      'campus_id', c.id,
      'campus_code', c.code,
      'campus_name', c.name
    )
    from public.institutions i
    join public.campuses c on c.institution_id = i.id
    where i.code = 'DMU'
      and c.code = 'ISB'
    limit 1
  ),
  'student_search_query', 'DMU-0001',
  'expected_student_number', 'DMU-0001'
) as workflow07_pilot_inputs;
