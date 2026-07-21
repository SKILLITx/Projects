-- Phase 4, Workflow 04:
-- Results approval, correction control, configured grading, GPA/CGPA,
-- academic standing, idempotent publication and notification outbox writes.

begin;

alter table public.mark_correction_requests
  add column if not exists evidence_url text;

do $do$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'mark_corrections_evidence_url_chk'
      and conrelid = 'public.mark_correction_requests'::regclass
  ) then
    alter table public.mark_correction_requests
      add constraint mark_corrections_evidence_url_chk
      check (
        evidence_url is null
        or evidence_url ~* '^https://'
      );
  end if;
end
$do$;

create or replace function app.results_staff_actor(p_request jsonb)
returns table (
  staff_profile_id uuid,
  auth_user_id uuid,
  email text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_email text;
  v_auth_user_id uuid;
  v_identity_verified boolean;
begin
  if app.is_service_request() then
    v_identity_verified :=
      lower(coalesce(p_request#>>'{requester,identity_verified}', 'false'))
      in ('true', '1', 'yes');

    if not v_identity_verified then
      raise exception using
        errcode = 'P0001',
        message = 'AUTH_VERIFIED_IDENTITY_REQUIRED';
    end if;

    v_email := lower(btrim(coalesce(
      p_request#>>'{requester,verified_email}',
      p_request#>>'{requester,email}',
      ''
    )));

    if v_email = '' or position('@' in v_email) <= 1 then
      raise exception using
        errcode = 'P0001',
        message = 'AUTH_VERIFIED_EMAIL_REQUIRED';
    end if;

    select sp.id, sp.auth_user_id, lower(sp.email)
      into staff_profile_id, auth_user_id, email
    from public.staff_profiles sp
    where lower(sp.email) = v_email
      and sp.status = 'active'
    limit 1;
  else
    v_auth_user_id := auth.uid();

    if v_auth_user_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'AUTH_LOGIN_REQUIRED';
    end if;

    select sp.id, sp.auth_user_id, lower(sp.email)
      into staff_profile_id, auth_user_id, email
    from public.staff_profiles sp
    where sp.auth_user_id = v_auth_user_id
      and sp.status = 'active'
    limit 1;
  end if;

  if staff_profile_id is null or auth_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'AUTH_ACTIVE_STAFF_PROFILE_REQUIRED';
  end if;

  return next;
end;
$function$;

create or replace function app.staff_can_administer_results(
  p_staff_profile_id uuid,
  p_institution_id uuid,
  p_campus_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.role_assignments ra
      where ra.staff_profile_id = p_staff_profile_id
        and ra.role = 'super_administrator'
        and ra.institution_id is null
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    )
    or exists (
      select 1
      from public.role_assignments ra
      where ra.staff_profile_id = p_staff_profile_id
        and ra.institution_id = p_institution_id
        and ra.role = 'registrar_admin'
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    )
    or exists (
      select 1
      from public.role_assignments ra
      join public.campus_assignments ca
        on ca.role_assignment_id = ra.id
       and ca.institution_id = ra.institution_id
      where ra.staff_profile_id = p_staff_profile_id
        and ra.institution_id = p_institution_id
        and ra.role = 'campus_administrator'
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
        and ca.campus_id = p_campus_id
        and ca.status = 'active'
        and ca.valid_from <= timezone('utc', now())
        and (ca.valid_to is null or ca.valid_to > timezone('utc', now()))
    );
$function$;

create or replace function app.staff_is_teacher_for_results_section(
  p_staff_profile_id uuid,
  p_institution_id uuid,
  p_campus_id uuid,
  p_section_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.role_assignments ra
      where ra.staff_profile_id = p_staff_profile_id
        and ra.institution_id = p_institution_id
        and ra.role = 'teacher'
        and ra.status = 'active'
        and ra.valid_from <= timezone('utc', now())
        and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    )
    and exists (
      select 1
      from public.teacher_assignments ta
      where ta.staff_profile_id = p_staff_profile_id
        and ta.institution_id = p_institution_id
        and ta.campus_id = p_campus_id
        and ta.section_id = p_section_id
        and ta.status = 'active'
        and (ta.valid_from is null or ta.valid_from <= current_date)
        and (ta.valid_to is null or ta.valid_to >= current_date)
    );
$function$;

create or replace function app.calculate_course_result(
  p_student_id uuid,
  p_course_offering_id uuid,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_grading_policy_id uuid;
  v_enrollment_id uuid;
  v_section_id uuid;
  v_enrollment_status text;
  v_credit_hours numeric(5,2);
  v_method jsonb := '{}'::jsonb;
  v_rounding_scale integer := 2;
  v_total numeric(8,4);
  v_missing_required integer := 0;
  v_grade jsonb;
  v_letter_grade text;
  v_grade_point numeric;
  v_outcome_code text;
  v_result_id uuid;
begin
  select
    co.institution_id,
    co.campus_id,
    co.term_id,
    co.grading_policy_id,
    e.id,
    e.section_id,
    e.enrollment_status,
    c.credit_hours,
    gp.calculation_method
  into
    v_institution_id,
    v_campus_id,
    v_term_id,
    v_grading_policy_id,
    v_enrollment_id,
    v_section_id,
    v_enrollment_status,
    v_credit_hours,
    v_method
  from public.course_offerings co
  join public.courses c on c.id = co.course_id
  join public.enrollments e
    on e.course_offering_id = co.id
   and e.student_id = p_student_id
  join public.grading_policies gp on gp.id = co.grading_policy_id
  where co.id = p_course_offering_id
    and e.enrollment_status <> 'cancelled'
  order by e.enrolled_at desc
  limit 1;

  if v_enrollment_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'RESULT_ENROLLMENT_NOT_FOUND';
  end if;

  begin
    v_rounding_scale := greatest(
      0,
      least(
        4,
        coalesce(nullif(v_method->>'rounding_scale', '')::integer, 2)
      )
    );
  exception when others then
    v_rounding_scale := 2;
  end;

  if v_enrollment_status = 'withdrawn' then
    v_total := null;
    v_letter_grade := 'W';
    v_grade_point := null;
    v_outcome_code := 'withdrawn';
  elsif v_enrollment_status = 'audit' then
    v_total := null;
    v_letter_grade := 'AU';
    v_grade_point := null;
    v_outcome_code := 'audit';
  elsif v_enrollment_status = 'incomplete' then
    v_total := null;
    v_letter_grade := 'I';
    v_grade_point := null;
    v_outcome_code := 'incomplete';
  else
    with applicable_assessments as (
      select
        a.id as assessment_id,
        a.maximum_marks,
        ac.weight_percent,
        ac.required
      from public.assessments a
      join public.assessment_components ac on ac.id = a.component_id
      where a.offering_id = p_course_offering_id
        and (a.section_id is null or a.section_id = v_section_id)
        and a.status = 'active'
        and ac.status = 'active'
    ),
    latest_marks as (
      select distinct on (sm.assessment_id)
        sm.assessment_id,
        sm.marks_obtained,
        sm.is_absent,
        sm.is_missing
      from public.student_marks sm
      join public.marks_batches mb on mb.id = sm.marks_batch_id
      where sm.student_id = p_student_id
        and mb.offering_id = p_course_offering_id
        and mb.section_id = v_section_id
        and mb.batch_status = 'approved'
      order by
        sm.assessment_id,
        mb.version_number desc,
        sm.updated_at desc
    )
    select
      count(*) filter (
        where aa.required
          and (
            lm.assessment_id is null
            or lm.is_missing
          )
      ),
      round(
        coalesce(
          sum(
            case
              when lm.assessment_id is null or lm.is_missing then 0
              when lm.is_absent then 0
              when lm.marks_obtained is null then 0
              else
                (lm.marks_obtained / nullif(aa.maximum_marks, 0))
                * aa.weight_percent
            end
          ),
          0
        ),
        v_rounding_scale
      )
    into v_missing_required, v_total
    from applicable_assessments aa
    left join latest_marks lm on lm.assessment_id = aa.assessment_id;

    if v_missing_required > 0 then
      v_letter_grade := 'I';
      v_grade_point := null;
      v_outcome_code := 'incomplete';
    else
      v_grade := app.resolve_grade(v_grading_policy_id, v_total);
      v_letter_grade := v_grade->>'letter_grade';
      v_grade_point := nullif(v_grade->>'grade_point', '')::numeric;
      v_outcome_code := coalesce(v_grade->>'outcome_code', 'incomplete');
    end if;
  end if;

  insert into public.course_results (
    institution_id,
    campus_id,
    student_id,
    term_id,
    course_offering_id,
    enrollment_id,
    grading_policy_id,
    total_score,
    letter_grade,
    grade_point,
    credit_hours,
    outcome_code,
    result_status,
    calculation_version,
    correlation_id
  )
  values (
    v_institution_id,
    v_campus_id,
    p_student_id,
    v_term_id,
    p_course_offering_id,
    v_enrollment_id,
    v_grading_policy_id,
    v_total,
    v_letter_grade,
    v_grade_point,
    v_credit_hours,
    v_outcome_code,
    'calculated',
    1,
    p_correlation_id
  )
  on conflict (student_id, course_offering_id)
  do update set
    total_score = excluded.total_score,
    letter_grade = excluded.letter_grade,
    grade_point = excluded.grade_point,
    credit_hours = excluded.credit_hours,
    outcome_code = excluded.outcome_code,
    result_status = case
      when row(
        public.course_results.total_score,
        public.course_results.letter_grade,
        public.course_results.grade_point,
        public.course_results.credit_hours,
        public.course_results.outcome_code
      ) is distinct from row(
        excluded.total_score,
        excluded.letter_grade,
        excluded.grade_point,
        excluded.credit_hours,
        excluded.outcome_code
      )
      then 'calculated'::public.result_status
      else public.course_results.result_status
    end,
    calculation_version = case
      when row(
        public.course_results.total_score,
        public.course_results.letter_grade,
        public.course_results.grade_point,
        public.course_results.credit_hours,
        public.course_results.outcome_code
      ) is distinct from row(
        excluded.total_score,
        excluded.letter_grade,
        excluded.grade_point,
        excluded.credit_hours,
        excluded.outcome_code
      )
      then public.course_results.calculation_version + 1
      else public.course_results.calculation_version
    end,
    approved_at = case
      when row(
        public.course_results.total_score,
        public.course_results.letter_grade,
        public.course_results.grade_point,
        public.course_results.credit_hours,
        public.course_results.outcome_code
      ) is distinct from row(
        excluded.total_score,
        excluded.letter_grade,
        excluded.grade_point,
        excluded.credit_hours,
        excluded.outcome_code
      )
      then null
      else public.course_results.approved_at
    end,
    published_at = case
      when row(
        public.course_results.total_score,
        public.course_results.letter_grade,
        public.course_results.grade_point,
        public.course_results.credit_hours,
        public.course_results.outcome_code
      ) is distinct from row(
        excluded.total_score,
        excluded.letter_grade,
        excluded.grade_point,
        excluded.credit_hours,
        excluded.outcome_code
      )
      then null
      else public.course_results.published_at
    end,
    correlation_id = excluded.correlation_id,
    calculated_at = case
      when row(
        public.course_results.total_score,
        public.course_results.letter_grade,
        public.course_results.grade_point,
        public.course_results.credit_hours,
        public.course_results.outcome_code
      ) is distinct from row(
        excluded.total_score,
        excluded.letter_grade,
        excluded.grade_point,
        excluded.credit_hours,
        excluded.outcome_code
      )
      then timezone('utc', now())
      else public.course_results.calculated_at
    end,
    updated_at = timezone('utc', now())
  returning id into v_result_id;

  return v_result_id;
end;
$function$;

create or replace function app.recalculate_academic_record(
  p_student_id uuid,
  p_term_id uuid,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_institution_id uuid;
  v_campus_id uuid;
  v_registration_id uuid;
  v_grading_policy_id uuid;
  v_method jsonb := '{}'::jsonb;
  v_repeat_policy text := 'latest_attempt';
  v_rounding_scale integer := 2;
  v_attempted numeric(10,2);
  v_earned numeric(10,2);
  v_quality numeric(12,4);
  v_gpa numeric(6,4);
  v_semester_standing text;
  v_semester_at_risk boolean;
  v_semester_id uuid;
  v_cum_attempted numeric(10,2);
  v_cum_earned numeric(10,2);
  v_cum_quality numeric(12,4);
  v_cgpa numeric(6,4);
  v_cumulative_standing text;
  v_cumulative_at_risk boolean;
begin
  select
    s.institution_id,
    s.campus_id,
    spr.id
  into
    v_institution_id,
    v_campus_id,
    v_registration_id
  from public.students s
  join public.student_program_registrations spr
    on spr.student_id = s.id
   and spr.registration_status = 'active'
  where s.id = p_student_id
  order by spr.created_at desc
  limit 1;

  if v_registration_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'RESULT_ACTIVE_PROGRAM_NOT_FOUND';
  end if;

  select cr.grading_policy_id, gp.calculation_method
    into v_grading_policy_id, v_method
  from public.course_results cr
  join public.grading_policies gp on gp.id = cr.grading_policy_id
  where cr.student_id = p_student_id
    and cr.term_id = p_term_id
    and cr.result_status in ('calculated', 'approved', 'published')
  order by cr.calculated_at desc, cr.id
  limit 1;

  if v_grading_policy_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'RESULT_GRADING_POLICY_NOT_FOUND';
  end if;

  v_repeat_policy := lower(coalesce(
    nullif(v_method->>'repeat_policy', ''),
    'latest_attempt'
  ));

  if v_repeat_policy not in ('latest_attempt', 'highest_grade', 'all_attempts') then
    v_repeat_policy := 'latest_attempt';
  end if;

  begin
    v_rounding_scale := greatest(
      0,
      least(
        4,
        coalesce(nullif(v_method->>'rounding_scale', '')::integer, 2)
      )
    );
  exception when others then
    v_rounding_scale := 2;
  end;

  select
    coalesce(sum(cr.credit_hours)
      filter (where cr.outcome_code in ('pass', 'fail')), 0),
    coalesce(sum(cr.credit_hours)
      filter (where cr.outcome_code = 'pass'), 0),
    coalesce(sum(cr.credit_hours * coalesce(cr.grade_point, 0))
      filter (where cr.outcome_code in ('pass', 'fail')), 0)
  into v_attempted, v_earned, v_quality
  from public.course_results cr
  where cr.student_id = p_student_id
    and cr.term_id = p_term_id
    and cr.result_status in ('calculated', 'approved', 'published');

  v_gpa := case
    when v_attempted > 0
      then round(v_quality / v_attempted, v_rounding_scale)
    else null
  end;

  select asr.standing_code, asr.at_risk
    into v_semester_standing, v_semester_at_risk
  from public.academic_standing_rules asr
  where asr.grading_policy_id = v_grading_policy_id
    and v_gpa between asr.minimum_cgpa and asr.maximum_cgpa
  order by asr.display_order
  limit 1;

  v_semester_standing := coalesce(v_semester_standing, 'UNCLASSIFIED');
  v_semester_at_risk := coalesce(v_semester_at_risk, false);

  insert into public.semester_results (
    institution_id,
    campus_id,
    student_id,
    program_registration_id,
    term_id,
    attempted_credits,
    earned_credits,
    quality_points,
    gpa,
    standing_code,
    at_risk,
    result_status,
    correlation_id
  )
  values (
    v_institution_id,
    v_campus_id,
    p_student_id,
    v_registration_id,
    p_term_id,
    v_attempted,
    v_earned,
    v_quality,
    v_gpa,
    v_semester_standing,
    v_semester_at_risk,
    'calculated',
    p_correlation_id
  )
  on conflict (student_id, term_id)
  do update set
    attempted_credits = excluded.attempted_credits,
    earned_credits = excluded.earned_credits,
    quality_points = excluded.quality_points,
    gpa = excluded.gpa,
    standing_code = excluded.standing_code,
    at_risk = excluded.at_risk,
    result_status = case
      when row(
        public.semester_results.attempted_credits,
        public.semester_results.earned_credits,
        public.semester_results.quality_points,
        public.semester_results.gpa,
        public.semester_results.standing_code,
        public.semester_results.at_risk
      ) is distinct from row(
        excluded.attempted_credits,
        excluded.earned_credits,
        excluded.quality_points,
        excluded.gpa,
        excluded.standing_code,
        excluded.at_risk
      )
      then 'calculated'::public.result_status
      else public.semester_results.result_status
    end,
    published_at = case
      when row(
        public.semester_results.attempted_credits,
        public.semester_results.earned_credits,
        public.semester_results.quality_points,
        public.semester_results.gpa,
        public.semester_results.standing_code,
        public.semester_results.at_risk
      ) is distinct from row(
        excluded.attempted_credits,
        excluded.earned_credits,
        excluded.quality_points,
        excluded.gpa,
        excluded.standing_code,
        excluded.at_risk
      )
      then null
      else public.semester_results.published_at
    end,
    correlation_id = excluded.correlation_id,
    calculated_at = timezone('utc', now()),
    updated_at = timezone('utc', now())
  returning id into v_semester_id;

  with ranked_attempts as (
    select
      cr.*,
      row_number() over (
        partition by co.course_id
        order by
          case
            when v_repeat_policy = 'highest_grade'
              then coalesce(cr.grade_point, -1)
            else null
          end desc nulls last,
          t.starts_on desc,
          cr.calculated_at desc,
          cr.id desc
      ) as attempt_rank
    from public.course_results cr
    join public.course_offerings co on co.id = cr.course_offering_id
    join public.terms t on t.id = cr.term_id
    where cr.student_id = p_student_id
      and cr.result_status in ('calculated', 'approved', 'published')
  ),
  included_attempts as (
    select *
    from ranked_attempts
    where v_repeat_policy = 'all_attempts'
       or attempt_rank = 1
  )
  select
    coalesce(sum(credit_hours)
      filter (where outcome_code in ('pass', 'fail')), 0),
    coalesce(sum(credit_hours)
      filter (where outcome_code = 'pass'), 0),
    coalesce(sum(credit_hours * coalesce(grade_point, 0))
      filter (where outcome_code in ('pass', 'fail')), 0)
  into v_cum_attempted, v_cum_earned, v_cum_quality
  from included_attempts;

  v_cgpa := case
    when v_cum_attempted > 0
      then round(v_cum_quality / v_cum_attempted, v_rounding_scale)
    else null
  end;

  select asr.standing_code, asr.at_risk
    into v_cumulative_standing, v_cumulative_at_risk
  from public.academic_standing_rules asr
  where asr.grading_policy_id = v_grading_policy_id
    and v_cgpa between asr.minimum_cgpa and asr.maximum_cgpa
  order by asr.display_order
  limit 1;

  v_cumulative_standing := coalesce(v_cumulative_standing, 'UNCLASSIFIED');
  v_cumulative_at_risk := coalesce(v_cumulative_at_risk, false);

  insert into public.cumulative_results (
    institution_id,
    campus_id,
    student_id,
    program_registration_id,
    attempted_credits,
    earned_credits,
    quality_points,
    cgpa,
    standing_code,
    at_risk,
    last_term_id,
    correlation_id
  )
  values (
    v_institution_id,
    v_campus_id,
    p_student_id,
    v_registration_id,
    v_cum_attempted,
    v_cum_earned,
    v_cum_quality,
    v_cgpa,
    v_cumulative_standing,
    v_cumulative_at_risk,
    p_term_id,
    p_correlation_id
  )
  on conflict (student_id, program_registration_id)
  do update set
    attempted_credits = excluded.attempted_credits,
    earned_credits = excluded.earned_credits,
    quality_points = excluded.quality_points,
    cgpa = excluded.cgpa,
    standing_code = excluded.standing_code,
    at_risk = excluded.at_risk,
    last_term_id = excluded.last_term_id,
    correlation_id = excluded.correlation_id,
    calculated_at = timezone('utc', now()),
    updated_at = timezone('utc', now());

  insert into public.academic_standing_history (
    institution_id,
    student_id,
    program_registration_id,
    term_id,
    semester_result_id,
    standing_code,
    at_risk,
    grading_policy_id,
    correlation_id
  )
  values (
    v_institution_id,
    p_student_id,
    v_registration_id,
    p_term_id,
    v_semester_id,
    v_cumulative_standing,
    v_cumulative_at_risk,
    v_grading_policy_id,
    p_correlation_id
  )
  on conflict (semester_result_id)
  do update set
    standing_code = excluded.standing_code,
    at_risk = excluded.at_risk,
    grading_policy_id = excluded.grading_policy_id,
    correlation_id = excluded.correlation_id,
    effective_at = timezone('utc', now());

  return jsonb_build_object(
    'semester_result_id', v_semester_id,
    'gpa', v_gpa,
    'cgpa', v_cgpa,
    'semester_standing_code', v_semester_standing,
    'standing_code', v_cumulative_standing,
    'at_risk', v_cumulative_at_risk,
    'repeat_policy', v_repeat_policy
  );
end;
$function$;

create or replace function public.rpc_decide_marks_batch(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.batch.decide';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}', '')::uuid;
  v_decision public.approval_decision :=
    nullif(p_request#>>'{payload,decision}', '')::public.approval_decision;
  v_reason text := nullif(btrim(coalesce(p_request#>>'{payload,reason}', '')), '');
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_batch public.marks_batches%rowtype;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_result jsonb;
  v_error jsonb;
  v_student_id uuid;
  v_result_count integer := 0;
  v_notification_type text;
begin
  if v_batch_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_MARKS_BATCH_ID_REQUIRED';
  end if;

  if v_decision not in ('approved', 'rejected', 'returned') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DECISION_INVALID';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  select *
    into v_batch
  from public.marks_batches mb
  where mb.id = v_batch_id
  for update;

  if v_batch.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FOUND';
  end if;

  if not app.staff_can_administer_results(
    v_actor_staff_id,
    v_batch.institution_id,
    v_batch.campus_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'marks_batch_id', v_batch_id,
      'decision', v_decision,
      'reason', v_reason
    )
  );

  v_idem := app.begin_idempotency(
    v_batch.institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  if v_batch.batch_status <> 'finalized' then
    if (
      v_decision = 'approved'
      and v_batch.batch_status = 'approved'
    ) or (
      v_decision in ('rejected', 'returned')
      and v_batch.batch_status = 'rejected'
    ) then
      v_result := app.rpc_success(
        v_operation,
        v_correlation_id,
        v_idempotency_key,
        jsonb_build_object(
          'marks_batch_id', v_batch.id,
          'decision', v_decision,
          'status', v_batch.batch_status,
          'already_decided', true
        )
      );
      perform app.complete_idempotency(v_idem_id, v_result);
      return v_result;
    end if;

    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FINALIZED';
  end if;

  insert into public.marks_approval_history (
    institution_id,
    marks_batch_id,
    decision,
    reason,
    decided_by,
    correlation_id
  )
  values (
    v_batch.institution_id,
    v_batch.id,
    v_decision,
    v_reason,
    v_actor_auth_user_id,
    v_correlation_id
  );

  update public.marks_batches
  set
    batch_status = case
      when v_decision = 'approved'
        then 'approved'::public.marks_batch_status
      else 'rejected'::public.marks_batch_status
    end,
    approved_at = case
      when v_decision = 'approved'
        then timezone('utc', now())
      else null
    end,
    approved_by = case
      when v_decision = 'approved'
        then v_actor_auth_user_id
      else null
    end,
    updated_at = timezone('utc', now())
  where id = v_batch.id;

  if v_decision = 'approved' then
    for v_student_id in
      select distinct sm.student_id
      from public.student_marks sm
      where sm.marks_batch_id = v_batch.id
    loop
      perform app.calculate_course_result(
        v_student_id,
        v_batch.offering_id,
        v_correlation_id
      );
      v_result_count := v_result_count + 1;
    end loop;
  end if;

  v_notification_type := case v_decision
    when 'approved' then 'marks.batch.approved'
    when 'returned' then 'marks.batch.returned'
    else 'marks.batch.rejected'
  end;

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
  select
    v_batch.institution_id,
    v_batch.campus_id,
    'email',
    v_notification_type,
    sp.email,
    sp.full_name,
    case v_decision
      when 'approved' then 'Marks batch approved'
      when 'returned' then 'Marks batch returned for correction'
      else 'Marks batch rejected'
    end,
    replace(v_notification_type, '.', '-'),
    jsonb_build_object(
      'marks_batch_id', v_batch.id,
      'decision', v_decision,
      'reason', v_reason,
      'course_offering_id', v_batch.offering_id,
      'section_id', v_batch.section_id
    ),
    v_correlation_id,
    v_batch.id::text || ':' || v_decision::text
  from public.staff_profiles sp
  where sp.id = v_batch.submitted_by_staff_profile_id
    and sp.status = 'active'
  on conflict (
    institution_id,
    channel,
    notification_type,
    idempotency_key
  ) do nothing;

  insert into audit.audit_logs (
    institution_id,
    campus_id,
    actor_auth_user_id,
    actor_staff_profile_id,
    operation,
    entity_type,
    entity_id,
    correlation_id,
    outcome,
    details
  )
  values (
    v_batch.institution_id,
    v_batch.campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'marks_batch',
    v_batch.id,
    v_correlation_id,
    'completed',
    jsonb_build_object(
      'decision', v_decision,
      'reason', v_reason,
      'calculated_student_count', v_result_count
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'marks_batch_id', v_batch.id,
      'course_offering_id', v_batch.offering_id,
      'decision', v_decision,
      'status', case
        when v_decision = 'approved' then 'approved'
        else 'rejected'
      end,
      'calculated_student_count', v_result_count
    )
  );

  perform app.complete_idempotency(v_idem_id, v_result);
  return v_result;
exception when others then
  v_error := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
  if v_idem_id is not null then
    perform app.fail_idempotency(v_idem_id, v_error);
  end if;
  return v_error;
end;
$function$;

create or replace function public.rpc_request_mark_correction(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.correction.request';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_institution_id uuid := nullif(p_request->>'institution_id', '')::uuid;
  v_campus_id uuid := nullif(p_request->>'campus_id', '')::uuid;
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_batch_id uuid := nullif(p_request#>>'{payload,marks_batch_id}', '')::uuid;
  v_student_mark_id uuid := nullif(p_request#>>'{payload,student_mark_id}', '')::uuid;
  v_reason text := btrim(coalesce(p_request#>>'{payload,reason}', ''));
  v_proposed_marks numeric := nullif(p_request#>>'{payload,proposed_marks}', '')::numeric;
  v_current_marks numeric := nullif(p_request#>>'{payload,current_marks}', '')::numeric;
  v_student_number text := upper(btrim(coalesce(
    p_request#>>'{payload,student_number}',
    ''
  )));
  v_assessment_code text := upper(btrim(coalesce(
    p_request#>>'{payload,assessment_code}',
    ''
  )));
  v_evidence_url text := nullif(btrim(coalesce(
    p_request#>>'{payload,evidence_drive_url}',
    ''
  )), '');
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_batch public.marks_batches%rowtype;
  v_mark public.student_marks%rowtype;
  v_assessment public.assessments%rowtype;
  v_actual_student_number text;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_correction_id uuid;
  v_result jsonb;
  v_error jsonb;
begin
  if v_institution_id is null
     or v_campus_id is null
     or v_batch_id is null
     or v_student_mark_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CORRECTION_SCOPE_REQUIRED';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  if length(v_reason) < 10 then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CORRECTION_REASON_REQUIRED';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  select *
    into v_batch
  from public.marks_batches mb
  where mb.id = v_batch_id
    and mb.institution_id = v_institution_id
    and mb.campus_id = v_campus_id;

  if v_batch.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_BATCH_NOT_FOUND';
  end if;

  if v_batch.batch_status not in ('finalized', 'approved') then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_BATCH_STATE_INVALID';
  end if;

  select sm.*
    into v_mark
  from public.student_marks sm
  where sm.id = v_student_mark_id
    and sm.marks_batch_id = v_batch.id
    and sm.institution_id = v_institution_id;

  if v_mark.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_STUDENT_MARK_NOT_FOUND';
  end if;

  select a.*
    into v_assessment
  from public.assessments a
  where a.id = v_mark.assessment_id
    and a.institution_id = v_institution_id;

  select s.student_number
    into v_actual_student_number
  from public.students s
  where s.id = v_mark.student_id;

  if v_student_number <> ''
     and upper(v_actual_student_number) <> v_student_number then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_STUDENT_MISMATCH';
  end if;

  if v_assessment_code <> ''
     and upper(v_assessment.code) <> v_assessment_code then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_ASSESSMENT_MISMATCH';
  end if;

  if v_current_marks is not null
     and v_mark.marks_obtained is distinct from v_current_marks then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_CURRENT_VALUE_CHANGED';
  end if;

  if v_proposed_marks is null
     or v_proposed_marks < 0
     or v_proposed_marks > v_assessment.maximum_marks then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_VALUE_OUT_OF_RANGE';
  end if;

  if not (
    app.staff_can_administer_results(
      v_actor_staff_id,
      v_institution_id,
      v_campus_id
    )
    or app.staff_is_teacher_for_results_section(
      v_actor_staff_id,
      v_institution_id,
      v_campus_id,
      v_batch.section_id
    )
    or v_batch.submitted_by_staff_profile_id = v_actor_staff_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'marks_batch_id', v_batch_id,
      'student_mark_id', v_student_mark_id,
      'proposed_marks', v_proposed_marks,
      'reason', v_reason,
      'evidence_url', v_evidence_url
    )
  );

  v_idem := app.begin_idempotency(
    v_institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  insert into public.mark_correction_requests (
    institution_id,
    campus_id,
    marks_batch_id,
    student_mark_id,
    requested_by_staff_profile_id,
    requested_by_student_id,
    reason,
    proposed_marks,
    correction_status,
    correlation_id,
    idempotency_key,
    evidence_url
  )
  values (
    v_institution_id,
    v_campus_id,
    v_batch.id,
    v_mark.id,
    v_actor_staff_id,
    null,
    v_reason,
    v_proposed_marks,
    'requested',
    v_correlation_id,
    v_idempotency_key,
    v_evidence_url
  )
  on conflict (institution_id, idempotency_key)
  do update set updated_at = public.mark_correction_requests.updated_at
  returning id into v_correction_id;

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
    v_institution_id,
    v_campus_id,
    'email',
    'marks.correction.requested',
    sp.email,
    sp.full_name,
    'Mark correction request awaiting review',
    'marks-correction-requested',
    jsonb_build_object(
      'correction_request_id', v_correction_id,
      'marks_batch_id', v_batch.id,
      'student_mark_id', v_mark.id,
      'student_number', v_actual_student_number,
      'assessment_code', v_assessment.code,
      'proposed_marks', v_proposed_marks,
      'reason', v_reason
    ),
    v_correlation_id,
    v_correction_id::text || ':' || sp.id::text || ':requested'
  from public.staff_profiles sp
  join public.role_assignments ra on ra.staff_profile_id = sp.id
  left join public.campus_assignments ca
    on ca.role_assignment_id = ra.id
   and ca.institution_id = ra.institution_id
  where sp.status = 'active'
    and ra.status = 'active'
    and ra.valid_from <= timezone('utc', now())
    and (ra.valid_to is null or ra.valid_to > timezone('utc', now()))
    and (
      (
        ra.role = 'super_administrator'
        and ra.institution_id is null
      )
      or (
        ra.role = 'registrar_admin'
        and ra.institution_id = v_institution_id
      )
      or (
        ra.role = 'campus_administrator'
        and ra.institution_id = v_institution_id
        and ca.campus_id = v_campus_id
        and ca.status = 'active'
        and ca.valid_from <= timezone('utc', now())
        and (ca.valid_to is null or ca.valid_to > timezone('utc', now()))
      )
    )
  on conflict (
    institution_id,
    channel,
    notification_type,
    idempotency_key
  ) do nothing;

  insert into audit.audit_logs (
    institution_id,
    campus_id,
    actor_auth_user_id,
    actor_staff_profile_id,
    operation,
    entity_type,
    entity_id,
    correlation_id,
    outcome,
    details
  )
  values (
    v_institution_id,
    v_campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'mark_correction_request',
    v_correction_id,
    v_correlation_id,
    'completed',
    jsonb_build_object(
      'marks_batch_id', v_batch.id,
      'student_mark_id', v_mark.id,
      'proposed_marks', v_proposed_marks,
      'evidence_url', v_evidence_url
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'correction_request_id', v_correction_id,
      'status', 'requested',
      'marks_batch_id', v_batch.id,
      'student_mark_id', v_mark.id
    )
  );

  perform app.complete_idempotency(v_idem_id, v_result);
  return v_result;
exception when others then
  v_error := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
  if v_idem_id is not null then
    perform app.fail_idempotency(v_idem_id, v_error);
  end if;
  return v_error;
end;
$function$;

create or replace function public.rpc_request_mark_correction_from_form(
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_institution_id uuid;
  v_campus_id uuid;
  v_email text := lower(btrim(coalesce(
    p_request#>>'{requester,email}',
    ''
  )));
  v_normalized jsonb;
begin
  perform app.require_service();

  select i.id
    into v_institution_id
  from public.institutions i
  where upper(i.code) = upper(btrim(coalesce(
    p_request#>>'{payload,institution_code}',
    ''
  )))
    and i.status = 'active'
  limit 1;

  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_INSTITUTION_CODE_INVALID';
  end if;

  select c.id
    into v_campus_id
  from public.campuses c
  where c.institution_id = v_institution_id
    and upper(c.code) = upper(btrim(coalesce(
      p_request#>>'{payload,campus_code}',
      ''
    )))
    and c.status = 'active'
  limit 1;

  if v_campus_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CAMPUS_CODE_INVALID';
  end if;

  if v_email = '' or position('@' in v_email) <= 1 then
    raise exception using errcode = 'P0001', message = 'AUTH_VERIFIED_EMAIL_REQUIRED';
  end if;

  v_normalized := jsonb_build_object(
    'operation', 'marks.correction.request',
    'correlation_id', v_correlation_id,
    'idempotency_key', p_request->>'idempotency_key',
    'institution_id', v_institution_id,
    'campus_id', v_campus_id,
    'requester', jsonb_build_object(
      'identity_verified', true,
      'verified_email', v_email,
      'verification_source', 'google_forms_collected_email'
    ),
    'submitted_at', coalesce(
      p_request->>'submitted_at',
      timezone('utc', now())::text
    ),
    'source', coalesce(p_request->'source', '{}'::jsonb),
    'payload', coalesce(p_request->'payload', '{}'::jsonb)
  );

  return public.rpc_request_mark_correction(v_normalized);
exception when others then
  return app.exception_rpc_error(
    'marks.correction.request',
    v_correlation_id,
    sqlerrm
  );
end;
$function$;

create or replace function public.rpc_decide_mark_correction(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'marks.correction.decide';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_correction_id uuid := nullif(
    p_request#>>'{payload,correction_request_id}',
    ''
  )::uuid;
  v_decision public.approval_decision :=
    nullif(p_request#>>'{payload,decision}', '')::public.approval_decision;
  v_reason text := nullif(btrim(coalesce(p_request#>>'{payload,reason}', '')), '');
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_correction public.mark_correction_requests%rowtype;
  v_mark public.student_marks%rowtype;
  v_batch public.marks_batches%rowtype;
  v_assessment public.assessments%rowtype;
  v_requester_email text;
  v_requester_name text;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_result jsonb;
  v_error jsonb;
begin
  if v_correction_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_CORRECTION_REQUEST_ID_REQUIRED';
  end if;

  if v_decision not in ('approved', 'rejected') then
    raise exception using errcode = 'P0001', message = 'VALIDATION_DECISION_INVALID';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  select *
    into v_correction
  from public.mark_correction_requests mcr
  where mcr.id = v_correction_id
  for update;

  if v_correction.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_NOT_FOUND';
  end if;

  if not app.staff_can_administer_results(
    v_actor_staff_id,
    v_correction.institution_id,
    v_correction.campus_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'correction_request_id', v_correction.id,
      'decision', v_decision,
      'reason', v_reason
    )
  );

  v_idem := app.begin_idempotency(
    v_correction.institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  if v_correction.correction_status <> 'requested' then
    v_result := app.rpc_success(
      v_operation,
      v_correlation_id,
      v_idempotency_key,
      jsonb_build_object(
        'correction_request_id', v_correction.id,
        'status', v_correction.correction_status,
        'already_decided', true
      )
    );
    perform app.complete_idempotency(v_idem_id, v_result);
    return v_result;
  end if;

  select sm.*
    into v_mark
  from public.student_marks sm
  where sm.id = v_correction.student_mark_id
  for update;

  select mb.*
    into v_batch
  from public.marks_batches mb
  where mb.id = v_correction.marks_batch_id;

  select a.*
    into v_assessment
  from public.assessments a
  where a.id = v_mark.assessment_id;

  if v_mark.id is null
     or v_batch.id is null
     or v_assessment.id is null then
    raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_SOURCE_RECORD_MISSING';
  end if;

  if v_decision = 'approved' then
    if v_correction.proposed_marks is null
       or v_correction.proposed_marks < 0
       or v_correction.proposed_marks > v_assessment.maximum_marks then
      raise exception using errcode = 'P0001', message = 'MARKS_CORRECTION_VALUE_OUT_OF_RANGE';
    end if;

    update public.student_marks
    set
      marks_obtained = v_correction.proposed_marks,
      is_absent = false,
      is_missing = false,
      remarks = concat_ws(
        ' | ',
        nullif(remarks, ''),
        'Corrected under request ' || v_correction.id::text
      ),
      updated_at = timezone('utc', now())
    where id = v_mark.id;

    update public.mark_correction_requests
    set
      correction_status = 'applied',
      decision_reason = v_reason,
      decided_by = v_actor_auth_user_id,
      decided_at = timezone('utc', now()),
      applied_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where id = v_correction.id;

    perform app.calculate_course_result(
      v_mark.student_id,
      v_batch.offering_id,
      v_correlation_id
    );
  else
    update public.mark_correction_requests
    set
      correction_status = 'rejected',
      decision_reason = v_reason,
      decided_by = v_actor_auth_user_id,
      decided_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where id = v_correction.id;
  end if;

  select sp.email, sp.full_name
    into v_requester_email, v_requester_name
  from public.staff_profiles sp
  where sp.id = v_correction.requested_by_staff_profile_id;

  if v_requester_email is not null then
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
    values (
      v_correction.institution_id,
      v_correction.campus_id,
      'email',
      case
        when v_decision = 'approved'
          then 'marks.correction.applied'
        else 'marks.correction.rejected'
      end,
      v_requester_email,
      v_requester_name,
      case
        when v_decision = 'approved'
          then 'Mark correction approved and applied'
        else 'Mark correction request rejected'
      end,
      case
        when v_decision = 'approved'
          then 'marks-correction-applied'
        else 'marks-correction-rejected'
      end,
      jsonb_build_object(
        'correction_request_id', v_correction.id,
        'marks_batch_id', v_batch.id,
        'student_mark_id', v_mark.id,
        'decision', v_decision,
        'reason', v_reason,
        'applied_marks', case
          when v_decision = 'approved'
            then v_correction.proposed_marks
          else null
        end
      ),
      v_correlation_id,
      v_correction.id::text || ':' || v_decision::text
    )
    on conflict (
      institution_id,
      channel,
      notification_type,
      idempotency_key
    ) do nothing;
  end if;

  insert into audit.audit_logs (
    institution_id,
    campus_id,
    actor_auth_user_id,
    actor_staff_profile_id,
    operation,
    entity_type,
    entity_id,
    correlation_id,
    outcome,
    details
  )
  values (
    v_correction.institution_id,
    v_correction.campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'mark_correction_request',
    v_correction.id,
    v_correlation_id,
    'completed',
    jsonb_build_object(
      'decision', v_decision,
      'reason', v_reason,
      'student_mark_id', v_mark.id,
      'proposed_marks', v_correction.proposed_marks
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'correction_request_id', v_correction.id,
      'status', case
        when v_decision = 'approved' then 'applied'
        else 'rejected'
      end,
      'course_offering_id', v_batch.offering_id,
      'result_republication_required', v_decision = 'approved'
    )
  );

  perform app.complete_idempotency(v_idem_id, v_result);
  return v_result;
exception when others then
  v_error := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
  if v_idem_id is not null then
    perform app.fail_idempotency(v_idem_id, v_error);
  end if;
  return v_error;
end;
$function$;

create or replace function public.rpc_publish_results(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'results.publish';
  v_correlation_id uuid := coalesce(
    nullif(p_request->>'correlation_id', '')::uuid,
    gen_random_uuid()
  );
  v_idempotency_key text := btrim(coalesce(p_request->>'idempotency_key', ''));
  v_offering_id uuid := nullif(
    p_request#>>'{payload,course_offering_id}',
    ''
  )::uuid;
  v_force boolean :=
    lower(coalesce(p_request#>>'{payload,force_recalculate}', 'false'))
    in ('true', '1', 'yes');
  v_institution_id uuid;
  v_campus_id uuid;
  v_term_id uuid;
  v_actor_staff_id uuid;
  v_actor_auth_user_id uuid;
  v_actor_email text;
  v_student_id uuid;
  v_result_count integer := 0;
  v_published_count integer := 0;
  v_enrollment_count integer := 0;
  v_records jsonb := '[]'::jsonb;
  v_academic jsonb;
  v_hash text;
  v_idem jsonb;
  v_idem_id uuid;
  v_result jsonb;
  v_error jsonb;
begin
  if v_offering_id is null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_COURSE_OFFERING_ID_REQUIRED';
  end if;

  if v_idempotency_key = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_IDEMPOTENCY_REQUIRED';
  end if;

  select co.institution_id, co.campus_id, co.term_id
    into v_institution_id, v_campus_id, v_term_id
  from public.course_offerings co
  where co.id = v_offering_id;

  if v_institution_id is null then
    raise exception using errcode = 'P0001', message = 'RESULT_OFFERING_NOT_FOUND';
  end if;

  select rsa.staff_profile_id, rsa.auth_user_id, rsa.email
    into v_actor_staff_id, v_actor_auth_user_id, v_actor_email
  from app.results_staff_actor(p_request) rsa;

  if not app.staff_can_administer_results(
    v_actor_staff_id,
    v_institution_id,
    v_campus_id
  ) then
    raise exception using errcode = 'P0001', message = 'AUTH_SCOPE_DENIED';
  end if;

  v_hash := app.request_hash(
    jsonb_build_object(
      'actor_staff_profile_id', v_actor_staff_id,
      'course_offering_id', v_offering_id,
      'force_recalculate', v_force
    )
  );

  v_idem := app.begin_idempotency(
    v_institution_id,
    v_operation,
    v_idempotency_key,
    v_hash,
    v_correlation_id
  );
  v_idem_id := (v_idem->>'record_id')::uuid;

  if v_idem->>'state' in ('completed', 'failed') then
    return v_idem->'existing_result';
  end if;

  if not exists (
    select 1
    from public.marks_batches mb
    where mb.offering_id = v_offering_id
      and mb.batch_status = 'approved'
  ) then
    raise exception using errcode = 'P0001', message = 'RESULT_APPROVED_MARKS_REQUIRED';
  end if;

  select count(*)
    into v_enrollment_count
  from public.enrollments e
  where e.course_offering_id = v_offering_id
    and e.enrollment_status <> 'cancelled';

  select count(*)
    into v_published_count
  from public.course_results cr
  where cr.course_offering_id = v_offering_id
    and cr.result_status = 'published';

  if not v_force
     and v_enrollment_count > 0
     and v_published_count = v_enrollment_count then
    v_result := app.rpc_success(
      v_operation,
      v_correlation_id,
      v_idempotency_key,
      jsonb_build_object(
        'course_offering_id', v_offering_id,
        'published_student_count', v_published_count,
        'already_published', true
      )
    );
    perform app.complete_idempotency(v_idem_id, v_result);
    return v_result;
  end if;

  for v_student_id in
    select distinct e.student_id
    from public.enrollments e
    where e.course_offering_id = v_offering_id
      and e.enrollment_status <> 'cancelled'
  loop
    perform app.calculate_course_result(
      v_student_id,
      v_offering_id,
      v_correlation_id
    );

    update public.course_results
    set
      result_status = 'published',
      approved_at = coalesce(
        approved_at,
        timezone('utc', now())
      ),
      published_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where student_id = v_student_id
      and course_offering_id = v_offering_id;

    v_academic := app.recalculate_academic_record(
      v_student_id,
      v_term_id,
      v_correlation_id
    );

    update public.semester_results
    set
      result_status = 'published',
      published_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where student_id = v_student_id
      and term_id = v_term_id;

    v_records := v_records || jsonb_build_array(
      jsonb_build_object(
        'student_id', v_student_id,
        'academic_record', v_academic
      )
    );
    v_result_count := v_result_count + 1;
  end loop;

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
    v_offering_id::text || ':' || s.id::text || ':results-published'
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

  insert into audit.audit_logs (
    institution_id,
    campus_id,
    actor_auth_user_id,
    actor_staff_profile_id,
    operation,
    entity_type,
    entity_id,
    correlation_id,
    outcome,
    details
  )
  values (
    v_institution_id,
    v_campus_id,
    v_actor_auth_user_id,
    v_actor_staff_id,
    v_operation,
    'course_offering',
    v_offering_id,
    v_correlation_id,
    'completed',
    jsonb_build_object(
      'published_student_count', v_result_count,
      'force_recalculate', v_force
    )
  );

  v_result := app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'course_offering_id', v_offering_id,
      'term_id', v_term_id,
      'published_student_count', v_result_count,
      'already_published', false,
      'records', v_records
    )
  );

  perform app.complete_idempotency(v_idem_id, v_result);
  return v_result;
exception when others then
  v_error := app.exception_rpc_error(v_operation, v_correlation_id, sqlerrm);
  if v_idem_id is not null then
    perform app.fail_idempotency(v_idem_id, v_error);
  end if;
  return v_error;
end;
$function$;

revoke all on function app.results_staff_actor(jsonb)
  from public, anon, authenticated;
revoke all on function app.staff_can_administer_results(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function app.staff_is_teacher_for_results_section(
  uuid, uuid, uuid, uuid
) from public, anon, authenticated;
revoke all on function app.calculate_course_result(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function app.recalculate_academic_record(uuid, uuid, uuid)
  from public, anon, authenticated;

grant execute on function app.results_staff_actor(jsonb) to service_role;
grant execute on function app.staff_can_administer_results(uuid, uuid, uuid)
  to service_role;
grant execute on function app.staff_is_teacher_for_results_section(
  uuid, uuid, uuid, uuid
) to service_role;
grant execute on function app.calculate_course_result(uuid, uuid, uuid)
  to service_role;
grant execute on function app.recalculate_academic_record(uuid, uuid, uuid)
  to service_role;

revoke all on function public.rpc_decide_marks_batch(jsonb)
  from public, anon;
revoke all on function public.rpc_request_mark_correction(jsonb)
  from public, anon;
revoke all on function public.rpc_request_mark_correction_from_form(jsonb)
  from public, anon, authenticated;
revoke all on function public.rpc_decide_mark_correction(jsonb)
  from public, anon;
revoke all on function public.rpc_publish_results(jsonb)
  from public, anon;

grant execute on function public.rpc_decide_marks_batch(jsonb)
  to authenticated, service_role;
grant execute on function public.rpc_request_mark_correction(jsonb)
  to authenticated, service_role;
grant execute on function public.rpc_request_mark_correction_from_form(jsonb)
  to service_role;
grant execute on function public.rpc_decide_mark_correction(jsonb)
  to authenticated, service_role;
grant execute on function public.rpc_publish_results(jsonb)
  to authenticated, service_role;

commit;
