-- Workflow 04 correction pilot input selector.
-- Read-only. Returns one safe mark from the approved FIN pilot batch.
with target_batch as (
  select mb.*
  from public.marks_batches mb
  where mb.id = 'b3dd3f5d-ad13-498d-a7e4-41622bc8abbe'::uuid
    and mb.batch_status = 'approved'
),
candidate as (
  select
    i.code as institution_code,
    c.code as campus_code,
    mb.id as marks_batch_id,
    sm.id as student_mark_id,
    s.student_number,
    a.code as assessment_code,
    sm.marks_obtained as current_marks,
    a.maximum_marks,
    least(
      a.maximum_marks,
      sm.marks_obtained + 1
    ) as proposed_corrected_marks,
    cr.calculation_version as current_calculation_version,
    cr.total_score as current_total_score,
    cr.letter_grade as current_letter_grade,
    cr.grade_point as current_grade_point
  from target_batch mb
  join public.student_marks sm
    on sm.marks_batch_id = mb.id
  join public.students s
    on s.id = sm.student_id
   and s.institution_id = sm.institution_id
  join public.assessments a
    on a.id = sm.assessment_id
   and a.institution_id = sm.institution_id
  join public.institutions i
    on i.id = mb.institution_id
  join public.campuses c
    on c.id = mb.campus_id
   and c.institution_id = mb.institution_id
  left join public.course_results cr
    on cr.student_id = sm.student_id
   and cr.course_offering_id = mb.offering_id
  where sm.marks_obtained is not null
    and sm.marks_obtained < a.maximum_marks
  order by s.student_number, sm.id
  limit 1
)
select jsonb_build_object(
  'status',
    case when exists (select 1 from candidate) then 'PASS' else 'FAIL' end,
  'form_fields',
    (
      select jsonb_build_object(
        'Institution code', institution_code,
        'Campus code', campus_code,
        'Marks batch ID', marks_batch_id,
        'Student mark ID', student_mark_id,
        'Student number', student_number,
        'Assessment code', assessment_code,
        'Current marks', current_marks,
        'Proposed corrected marks', proposed_corrected_marks,
        'Detailed reason for correction',
          'Workflow 04 pilot acceptance correction: verified one-mark adjustment for correction, recalculation and audit testing.',
        'Supporting evidence Drive URL (optional)', '',
        'I confirm that this request is accurate and auditable.', 'I confirm'
      )
      from candidate
    ),
  'baseline',
    (
      select jsonb_build_object(
        'maximum_marks', maximum_marks,
        'current_calculation_version', current_calculation_version,
        'current_total_score', current_total_score,
        'current_letter_grade', current_letter_grade,
        'current_grade_point', current_grade_point
      )
      from candidate
    )
) as workflow04_correction_pilot_inputs;
