-- Workflow 07 complete repair migration.
-- The earlier 20260721000100 migration is immutable and is not edited.
-- This migration replaces only the two public read RPC definitions, adds
-- missing search indexes, and installs one fictional identity-search fixture
-- for the synthetic DMU-0001 pilot student.

begin;

create extension if not exists pg_trgm with schema extensions;

create index if not exists students_number_prefix_idx
  on public.students (institution_id, (upper(student_number)) text_pattern_ops);

create index if not exists students_full_name_trgm_idx
  on public.students using gin ((lower(full_name)) extensions.gin_trgm_ops);

create index if not exists students_primary_email_trgm_idx
  on public.students using gin ((lower(primary_email)) extensions.gin_trgm_ops)
  where primary_email is not null;

create index if not exists student_contacts_email_trgm_idx
  on public.student_contacts using gin ((lower(email)) extensions.gin_trgm_ops)
  where email is not null and status = 'active';

-- Fictional controlled-pilot fixture only. No raw identity value is stored.
update public.students
set cnic_hash = encode(
      extensions.digest(
        convert_to(lower('DEMO-ID-DMU-0001'), 'utf8'),
        'sha256'
      ),
      'hex'
    ),
    updated_at = timezone('utc', now())
where upper(student_number) = 'DMU-0001'
  and coalesce(metadata->>'synthetic','false') = 'true'
  and cnic_hash is null;

