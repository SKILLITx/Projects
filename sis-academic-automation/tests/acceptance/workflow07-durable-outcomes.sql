select jsonb_build_object(
  'student_exists', exists(
    select 1 from public.students
    where student_number = 'DMU-0001'
      and status = 'active'
  ),
  'published_result_exists', exists(
    select 1
    from public.course_results cr
    join public.students s on s.id = cr.student_id
    where s.student_number = 'DMU-0001'
      and cr.result_status = 'published'
  ),
  'transcript_exists', exists(
    select 1
    from public.transcript_documents td
    join public.transcript_requests tr on tr.id = td.transcript_request_id
    join public.students s on s.id = tr.student_id
    where s.student_number = 'DMU-0001'
  ),
  'search_audit_exists', exists(
    select 1 from audit.audit_logs
    where operation = 'student.admin.search'
  ),
  'dashboard_audit_exists', exists(
    select 1 from audit.audit_logs
    where operation = 'dashboard.snapshot.get'
  )
) as workflow07_durable_outcomes;
