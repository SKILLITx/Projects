-- Workflow 04 bundled durable-outcome verification.
-- Run after the live approve, correction and publication acceptance sequence.
select jsonb_build_object(
  'marks_batches', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (
      select
        mb.id,
        mb.offering_id,
        mb.section_id,
        mb.version_number,
        mb.batch_status,
        mb.approved_at,
        mb.approved_by,
        mb.correlation_id,
        mb.created_at
      from public.marks_batches mb
      order by mb.created_at desc
      limit 10
    ) x
  ),
  'approval_history', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.decided_at desc), '[]'::jsonb)
    from (
      select
        mah.id,
        mah.marks_batch_id,
        mah.decision,
        mah.reason,
        mah.decided_by,
        mah.correlation_id,
        mah.decided_at
      from public.marks_approval_history mah
      order by mah.decided_at desc
      limit 10
    ) x
  ),
  'corrections', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (
      select
        mcr.id,
        mcr.marks_batch_id,
        mcr.student_mark_id,
        mcr.proposed_marks,
        mcr.correction_status,
        mcr.decision_reason,
        mcr.decided_at,
        mcr.applied_at,
        mcr.correlation_id,
        mcr.created_at
      from public.mark_correction_requests mcr
      order by mcr.created_at desc
      limit 10
    ) x
  ),
  'course_results', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.student_id), '[]'::jsonb)
    from (
      select
        cr.student_id,
        cr.course_offering_id,
        cr.total_score,
        cr.letter_grade,
        cr.grade_point,
        cr.credit_hours,
        cr.outcome_code,
        cr.result_status,
        cr.calculation_version,
        cr.published_at,
        cr.correlation_id
      from public.course_results cr
      where cr.course_offering_id = (
        select mb.offering_id
        from public.marks_batches mb
        order by mb.created_at desc
        limit 1
      )
    ) x
  ),
  'semester_results', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.student_id), '[]'::jsonb)
    from (
      select
        sr.student_id,
        sr.term_id,
        sr.attempted_credits,
        sr.earned_credits,
        sr.quality_points,
        sr.gpa,
        sr.standing_code,
        sr.at_risk,
        sr.result_status,
        sr.published_at
      from public.semester_results sr
      order by sr.updated_at desc
      limit 20
    ) x
  ),
  'cumulative_results', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.student_id), '[]'::jsonb)
    from (
      select
        cr.student_id,
        cr.attempted_credits,
        cr.earned_credits,
        cr.quality_points,
        cr.cgpa,
        cr.standing_code,
        cr.at_risk,
        cr.last_term_id
      from public.cumulative_results cr
      order by cr.updated_at desc
      limit 20
    ) x
  ),
  'notification_outbox', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (
      select
        no.id,
        no.notification_type,
        no.recipient_address,
        no.job_status,
        no.attempt_count,
        no.correlation_id,
        no.idempotency_key,
        no.created_at
      from ops.notification_outbox no
      where no.notification_type in (
        'marks.batch.approved',
        'marks.batch.rejected',
        'marks.batch.returned',
        'marks.correction.requested',
        'marks.correction.applied',
        'marks.correction.rejected',
        'results.published'
      )
      order by no.created_at desc
      limit 30
    ) x
  )
) as workflow04_acceptance_evidence;
