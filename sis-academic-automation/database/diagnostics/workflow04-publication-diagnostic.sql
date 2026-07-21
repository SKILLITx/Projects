-- Workflow 04 focused publication diagnostic.
-- This test runs inside a transaction and rolls back every test write.
-- It returns the first exact failing stage without exposing credentials.

begin;

create or replace function pg_temp.workflow04_publication_diagnostic()
returns jsonb
language plpgsql
as $diagnostic$
declare
  v_offering_id constant uuid :=
    '631640f3-abfd-dbf5-a25a-b0a0afa0d6c3'::uuid;
  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_student_id uuid;
  v_stage text := 'initialize';
  v_correlation_id uuid := gen_random_uuid();
  v_academic jsonb;
  v_student_count integer := 0;
  v_sqlstate text;
  v_message text;
  v_detail text;
  v_hint text;
  v_context text;
begin
  select
    co.institution_id,
    co.campus_id,
    co.term_id
  into
    v_institution_id,
    v_campus_id,
    v_term_id
  from public.course_offerings co
  where co.id = v_offering_id;

  if v_institution_id is null then
    return jsonb_build_object(
      'status', 'FAIL',
      'stage', 'resolve_offering',
      'message', 'Pilot course offering was not found.'
    );
  end if;

  for v_student_id in
    select distinct e.student_id
    from public.enrollments e
    where e.course_offering_id = v_offering_id
      and e.enrollment_status <> 'cancelled'
    order by e.student_id
  loop
    v_student_count := v_student_count + 1;

    begin
      v_stage := 'calculate_course_result';
      perform app.calculate_course_result(
        v_student_id,
        v_offering_id,
        v_correlation_id
      );

      v_stage := 'mark_course_result_published';
      update public.course_results
      set
        result_status = 'published',
        approved_at = coalesce(approved_at, timezone('utc', now())),
        published_at = timezone('utc', now()),
        updated_at = timezone('utc', now())
      where student_id = v_student_id
        and course_offering_id = v_offering_id;

      if not found then
        raise exception using
          errcode = 'P0001',
          message = 'DIAGNOSTIC_COURSE_RESULT_NOT_CREATED';
      end if;

      v_stage := 'recalculate_academic_record';
      v_academic := app.recalculate_academic_record(
        v_student_id,
        v_term_id,
        v_correlation_id
      );

      v_stage := 'mark_semester_result_published';
      update public.semester_results
      set
        result_status = 'published',
        published_at = timezone('utc', now()),
        updated_at = timezone('utc', now())
      where student_id = v_student_id
        and term_id = v_term_id;

      if not found then
        raise exception using
          errcode = 'P0001',
          message = 'DIAGNOSTIC_SEMESTER_RESULT_NOT_CREATED';
      end if;
    exception when others then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail,
        v_hint = pg_exception_hint,
        v_context = pg_exception_context;

      return jsonb_strip_nulls(jsonb_build_object(
        'status', 'FAIL',
        'stage', v_stage,
        'student_id', v_student_id,
        'processed_students_before_failure', v_student_count - 1,
        'sqlstate', v_sqlstate,
        'message', v_message,
        'detail', nullif(v_detail, ''),
        'hint', nullif(v_hint, ''),
        'context', nullif(v_context, '')
      ));
    end;
  end loop;

  begin
    v_stage := 'queue_results_publication_notifications';

    insert into ops.notification_outbox (
      institution_id,
      campus_id,
      channel,
      notification_type,
      recipient_address,
      recipient_name,
      subject,
      template_code,
      payload,
      correlation_id,
      idempotency_key
    )
    select distinct
      s.institution_id,
      s.campus_id,
      'email',
      'results.published',
      s.primary_email,
      s.full_name,
      'Academic results published',
      'results-published',
      jsonb_build_object(
        'student_id', s.id,
        'student_number', s.student_number,
        'course_offering_id', v_offering_id,
        'term_id', v_term_id
      ),
      v_correlation_id,
      v_offering_id::text || ':' || s.id::text ||
        ':diagnostic-results-published'
    from public.students s
    join public.enrollments e on e.student_id = s.id
    where e.course_offering_id = v_offering_id
      and e.enrollment_status <> 'cancelled'
      and s.primary_email is not null
    on conflict (
      institution_id,
      channel,
      notification_type,
      idempotency_key
    ) do nothing;
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_message = message_text,
      v_detail = pg_exception_detail,
      v_hint = pg_exception_hint,
      v_context = pg_exception_context;

    return jsonb_strip_nulls(jsonb_build_object(
      'status', 'FAIL',
      'stage', v_stage,
      'processed_students_before_failure', v_student_count,
      'sqlstate', v_sqlstate,
      'message', v_message,
      'detail', nullif(v_detail, ''),
      'hint', nullif(v_hint, ''),
      'context', nullif(v_context, '')
    ));
  end;

  return jsonb_build_object(
    'status', 'PASS',
    'stage', 'all_publication_stages',
    'tested_student_count', v_student_count,
    'course_offering_id', v_offering_id,
    'transaction_will_be_rolled_back', true
  );
end;
$diagnostic$;

select pg_temp.workflow04_publication_diagnostic()
  as workflow04_publication_diagnostic;

rollback;