create or replace function public.rpc_search_students(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation constant text := 'student.search';
  v_uuid_pattern constant text := '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$';
  v_correlation_id uuid := gen_random_uuid();
  v_correlation_text text := nullif(btrim(coalesce(p_request->>'correlation_id','')), '');
  v_idempotency_key text := nullif(btrim(coalesce(p_request->>'idempotency_key','')), '');
  v_institution_text text := nullif(btrim(coalesce(p_request#>>'{context,institution_id}','')), '');
  v_campus_text text := nullif(btrim(coalesce(p_request#>>'{context,campus_id}','')), '');
  v_institution_id uuid;
  v_campus_id uuid;
  v_staff_profile_id uuid;
  v_query text := btrim(coalesce(p_request#>>'{payload,query}',''));
  v_requested_search_type text := lower(btrim(coalesce(p_request#>>'{payload,search_type}','auto')));
  v_search_type text;
  v_limit_text text := nullif(btrim(coalesce(p_request#>>'{payload,limit}','')), '');
  v_offset_text text := nullif(btrim(coalesce(p_request#>>'{payload,offset}','')), '');
  v_limit integer := 25;
  v_offset integer := 0;
  v_identity_hash text;
  v_identity_masked text;
  v_rows jsonb := '[]'::jsonb;
begin
  if coalesce(p_request->>'operation','') <> v_operation then
    raise exception using errcode = 'P0001', message = 'VALIDATION_OPERATION_UNSUPPORTED';
  end if;

  if v_correlation_text is not null then
    if v_correlation_text !~ v_uuid_pattern then
      raise exception using errcode = 'P0001', message = 'VALIDATION_CORRELATION_UUID_INVALID';
    end if;
    v_correlation_id := v_correlation_text::uuid;
  end if;

  if v_idempotency_key is null then
    v_idempotency_key := 'portal:student.search:' || v_correlation_id::text;
  end if;

  if v_institution_text is null or v_institution_text !~ v_uuid_pattern then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_UUID_INVALID';
  end if;
  v_institution_id := v_institution_text::uuid;

  if v_campus_text is not null then
    if v_campus_text !~ v_uuid_pattern then
      raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_UUID_INVALID';
    end if;
    v_campus_id := v_campus_text::uuid;
  end if;

  if not exists (
    select 1 from public.institutions i
    where i.id = v_institution_id and i.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_SCOPE_INVALID';
  end if;

  if v_campus_id is not null and not exists (
    select 1 from public.campuses c
    where c.institution_id = v_institution_id
      and c.id = v_campus_id
      and c.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_SCOPE_INVALID';
  end if;

  v_staff_profile_id := app.current_staff_profile_id();
  if auth.uid() is null or v_staff_profile_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_STAFF_PROFILE_REQUIRED';
  end if;

  if app.can_administer_institution(v_institution_id) then
    null;
  elsif v_campus_id is not null and app.can_access_campus(v_institution_id, v_campus_id) then
    null;
  elsif exists (
    select 1
    from public.role_assignments ra
    where ra.staff_profile_id = v_staff_profile_id
      and ra.institution_id = v_institution_id
      and ra.role = 'campus_administrator'
      and ra.status = 'active'
      and ra.valid_from <= timezone('utc', now())
      and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
  ) and v_campus_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_CAMPUS_SCOPE_REQUIRED';
  else
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_query = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_QUERY_REQUIRED';
  end if;

  if v_requested_search_type not in ('auto','student_number','name','email','identity_reference') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_TYPE_UNSUPPORTED';
  end if;

  if v_limit_text is not null then
    if v_limit_text !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_LIMIT_INVALID';
    end if;
    v_limit := v_limit_text::integer;
  end if;
  if v_limit < 1 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_LIMIT_INVALID';
  end if;
  v_limit := least(v_limit, 25);

  if v_offset_text is not null then
    if v_offset_text !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001', message = 'VALIDATION_SEARCH_OFFSET_INVALID';
    end if;
    v_offset := v_offset_text::integer;
  end if;

  v_search_type := v_requested_search_type;
  if v_search_type = 'auto' then
    if position('@' in v_query) > 1 then
      v_search_type := 'email';
    elsif regexp_replace(v_query, '[^0-9]', '', 'g') ~ '^[0-9]{13}$' then
      v_search_type := 'identity_reference';
    elsif v_query ~* '^[A-Z0-9]+[-_/][A-Z0-9_-]+$' or v_query ~ '[0-9]' then
      v_search_type := 'student_number';
    else
      v_search_type := 'name';
    end if;
  end if;

  if v_search_type = 'name' and length(v_query) < 2 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_NAME_QUERY_TOO_SHORT';
  end if;

  if v_search_type = 'identity_reference' then
    v_identity_hash := encode(
      extensions.digest(convert_to(lower(btrim(v_query)), 'utf8'), 'sha256'),
      'hex'
    );
    v_identity_masked := case
      when length(v_query) <= 4 then repeat('*', length(v_query))
      else repeat('*', greatest(length(v_query) - 4, 4)) || right(v_query, 4)
    end;
  end if;

  select coalesce(jsonb_agg(q.row_data order by q.sort_student_number, q.sort_id), '[]'::jsonb)
  into v_rows
  from (
    select
      s.student_number as sort_student_number,
      s.id as sort_id,
      jsonb_build_object(
        'student_id', s.id,
        'student_number', s.student_number,
        'full_name', s.full_name,
        'primary_email', coalesce(s.primary_email, contact_row.email),
        'identity_reference_masked', case
          when v_search_type = 'identity_reference' then v_identity_masked
          else null
        end,
        'student_status', s.status,
        'institution', jsonb_build_object(
          'id', i.id,
          'code', i.code,
          'name', i.name
        ),
        'campus', jsonb_build_object(
          'id', c.id,
          'code', c.code,
          'name', c.name
        ),
        'program', case
          when program_row.program_id is null then null
          else jsonb_build_object(
            'id', program_row.program_id,
            'code', program_row.program_code,
            'name', program_row.program_name
          )
        end,
        'current_gpa', semester_row.gpa,
        'current_cgpa', cumulative_row.cgpa,
        'academic_standing', coalesce(cumulative_row.standing_code, semester_row.standing_code),
        'at_risk', coalesce(cumulative_row.at_risk, semester_row.at_risk, false)
      ) as row_data
    from public.students s
    join public.institutions i on i.id = s.institution_id
    join public.campuses c
      on c.institution_id = s.institution_id
     and c.id = s.campus_id
    left join lateral (
      select sc.email
      from public.student_contacts sc
      where sc.institution_id = s.institution_id
        and sc.student_id = s.id
        and sc.status = 'active'
        and sc.email is not null
      order by sc.is_primary desc, sc.created_at, sc.id
      limit 1
    ) contact_row on true
    left join lateral (
      select p.id as program_id, p.code as program_code, p.name as program_name
      from public.student_program_registrations spr
      join public.programs p
        on p.institution_id = spr.institution_id
       and p.id = spr.program_id
      where spr.institution_id = s.institution_id
        and spr.student_id = s.id
      order by
        case when spr.registration_status = 'active' then 0 else 1 end,
        spr.created_at desc,
        spr.id desc
      limit 1
    ) program_row on true
    left join lateral (
      select sr.gpa, sr.standing_code, sr.at_risk
      from public.semester_results sr
      where sr.institution_id = s.institution_id
        and sr.student_id = s.id
      order by sr.calculated_at desc, sr.id desc
      limit 1
    ) semester_row on true
    left join lateral (
      select cr.cgpa, cr.standing_code, cr.at_risk
      from public.cumulative_results cr
      where cr.institution_id = s.institution_id
        and cr.student_id = s.id
      order by cr.calculated_at desc, cr.id desc
      limit 1
    ) cumulative_row on true
    where s.institution_id = v_institution_id
      and (v_campus_id is null or s.campus_id = v_campus_id)
      and (
        (v_search_type = 'student_number' and upper(s.student_number) like upper(v_query) || '%')
        or (v_search_type = 'name' and lower(s.full_name) like '%' || lower(v_query) || '%')
        or (
          v_search_type = 'email'
          and (
            lower(coalesce(s.primary_email,'')) like '%' || lower(v_query) || '%'
            or exists (
              select 1 from public.student_contacts sce
              where sce.institution_id = s.institution_id
                and sce.student_id = s.id
                and sce.status = 'active'
                and lower(coalesce(sce.email,'')) like '%' || lower(v_query) || '%'
            )
          )
        )
        or (v_search_type = 'identity_reference' and s.cnic_hash = v_identity_hash)
      )
    order by s.student_number, s.id
    limit v_limit offset v_offset
  ) q;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'query', case when v_search_type = 'identity_reference' then v_identity_masked else v_query end,
      'search_type', v_search_type,
      'count', jsonb_array_length(v_rows),
      'limit', v_limit,
      'offset', v_offset,
      'students', v_rows
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
  v_operation constant text := 'dashboard.snapshot';
  v_uuid_pattern constant text := '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$';
  v_correlation_id uuid := gen_random_uuid();
  v_correlation_text text := nullif(btrim(coalesce(p_request->>'correlation_id','')), '');
  v_idempotency_key text := nullif(btrim(coalesce(p_request->>'idempotency_key','')), '');
  v_institution_text text := nullif(btrim(coalesce(p_request#>>'{context,institution_id}','')), '');
  v_campus_text text := nullif(btrim(coalesce(p_request#>>'{context,campus_id}','')), '');
  v_term_text text := nullif(btrim(coalesce(p_request#>>'{payload,term_id}','')), '');
  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_staff_profile_id uuid;
  v_institution_code text;
  v_institution_name text;
  v_campus_code text;
  v_campus_name text;
  v_term_code text;
  v_term_name text;
  v_students_total bigint := 0;
  v_students_active bigint := 0;
  v_active_enrollments bigint := 0;
  v_waitlist_count bigint := 0;
  v_rejected_requests bigint := 0;
  v_marks_expected bigint := 0;
  v_marks_submitted bigint := 0;
  v_marks_completion numeric := 0;
  v_at_risk bigint := 0;
  v_average_gpa numeric := 0;
  v_average_cgpa numeric := 0;
  v_pending_transcripts bigint := 0;
  v_notification_backlog bigint := 0;
  v_open_incidents bigint := 0;
  v_available_terms jsonb := '[]'::jsonb;
  v_grade_distribution jsonb := '[]'::jsonb;
  v_course_capacity jsonb := '[]'::jsonb;
begin
  if coalesce(p_request->>'operation','') <> v_operation then
    raise exception using errcode = 'P0001', message = 'VALIDATION_OPERATION_UNSUPPORTED';
  end if;

  if v_correlation_text is not null then
    if v_correlation_text !~ v_uuid_pattern then
      raise exception using errcode = 'P0001', message = 'VALIDATION_CORRELATION_UUID_INVALID';
    end if;
    v_correlation_id := v_correlation_text::uuid;
  end if;

  if v_idempotency_key is null then
    v_idempotency_key := 'portal:dashboard.snapshot:' || v_correlation_id::text;
  end if;

  if v_institution_text is null or v_institution_text !~ v_uuid_pattern then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_UUID_INVALID';
  end if;
  v_institution_id := v_institution_text::uuid;

  if v_campus_text is not null then
    if v_campus_text !~ v_uuid_pattern then
      raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_UUID_INVALID';
    end if;
    v_campus_id := v_campus_text::uuid;
  end if;

  if v_term_text is not null then
    if v_term_text !~ v_uuid_pattern then
      raise exception using errcode = 'P0001', message = 'VALIDATION_TERM_UUID_INVALID';
    end if;
    v_term_id := v_term_text::uuid;
  end if;

  select i.code, i.name
  into v_institution_code, v_institution_name
  from public.institutions i
  where i.id = v_institution_id and i.status = 'active';

  if v_institution_code is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_SCOPE_INVALID';
  end if;

  if v_campus_id is not null then
    select c.code, c.name
    into v_campus_code, v_campus_name
    from public.campuses c
    where c.institution_id = v_institution_id
      and c.id = v_campus_id
      and c.status = 'active';
    if v_campus_code is null then
      raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_SCOPE_INVALID';
    end if;
  else
    v_campus_name := 'All permitted campuses';
  end if;

  v_staff_profile_id := app.current_staff_profile_id();
  if auth.uid() is null or v_staff_profile_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_STAFF_PROFILE_REQUIRED';
  end if;

  if app.can_administer_institution(v_institution_id) then
    null;
  elsif v_campus_id is not null and app.can_access_campus(v_institution_id, v_campus_id) then
    null;
  elsif exists (
    select 1
    from public.role_assignments ra
    where ra.staff_profile_id = v_staff_profile_id
      and ra.institution_id = v_institution_id
      and ra.role = 'campus_administrator'
      and ra.status = 'active'
      and ra.valid_from <= timezone('utc', now())
      and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
  ) and v_campus_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_CAMPUS_SCOPE_REQUIRED';
  else
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  if v_term_id is not null and not exists (
    select 1 from public.terms t
    where t.institution_id = v_institution_id and t.id = v_term_id
  ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_TERM_SCOPE_INVALID';
  end if;

  if v_term_id is null then
    select t.id
    into v_term_id
    from public.terms t
    where t.institution_id = v_institution_id
      and t.status = 'active'
    order by
      case when current_date between t.starts_on and t.ends_on then 0 else 1 end,
      t.starts_on desc,
      t.sequence_number desc,
      t.id
    limit 1;
  end if;

  if v_term_id is not null then
    select t.code, t.name
    into v_term_code, v_term_name
    from public.terms t
    where t.institution_id = v_institution_id and t.id = v_term_id;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'term_id', t.id,
      'term_code', t.code,
      'term_name', t.name,
      'academic_year_code', ay.code,
      'academic_year_name', ay.name,
      'status', t.status,
      'starts_on', t.starts_on,
      'ends_on', t.ends_on
    ) order by t.starts_on desc, t.sequence_number desc, t.id
  ), '[]'::jsonb)
  into v_available_terms
  from public.terms t
  join public.academic_years ay
    on ay.institution_id = t.institution_id
   and ay.id = t.academic_year_id
  where t.institution_id = v_institution_id
    and t.status in ('active','draft');

  select count(*), count(*) filter (where s.status = 'active')
  into v_students_total, v_students_active
  from public.students s
  where s.institution_id = v_institution_id
    and (v_campus_id is null or s.campus_id = v_campus_id);

  select count(*)
  into v_active_enrollments
  from public.enrollments e
  where e.institution_id = v_institution_id
    and (v_campus_id is null or e.campus_id = v_campus_id)
    and (v_term_id is null or e.term_id = v_term_id)
    and e.enrollment_status = 'active';

  select count(*)
  into v_waitlist_count
  from public.waitlist_entries w
  join public.course_offerings co
    on co.institution_id = w.institution_id
   and co.id = w.course_offering_id
  where w.institution_id = v_institution_id
    and (v_campus_id is null or w.campus_id = v_campus_id)
    and (v_term_id is null or co.term_id = v_term_id)
    and w.waitlist_status = 'waiting';

  select count(*)
  into v_rejected_requests
  from public.enrollment_requests er
  where er.institution_id = v_institution_id
    and (v_campus_id is null or er.campus_id = v_campus_id)
    and (v_term_id is null or er.term_id = v_term_id)
    and (er.final_outcome = 'rejected' or er.request_status = 'rejected');

  select count(*)
  into v_marks_expected
  from public.sections s
  join public.course_offerings co
    on co.institution_id = s.institution_id
   and co.id = s.offering_id
  where s.institution_id = v_institution_id
    and (v_campus_id is null or s.campus_id = v_campus_id)
    and (v_term_id is null or co.term_id = v_term_id)
    and s.status <> 'cancelled'
    and co.status <> 'cancelled';

  select count(distinct mb.section_id)
  into v_marks_submitted
  from public.marks_batches mb
  join public.course_offerings co
    on co.institution_id = mb.institution_id
   and co.id = mb.offering_id
  where mb.institution_id = v_institution_id
    and (v_campus_id is null or mb.campus_id = v_campus_id)
    and (v_term_id is null or co.term_id = v_term_id)
    and mb.batch_status in ('finalized','approved','rejected');

  v_marks_completion := case
    when v_marks_expected = 0 then 0
    else round((v_marks_submitted::numeric * 100.0) / v_marks_expected::numeric, 2)
  end;

  select count(*)
  into v_at_risk
  from (
    select distinct on (cr.student_id) cr.student_id, cr.at_risk
    from public.cumulative_results cr
    where cr.institution_id = v_institution_id
      and (v_campus_id is null or cr.campus_id = v_campus_id)
    order by cr.student_id, cr.calculated_at desc, cr.id desc
  ) latest
  where latest.at_risk;

  select coalesce(round(avg(sr.gpa)::numeric, 3), 0)
  into v_average_gpa
  from public.semester_results sr
  where sr.institution_id = v_institution_id
    and (v_campus_id is null or sr.campus_id = v_campus_id)
    and (v_term_id is null or sr.term_id = v_term_id)
    and sr.result_status in ('approved','published')
    and sr.gpa is not null;

  select coalesce(round(avg(latest.cgpa)::numeric, 3), 0)
  into v_average_cgpa
  from (
    select distinct on (cr.student_id) cr.student_id, cr.cgpa
    from public.cumulative_results cr
    where cr.institution_id = v_institution_id
      and (v_campus_id is null or cr.campus_id = v_campus_id)
      and cr.cgpa is not null
    order by cr.student_id, cr.calculated_at desc, cr.id desc
  ) latest;

  select count(*)
  into v_pending_transcripts
  from public.transcript_requests tr
  where tr.institution_id = v_institution_id
    and (v_campus_id is null or tr.campus_id = v_campus_id)
    and tr.request_status in ('requested','authorized','generating');

  select count(*)
  into v_notification_backlog
  from ops.notification_outbox no
  where no.institution_id = v_institution_id
    and (v_campus_id is null or no.campus_id = v_campus_id)
    and no.job_status in ('pending','claimed','running');

  select count(*)
  into v_open_incidents
  from ops.incidents inc
  where inc.institution_id = v_institution_id
    and (v_campus_id is null or inc.campus_id = v_campus_id)
    and inc.incident_status in ('open','acknowledged');

  select coalesce(jsonb_agg(
    jsonb_build_object('letter_grade', gd.letter_grade, 'count', gd.grade_count)
    order by gd.letter_grade
  ), '[]'::jsonb)
  into v_grade_distribution
  from (
    select coalesce(cr.letter_grade, '—') as letter_grade, count(*) as grade_count
    from public.course_results cr
    where cr.institution_id = v_institution_id
      and (v_campus_id is null or cr.campus_id = v_campus_id)
      and (v_term_id is null or cr.term_id = v_term_id)
      and cr.result_status = 'published'
    group by coalesce(cr.letter_grade, '—')
  ) gd;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'course_code', capacity.course_code,
      'course_title', capacity.course_title,
      'section_code', capacity.section_code,
      'capacity', capacity.capacity,
      'enrolled', capacity.enrolled,
      'remaining', greatest(capacity.capacity - capacity.enrolled, 0),
      'waitlisted', capacity.waitlisted
    ) order by capacity.course_code, capacity.section_code
  ), '[]'::jsonb)
  into v_course_capacity
  from (
    select
      course.code as course_code,
      course.title as course_title,
      section.code as section_code,
      section.capacity,
      (
        select count(*)
        from public.enrollments e
        where e.institution_id = section.institution_id
          and e.section_id = section.id
          and e.enrollment_status = 'active'
      ) as enrolled,
      (
        select count(*)
        from public.waitlist_entries w
        where w.institution_id = section.institution_id
          and w.course_offering_id = offering.id
          and w.waitlist_status = 'waiting'
          and (w.preferred_section_id is null or w.preferred_section_id = section.id)
      ) as waitlisted
    from public.sections section
    join public.course_offerings offering
      on offering.institution_id = section.institution_id
     and offering.id = section.offering_id
    join public.courses course
      on course.institution_id = offering.institution_id
     and course.id = offering.course_id
    where section.institution_id = v_institution_id
      and (v_campus_id is null or section.campus_id = v_campus_id)
      and (v_term_id is null or offering.term_id = v_term_id)
      and section.status <> 'cancelled'
      and offering.status <> 'cancelled'
  ) capacity;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'scope', jsonb_build_object(
        'institution_id', v_institution_id,
        'institution_code', v_institution_code,
        'institution_name', v_institution_name,
        'campus_id', v_campus_id,
        'campus_code', v_campus_code,
        'campus_name', v_campus_name,
        'term_id', v_term_id,
        'term_code', v_term_code,
        'term_name', v_term_name
      ),
      'metrics', jsonb_build_object(
        'students_total', coalesce(v_students_total,0),
        'students_active', coalesce(v_students_active,0),
        'active_enrollments', coalesce(v_active_enrollments,0),
        'waitlist_count', coalesce(v_waitlist_count,0),
        'rejected_or_ineligible_requests', coalesce(v_rejected_requests,0),
        'marks_batches_expected', coalesce(v_marks_expected,0),
        'marks_batches_submitted', coalesce(v_marks_submitted,0),
        'marks_completion_percent', coalesce(v_marks_completion,0),
        'at_risk_students', coalesce(v_at_risk,0),
        'average_gpa', coalesce(v_average_gpa,0),
        'average_cgpa', coalesce(v_average_cgpa,0),
        'pending_transcripts', coalesce(v_pending_transcripts,0),
        'notification_backlog', coalesce(v_notification_backlog,0),
        'open_incidents', coalesce(v_open_incidents,0)
      ),
      'grade_distribution', coalesce(v_grade_distribution, '[]'::jsonb),
      'course_capacity', coalesce(v_course_capacity, '[]'::jsonb),
      'available_terms', coalesce(v_available_terms, '[]'::jsonb),
      'generated_at', timezone('utc', now())
    )
  );
exception when others then
  return app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
end;
$function$;

revoke all on function public.rpc_search_students(jsonb) from public, anon, service_role;
revoke all on function public.rpc_get_dashboard_snapshot(jsonb) from public, anon, service_role;
grant execute on function public.rpc_search_students(jsonb) to authenticated;
grant execute on function public.rpc_get_dashboard_snapshot(jsonb) to authenticated;

comment on function public.rpc_search_students(jsonb) is
  'Workflow 07: authenticated staff-only student search with institution/campus scope, exact identity hashing, bounded paging and sanitized results.';
comment on function public.rpc_get_dashboard_snapshot(jsonb) is
  'Workflow 07: authenticated staff-only, server-aggregated administrative dashboard with institution/campus/term scope and zero-safe metrics.';

commit;
