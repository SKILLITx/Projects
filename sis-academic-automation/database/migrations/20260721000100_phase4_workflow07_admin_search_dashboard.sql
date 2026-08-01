begin;

create or replace function public.rpc_search_students(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'student.admin.search';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id','')::uuid,
    gen_random_uuid()
  );
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_query text := btrim(coalesce(p_request#>>'{payload,query}',''));
  v_status text := lower(btrim(coalesce(p_request#>>'{payload,status}','')));
  v_limit integer := least(
    greatest(coalesce(nullif(p_request#>>'{payload,limit}','')::integer,20),1),
    50
  );
  v_rows jsonb;
begin
  if v_institution_id is null or length(v_query) < 2 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_REQUIRED';
  end if;

  if v_status <> ''
     and v_status not in ('applicant','active','inactive','suspended','withdrawn','graduated') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_STUDENT_STATUS_INVALID';
  end if;

  if v_campus_id is not null
     and not exists (
       select 1
       from public.campuses c
       where c.institution_id = v_institution_id
         and c.id = v_campus_id
         and c.status = 'active'
     ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_SCOPE_INVALID';
  end if;

  if not app.is_service_request()
     and not (
       app.can_administer_institution(v_institution_id)
       or (
         v_campus_id is not null
         and app.can_access_campus(v_institution_id, v_campus_id)
       )
     ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select coalesce(jsonb_agg(row_data order by student_number), '[]'::jsonb)
    into v_rows
  from (
    select
      s.student_number,
      jsonb_build_object(
        'student_id', s.id,
        'student_number', s.student_number,
        'full_name', s.full_name,
        'primary_email', s.primary_email,
        'status', s.status,
        'campus', jsonb_build_object(
          'campus_id', c.id,
          'code', c.code,
          'name', c.name,
          'city', c.city
        ),
        'program', case
          when program_row.program_id is null then null
          else jsonb_build_object(
            'program_id', program_row.program_id,
            'code', program_row.program_code,
            'name', program_row.program_name,
            'registration_status', program_row.registration_status
          )
        end,
        'academic', case
          when academic_row.student_id is null then null
          else jsonb_build_object(
            'cgpa', academic_row.cgpa,
            'standing_code', academic_row.standing_code,
            'at_risk', academic_row.at_risk,
            'attempted_credits', academic_row.attempted_credits,
            'earned_credits', academic_row.earned_credits,
            'calculated_at', academic_row.calculated_at
          )
        end,
        'active_enrollment_count', (
          select count(*)
          from public.enrollments e
          where e.student_id = s.id
            and e.enrollment_status = 'active'
        ),
        'latest_transcript', (
          select jsonb_build_object(
            'reference_number', tr.reference_number,
            'request_status', tr.request_status,
            'created_at', tr.created_at,
            'completed_at', tr.completed_at
          )
          from public.transcript_requests tr
          where tr.student_id = s.id
          order by tr.created_at desc
          limit 1
        )
      ) as row_data
    from public.students s
    join public.campuses c
      on c.institution_id = s.institution_id
     and c.id = s.campus_id
    left join lateral (
      select
        p.id as program_id,
        p.code as program_code,
        p.name as program_name,
        spr.registration_status::text as registration_status
      from public.student_program_registrations spr
      join public.programs p
        on p.institution_id = spr.institution_id
       and p.id = spr.program_id
      where spr.student_id = s.id
      order by
        case when spr.registration_status = 'active' then 0 else 1 end,
        spr.created_at desc
      limit 1
    ) program_row on true
    left join lateral (
      select
        cr.student_id,
        cr.cgpa,
        cr.standing_code,
        cr.at_risk,
        cr.attempted_credits,
        cr.earned_credits,
        cr.calculated_at
      from public.cumulative_results cr
      where cr.student_id = s.id
      order by cr.calculated_at desc
      limit 1
    ) academic_row on true
    where s.institution_id = v_institution_id
      and (v_campus_id is null or s.campus_id = v_campus_id)
      and (v_status = '' or s.status::text = v_status)
      and (
        upper(s.student_number) like '%' || upper(v_query) || '%'
        or lower(s.full_name) like '%' || lower(v_query) || '%'
        or lower(coalesce(s.primary_email,'')) like '%' || lower(v_query) || '%'
      )
    order by s.student_number
    limit v_limit
  ) matched;

  insert into audit.audit_logs (
    institution_id, campus_id, actor_auth_user_id, actor_staff_profile_id,
    operation, entity_type, correlation_id, outcome, details
  )
  values (
    v_institution_id, v_campus_id, auth.uid(), app.current_staff_profile_id(),
    v_operation, 'student_search', v_correlation_id, 'success',
    jsonb_build_object(
      'query_length', length(v_query),
      'status_filter', nullif(v_status,''),
      'result_count', jsonb_array_length(v_rows),
      'limit', v_limit
    )
  );

  return app.rpc_success(
    v_operation, v_correlation_id, null,
    jsonb_build_object(
      'count', jsonb_array_length(v_rows),
      'students', v_rows,
      'scope', jsonb_build_object(
        'institution_id', v_institution_id,
        'campus_id', v_campus_id
      )
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;


create or replace function public.rpc_get_dashboard_snapshot(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'dashboard.snapshot.get';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id','')::uuid,
    gen_random_uuid()
  );
  v_institution_id uuid := nullif(p_request->>'institution_id','')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id','')::uuid;
  v_term_id uuid := nullif(p_request#>>'{payload,term_id}','')::uuid;
  v_snapshot jsonb;
begin
  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_REQUIRED';
  end if;

  if v_campus_id is not null
     and not exists (
       select 1
       from public.campuses c
       where c.institution_id = v_institution_id
         and c.id = v_campus_id
         and c.status = 'active'
     ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_SCOPE_INVALID';
  end if;

  if v_term_id is not null
     and not exists (
       select 1
       from public.terms t
       where t.institution_id = v_institution_id
         and t.id = v_term_id
     ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_TERM_SCOPE_INVALID';
  end if;

  if not app.is_service_request()
     and not (
       app.can_administer_institution(v_institution_id)
       or (
         v_campus_id is not null
         and app.can_access_campus(v_institution_id, v_campus_id)
       )
     ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  select jsonb_build_object(
    'generated_at', timezone('utc', now()),
    'scope', jsonb_build_object(
      'institution_id', v_institution_id,
      'campus_id', v_campus_id,
      'term_id', v_term_id
    ),
    'terms', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'term_id', t.id,
          'code', t.code,
          'name', t.name,
          'academic_year_code', ay.code,
          'academic_year_name', ay.name,
          'starts_on', t.starts_on,
          'ends_on', t.ends_on,
          'status', t.status
        )
        order by t.starts_on desc, t.sequence_number desc
      )
      from public.terms t
      join public.academic_years ay
        on ay.institution_id = t.institution_id
       and ay.id = t.academic_year_id
      where t.institution_id = v_institution_id
        and t.status in ('active','draft')
    ), '[]'::jsonb),
    'students', jsonb_build_object(
      'total', (
        select count(*) from public.students s
        where s.institution_id = v_institution_id
          and (v_campus_id is null or s.campus_id = v_campus_id)
      ),
      'active', (
        select count(*) from public.students s
        where s.institution_id = v_institution_id
          and s.status = 'active'
          and (v_campus_id is null or s.campus_id = v_campus_id)
      ),
      'at_risk', (
        select count(distinct cr.student_id)
        from public.cumulative_results cr
        where cr.institution_id = v_institution_id
          and cr.at_risk
          and (v_campus_id is null or cr.campus_id = v_campus_id)
      )
    ),
    'enrollment', jsonb_build_object(
      'active_count', (
        select count(*) from public.enrollments e
        where e.institution_id = v_institution_id
          and e.enrollment_status = 'active'
          and (v_campus_id is null or e.campus_id = v_campus_id)
          and (v_term_id is null or e.term_id = v_term_id)
      ),
      'waitlist_count', (
        select count(*)
        from public.waitlist_entries w
        join public.course_offerings co
          on co.institution_id = w.institution_id
         and co.id = w.course_offering_id
        where w.institution_id = v_institution_id
          and w.waitlist_status = 'waiting'
          and (v_campus_id is null or w.campus_id = v_campus_id)
          and (v_term_id is null or co.term_id = v_term_id)
      ),
      'rejected_requests', (
        select count(*) from public.enrollment_requests er
        where er.institution_id = v_institution_id
          and er.final_outcome = 'rejected'
          and (v_campus_id is null or er.campus_id = v_campus_id)
          and (v_term_id is null or er.term_id = v_term_id)
      ),
      'sections', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'section_id', scs.section_id,
            'section_code', scs.section_code,
            'capacity', scs.capacity,
            'enrolled_count', scs.enrolled_count,
            'remaining_capacity', scs.remaining_capacity,
            'waitlist_count', scs.waitlist_count
          )
          order by scs.section_code
        )
        from reporting.section_capacity_snapshot scs
        where scs.institution_id = v_institution_id
          and (v_campus_id is null or scs.campus_id = v_campus_id)
          and (v_term_id is null or scs.term_id = v_term_id)
      ), '[]'::jsonb)
    ),
    'marks', jsonb_build_object(
      'draft_batches', (
        select count(*)
        from public.marks_batches mb
        join public.course_offerings co
          on co.institution_id = mb.institution_id
         and co.id = mb.offering_id
        where mb.institution_id = v_institution_id
          and mb.batch_status = 'draft'
          and (v_campus_id is null or mb.campus_id = v_campus_id)
          and (v_term_id is null or co.term_id = v_term_id)
      ),
      'finalized_batches', (
        select count(*)
        from public.marks_batches mb
        join public.course_offerings co
          on co.institution_id = mb.institution_id
         and co.id = mb.offering_id
        where mb.institution_id = v_institution_id
          and mb.batch_status = 'finalized'
          and (v_campus_id is null or mb.campus_id = v_campus_id)
          and (v_term_id is null or co.term_id = v_term_id)
      ),
      'approved_batches', (
        select count(*)
        from public.marks_batches mb
        join public.course_offerings co
          on co.institution_id = mb.institution_id
         and co.id = mb.offering_id
        where mb.institution_id = v_institution_id
          and mb.batch_status = 'approved'
          and (v_campus_id is null or mb.campus_id = v_campus_id)
          and (v_term_id is null or co.term_id = v_term_id)
      )
    ),
    'results', jsonb_build_object(
      'published_course_results', (
        select count(*) from public.course_results cr
        where cr.institution_id = v_institution_id
          and cr.result_status = 'published'
          and (v_campus_id is null or cr.campus_id = v_campus_id)
          and (v_term_id is null or cr.term_id = v_term_id)
      ),
      'grade_distribution', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'letter_grade', grade_rows.letter_grade,
            'student_count', grade_rows.student_count
          )
          order by grade_rows.letter_grade
        )
        from (
          select
            coalesce(cr.letter_grade, '—') as letter_grade,
            count(*) as student_count
          from public.course_results cr
          where cr.institution_id = v_institution_id
            and cr.result_status = 'published'
            and (v_campus_id is null or cr.campus_id = v_campus_id)
            and (v_term_id is null or cr.term_id = v_term_id)
          group by coalesce(cr.letter_grade, '—')
        ) grade_rows
      ), '[]'::jsonb)
    ),
    'transcripts', jsonb_build_object(
      'pending', (
        select count(*) from public.transcript_requests tr
        where tr.institution_id = v_institution_id
          and tr.request_status in ('requested','authorized','generating')
          and (v_campus_id is null or tr.campus_id = v_campus_id)
      ),
      'ready', (
        select count(*) from public.transcript_requests tr
        where tr.institution_id = v_institution_id
          and tr.request_status in ('ready','delivered')
          and (v_campus_id is null or tr.campus_id = v_campus_id)
      )
    ),
    'operations', jsonb_build_object(
      'notification_backlog', (
        select count(*) from ops.notification_outbox no
        where no.institution_id = v_institution_id
          and no.job_status in ('pending','claimed')
          and (v_campus_id is null or no.campus_id = v_campus_id)
      ),
      'open_incidents', (
        select count(*) from ops.incidents i
        where i.institution_id = v_institution_id
          and i.incident_status in ('open','acknowledged')
          and (v_campus_id is null or i.campus_id = v_campus_id)
      )
    )
  ) into v_snapshot;

  insert into audit.audit_logs (
    institution_id, campus_id, actor_auth_user_id, actor_staff_profile_id,
    operation, entity_type, correlation_id, outcome, details
  )
  values (
    v_institution_id, v_campus_id, auth.uid(), app.current_staff_profile_id(),
    v_operation, 'administrative_dashboard', v_correlation_id, 'success',
    jsonb_build_object(
      'term_id', v_term_id,
      'generated_at', timezone('utc', now())
    )
  );

  return app.rpc_success(v_operation, v_correlation_id, null, v_snapshot);
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

revoke all on function public.rpc_search_students(jsonb) from public, anon;
revoke all on function public.rpc_get_dashboard_snapshot(jsonb) from public, anon;

grant execute on function public.rpc_search_students(jsonb) to authenticated, service_role;
grant execute on function public.rpc_get_dashboard_snapshot(jsonb) to authenticated, service_role;

comment on function public.rpc_search_students(jsonb) is
  'Workflow 07: authenticated institution/campus-scoped student search returning sanitized administrative fields only.';
comment on function public.rpc_get_dashboard_snapshot(jsonb) is
  'Workflow 07: authenticated institution/campus/term-scoped basic administrative dashboard snapshot.';

commit;
