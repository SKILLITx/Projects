-- Workflow 03 pilot-data preflight.
-- This is read-only. It does not create or modify staff, assignments, marks, or enrollments.

with current_user_staff as (
  select
    sp.id as staff_profile_id,
    sp.email,
    sp.full_name,
    sp.employee_code,
    sp.status,
    sp.auth_user_id
  from public.staff_profiles sp
  where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
),
candidate_classes as (
  select
    sp.id as assigned_staff_profile_id,
    sp.email as assigned_teacher_email,
    sp.full_name as assigned_teacher_name,
    i.code as institution_code,
    c.code as campus_code,
    t.code as term_code,
    co.id as course_offering_id,
    co.offering_code,
    crs.code as course_code,
    crs.title as course_title,
    sec.id as section_id,
    sec.code as section_code,
    a.id as assessment_id,
    a.code as assessment_code,
    a.title as assessment_title,
    a.maximum_marks,
    count(e.id) filter (where e.enrollment_status = 'active') as active_student_count,
    array_agg(s.student_number order by s.student_number)
      filter (
        where e.enrollment_status = 'active'
          and s.student_number is not null
      ) as active_student_numbers
  from public.teacher_assignments ta
  join public.staff_profiles sp
    on sp.id = ta.staff_profile_id
  join public.institutions i
    on i.id = ta.institution_id
  join public.campuses c
    on c.id = ta.campus_id
  join public.course_offerings co
    on co.id = ta.offering_id
   and co.institution_id = ta.institution_id
  join public.terms t
    on t.id = co.term_id
   and t.institution_id = co.institution_id
  join public.courses crs
    on crs.id = co.course_id
   and crs.institution_id = co.institution_id
  join public.sections sec
    on sec.id = ta.section_id
   and sec.offering_id = ta.offering_id
  join public.assessments a
    on a.offering_id = ta.offering_id
   and (a.section_id is null or a.section_id = ta.section_id)
   and a.status = 'active'
  left join public.enrollments e
    on e.course_offering_id = ta.offering_id
   and e.section_id = ta.section_id
   and e.enrollment_status = 'active'
  left join public.students s
    on s.id = e.student_id
  where ta.status = 'active'
    and sp.status = 'active'
    and co.status in ('open', 'completed')
    and sec.status in ('open', 'completed')
  group by
    sp.id,
    sp.email,
    sp.full_name,
    i.code,
    c.code,
    t.code,
    co.id,
    co.offering_code,
    crs.code,
    crs.title,
    sec.id,
    sec.code,
    a.id,
    a.code,
    a.title,
    a.maximum_marks
)
select jsonb_build_object(
  'current_user_staff_profiles',
  coalesce(
    (
      select jsonb_agg(to_jsonb(cus) order by cus.email)
      from current_user_staff cus
    ),
    '[]'::jsonb
  ),
  'candidate_classes',
  coalesce(
    (
      select jsonb_agg(to_jsonb(cc) order by
        cc.institution_code,
        cc.campus_code,
        cc.offering_code,
        cc.section_code,
        cc.assessment_code
      )
      from candidate_classes cc
    ),
    '[]'::jsonb
  )
) as workflow03_preflight;
