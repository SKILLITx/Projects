-- Workflow 04 correction-decision pilot input selector.
-- Read-only. Resolves the successfully queued correction request by correlation ID.
with target as (
  select
    mcr.id as correction_request_id,
    mcr.correction_status,
    mcr.reason,
    mcr.proposed_marks,
    mcr.correlation_id,
    mcr.idempotency_key,
    mcr.created_at,
    mcr.marks_batch_id,
    mcr.student_mark_id,
    sm.marks_obtained as current_stored_marks,
    s.student_number,
    a.code as assessment_code,
    a.maximum_marks,
    mb.offering_id as course_offering_id,
    cr.total_score as current_total_score,
    cr.letter_grade as current_letter_grade,
    cr.grade_point as current_grade_point,
    cr.calculation_version as current_calculation_version,
    cr.result_status as current_result_status
  from public.mark_correction_requests mcr
  join public.student_marks sm
    on sm.id = mcr.student_mark_id
   and sm.institution_id = mcr.institution_id
  join public.students s
    on s.id = sm.student_id
   and s.institution_id = sm.institution_id
  join public.assessments a
    on a.id = sm.assessment_id
   and a.institution_id = sm.institution_id
  join public.marks_batches mb
    on mb.id = mcr.marks_batch_id
   and mb.institution_id = mcr.institution_id
  left join public.course_results cr
    on cr.student_id = sm.student_id
   and cr.course_offering_id = mb.offering_id
  where mcr.correlation_id =
    '1dcc2a39-ed5f-456c-a5d0-418d6b5ed5b9'::uuid
  order by mcr.created_at desc
  limit 1
)
select jsonb_build_object(
  'status',
    case
      when not exists (select 1 from target) then 'FAIL'
      when (select correction_status from target) <> 'requested' then 'FAIL'
      else 'PASS'
    end,
  'portal_fields',
    (
      select jsonb_build_object(
        'Correction request ID', correction_request_id,
        'Decision', 'Approve',
        'Reason',
          'Workflow 04 pilot acceptance — approved verified one-mark FIN correction for DMU-0001.'
      )
      from target
    ),
  'baseline',
    (
      select jsonb_build_object(
        'correction_status', correction_status,
        'marks_batch_id', marks_batch_id,
        'student_mark_id', student_mark_id,
        'student_number', student_number,
        'assessment_code', assessment_code,
        'current_stored_marks', current_stored_marks,
        'proposed_marks', proposed_marks,
        'maximum_marks', maximum_marks,
        'course_offering_id', course_offering_id,
        'current_total_score', current_total_score,
        'current_letter_grade', current_letter_grade,
        'current_grade_point', current_grade_point,
        'current_calculation_version', current_calculation_version,
        'current_result_status', current_result_status,
        'request_correlation_id', correlation_id,
        'request_idempotency_key', idempotency_key,
        'requested_at', created_at,
        'request_reason', reason
      )
      from target
    )
) as workflow04_correction_decision_inputs;
