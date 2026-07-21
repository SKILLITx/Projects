select
  mb.id as marks_batch_id,
  mb.created_at,
  mb.source_submission_id,
  mb.version_number,
  mb.batch_status,
  mb.validation_summary,
  sp.email as submitted_by_email,
  i.code as institution_code,
  c.code as campus_code,
  co.offering_code,
  sec.code as section_code,
  count(sm.id)::integer as stored_mark_count,
  jsonb_agg(
    jsonb_build_object(
      'student_number', s.student_number,
      'assessment_code', a.code,
      'marks_obtained', sm.marks_obtained,
      'is_absent', sm.is_absent,
      'is_missing', sm.is_missing,
      'remarks', sm.remarks
    )
    order by s.student_number
  ) filter (where sm.id is not null) as stored_marks,
  (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'issue_code', mvi.issue_code,
          'severity', mvi.severity,
          'student_number', mvi.student_number,
          'assessment_code', mvi.assessment_code,
          'message', mvi.message
        )
        order by mvi.created_at, mvi.id
      ),
      '[]'::jsonb
    )
    from public.marks_validation_issues mvi
    where mvi.marks_batch_id = mb.id
  ) as validation_issues
from public.marks_batches mb
join public.staff_profiles sp
  on sp.id = mb.submitted_by_staff_profile_id
join public.institutions i
  on i.id = mb.institution_id
join public.campuses c
  on c.id = mb.campus_id
join public.course_offerings co
  on co.id = mb.offering_id
join public.sections sec
  on sec.id = mb.section_id
left join public.student_marks sm
  on sm.marks_batch_id = mb.id
left join public.students s
  on s.id = sm.student_id
left join public.assessments a
  on a.id = sm.assessment_id
where lower(sp.email) = lower('zaidrizwan.278@gmail.com')
group by
  mb.id,
  sp.email,
  i.code,
  c.code,
  co.offering_code,
  sec.code
order by mb.created_at desc
limit 10;
