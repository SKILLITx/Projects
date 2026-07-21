-- Phase 2 accelerated completion, migration 5:
-- marks lifecycle, approvals, corrections, course grades, GPA, CGPA and standing.

begin;

create type public.marks_batch_status as enum (
  'draft','finalized','approved','rejected','superseded'
);
create type public.approval_decision as enum ('approved','rejected','returned');
create type public.correction_status as enum (
  'requested','approved','rejected','applied','cancelled'
);
create type public.result_status as enum (
  'calculated','approved','published','superseded'
);

create table public.marks_batches (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  offering_id uuid not null,
  section_id uuid not null,
  submitted_by_staff_profile_id uuid not null references public.staff_profiles(id) on delete restrict,
  version_number integer not null,
  source_submission_id text,
  correlation_id uuid not null,
  idempotency_key text not null,
  request_hash text not null,
  batch_status public.marks_batch_status not null default 'draft',
  validation_summary jsonb not null default '{}'::jsonb,
  finalized_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint marks_batches_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint marks_batches_offering_scope_fk foreign key (institution_id, offering_id)
    references public.course_offerings(institution_id, id) on delete restrict,
  constraint marks_batches_section_scope_fk foreign key (institution_id, section_id)
    references public.sections(institution_id, id) on delete restrict,
  constraint marks_batches_version_chk check (version_number > 0),
  constraint marks_batches_idem_chk check (btrim(idempotency_key) <> ''),
  constraint marks_batches_summary_chk check (jsonb_typeof(validation_summary) = 'object'),
  constraint marks_batches_finalize_chk check (
    (batch_status in ('finalized','approved','rejected','superseded') and finalized_at is not null)
    or batch_status = 'draft'
  ),
  constraint marks_batches_approve_chk check (
    (batch_status = 'approved' and approved_at is not null)
    or batch_status <> 'approved'
  ),
  constraint marks_batches_scope_uq unique (institution_id, id)
);
create unique index marks_batches_idem_uq
  on public.marks_batches (institution_id, idempotency_key);
create unique index marks_batches_section_version_uq
  on public.marks_batches (section_id, version_number);
create index marks_batches_status_idx
  on public.marks_batches (institution_id, campus_id, section_id, batch_status, created_at);
create trigger marks_batches_set_updated_at before update on public.marks_batches
for each row execute function app.set_updated_at();

create table public.marks_batch_files (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  marks_batch_id uuid not null,
  file_name text not null,
  mime_type text,
  storage_provider text,
  storage_object_id text,
  checksum_sha256 text,
  row_count integer,
  created_at timestamptz not null default timezone('utc', now()),
  constraint marks_batch_files_batch_scope_fk foreign key (institution_id, marks_batch_id)
    references public.marks_batches(institution_id, id) on delete cascade,
  constraint marks_batch_files_name_chk check (btrim(file_name) <> ''),
  constraint marks_batch_files_checksum_chk check (
    checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'
  ),
  constraint marks_batch_files_rows_chk check (row_count is null or row_count >= 0)
);
create index marks_batch_files_batch_idx on public.marks_batch_files (marks_batch_id);

create table public.student_marks (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  marks_batch_id uuid not null,
  assessment_id uuid not null,
  student_id uuid not null,
  enrollment_id uuid not null,
  marks_obtained numeric(8,2),
  is_absent boolean not null default false,
  is_missing boolean not null default false,
  remarks text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint student_marks_batch_scope_fk foreign key (institution_id, marks_batch_id)
    references public.marks_batches(institution_id, id) on delete cascade,
  constraint student_marks_assessment_scope_fk foreign key (institution_id, assessment_id)
    references public.assessments(institution_id, id) on delete restrict,
  constraint student_marks_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint student_marks_enrollment_scope_fk foreign key (institution_id, enrollment_id)
    references public.enrollments(institution_id, id) on delete restrict,
  constraint student_marks_value_chk check (
    marks_obtained is null or marks_obtained >= 0
  ),
  constraint student_marks_state_chk check (
    not (is_absent and is_missing)
  ),
  constraint student_marks_value_state_chk check (
    (marks_obtained is not null and not is_absent and not is_missing)
    or (marks_obtained is null and (is_absent or is_missing))
  ),
  constraint student_marks_scope_uq unique (institution_id, id)
);
create unique index student_marks_batch_assessment_student_uq
  on public.student_marks (marks_batch_id, assessment_id, student_id);
create index student_marks_student_idx
  on public.student_marks (institution_id, student_id, assessment_id);
create trigger student_marks_set_updated_at before update on public.student_marks
for each row execute function app.set_updated_at();

create or replace function app.validate_student_mark()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_max numeric(8,2);
  v_assessment_section uuid;
  v_batch_section uuid;
  v_enrollment_student uuid;
  v_enrollment_section uuid;
begin
  select a.maximum_marks, a.section_id
    into v_max, v_assessment_section
  from public.assessments a
  where a.id = new.assessment_id
    and a.institution_id = new.institution_id;

  select mb.section_id
    into v_batch_section
  from public.marks_batches mb
  where mb.id = new.marks_batch_id
    and mb.institution_id = new.institution_id;

  select e.student_id, e.section_id
    into v_enrollment_student, v_enrollment_section
  from public.enrollments e
  where e.id = new.enrollment_id
    and e.institution_id = new.institution_id;

  if v_max is null or v_batch_section is null or v_enrollment_student is null then
    raise exception using errcode = '23503', message = 'Invalid marks relationship.';
  end if;

  if new.marks_obtained is not null and new.marks_obtained > v_max then
    raise exception using errcode = '23514', message = 'Marks exceed the assessment maximum.';
  end if;

  if v_enrollment_student <> new.student_id then
    raise exception using errcode = '23514', message = 'Enrollment does not belong to the student.';
  end if;

  if v_enrollment_section <> v_batch_section then
    raise exception using errcode = '23514', message = 'Enrollment is not in the marks batch section.';
  end if;

  if v_assessment_section is not null and v_assessment_section <> v_batch_section then
    raise exception using errcode = '23514', message = 'Assessment is not assigned to the marks batch section.';
  end if;

  return new;
end;
$function$;
revoke all on function app.validate_student_mark() from public, anon, authenticated;

create trigger student_marks_validate
before insert or update on public.student_marks
for each row execute function app.validate_student_mark();

create table public.marks_validation_issues (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  marks_batch_id uuid not null,
  issue_code text not null,
  severity text not null,
  student_number text,
  assessment_code text,
  row_number integer,
  message text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint marks_validation_batch_scope_fk foreign key (institution_id, marks_batch_id)
    references public.marks_batches(institution_id, id) on delete cascade,
  constraint marks_validation_code_chk check (issue_code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  constraint marks_validation_severity_chk check (severity in ('warning','error')),
  constraint marks_validation_row_chk check (row_number is null or row_number > 0),
  constraint marks_validation_message_chk check (btrim(message) <> ''),
  constraint marks_validation_details_chk check (jsonb_typeof(details) = 'object')
);
create index marks_validation_batch_idx
  on public.marks_validation_issues (marks_batch_id, severity, issue_code);

create table public.marks_approval_history (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  marks_batch_id uuid not null,
  decision public.approval_decision not null,
  reason text,
  decided_by uuid not null references auth.users(id) on delete restrict,
  decided_at timestamptz not null default timezone('utc', now()),
  correlation_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint marks_approval_batch_scope_fk foreign key (institution_id, marks_batch_id)
    references public.marks_batches(institution_id, id) on delete cascade
);
create index marks_approval_batch_idx
  on public.marks_approval_history (marks_batch_id, decided_at);

create table public.mark_correction_requests (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  marks_batch_id uuid not null,
  student_mark_id uuid,
  requested_by_staff_profile_id uuid references public.staff_profiles(id) on delete set null,
  requested_by_student_id uuid,
  reason text not null,
  proposed_marks numeric(8,2),
  correction_status public.correction_status not null default 'requested',
  correlation_id uuid not null,
  idempotency_key text not null,
  decision_reason text,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mark_corrections_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint mark_corrections_batch_scope_fk foreign key (institution_id, marks_batch_id)
    references public.marks_batches(institution_id, id) on delete restrict,
  constraint mark_corrections_mark_scope_fk foreign key (institution_id, student_mark_id)
    references public.student_marks(institution_id, id) on delete set null,
  constraint mark_corrections_student_scope_fk foreign key (institution_id, requested_by_student_id)
    references public.students(institution_id, id) on delete set null,
  constraint mark_corrections_reason_chk check (btrim(reason) <> ''),
  constraint mark_corrections_marks_chk check (proposed_marks is null or proposed_marks >= 0),
  constraint mark_corrections_idem_chk check (btrim(idempotency_key) <> ''),
  constraint mark_corrections_decision_chk check (
    (correction_status in ('approved','rejected','applied') and decided_at is not null)
    or correction_status in ('requested','cancelled')
  ),
  constraint mark_corrections_applied_chk check (
    (correction_status = 'applied' and applied_at is not null)
    or correction_status <> 'applied'
  ),
  constraint mark_corrections_scope_uq unique (institution_id, id)
);
create unique index mark_corrections_idem_uq
  on public.mark_correction_requests (institution_id, idempotency_key);
create index mark_corrections_status_idx
  on public.mark_correction_requests (institution_id, campus_id, correction_status, created_at);
create trigger mark_correction_requests_set_updated_at before update on public.mark_correction_requests
for each row execute function app.set_updated_at();

create table public.course_results (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  student_id uuid not null,
  term_id uuid not null,
  course_offering_id uuid not null,
  enrollment_id uuid not null,
  grading_policy_id uuid not null,
  total_score numeric(7,3),
  letter_grade text,
  grade_point numeric(5,2),
  credit_hours numeric(5,2) not null,
  outcome_code text not null,
  result_status public.result_status not null default 'calculated',
  calculation_version integer not null default 1,
  correlation_id uuid not null,
  calculated_at timestamptz not null default timezone('utc', now()),
  approved_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint course_results_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint course_results_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint course_results_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint course_results_offering_scope_fk foreign key (institution_id, course_offering_id)
    references public.course_offerings(institution_id, id) on delete restrict,
  constraint course_results_enrollment_scope_fk foreign key (institution_id, enrollment_id)
    references public.enrollments(institution_id, id) on delete restrict,
  constraint course_results_policy_scope_fk foreign key (institution_id, grading_policy_id)
    references public.grading_policies(institution_id, id) on delete restrict,
  constraint course_results_score_chk check (total_score is null or total_score between 0 and 100),
  constraint course_results_point_chk check (grade_point is null or grade_point >= 0),
  constraint course_results_credit_chk check (credit_hours >= 0),
  constraint course_results_outcome_chk check (
    outcome_code in ('pass','fail','incomplete','withdrawn','audit')
  ),
  constraint course_results_version_chk check (calculation_version > 0),
  constraint course_results_scope_uq unique (institution_id, id)
);
create unique index course_results_student_offering_uq
  on public.course_results (student_id, course_offering_id);
create index course_results_student_term_idx
  on public.course_results (institution_id, student_id, term_id, result_status);
create trigger course_results_set_updated_at before update on public.course_results
for each row execute function app.set_updated_at();

alter table public.prerequisite_evidence
  add constraint prerequisite_evidence_result_scope_fk
  foreign key (institution_id, supporting_course_result_id)
  references public.course_results(institution_id, id) on delete set null;

create table public.semester_results (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  student_id uuid not null,
  program_registration_id uuid not null,
  term_id uuid not null,
  attempted_credits numeric(8,2) not null default 0,
  earned_credits numeric(8,2) not null default 0,
  quality_points numeric(10,3) not null default 0,
  gpa numeric(5,3),
  standing_code text,
  at_risk boolean not null default false,
  result_status public.result_status not null default 'calculated',
  correlation_id uuid not null,
  calculated_at timestamptz not null default timezone('utc', now()),
  published_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint semester_results_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint semester_results_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint semester_results_registration_scope_fk foreign key (institution_id, program_registration_id)
    references public.student_program_registrations(institution_id, id) on delete restrict,
  constraint semester_results_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint semester_results_nonnegative_chk check (
    attempted_credits >= 0 and earned_credits >= 0 and quality_points >= 0
  ),
  constraint semester_results_gpa_chk check (gpa is null or gpa >= 0),
  constraint semester_results_scope_uq unique (institution_id, id)
);
create unique index semester_results_student_term_uq
  on public.semester_results (student_id, term_id);
create trigger semester_results_set_updated_at before update on public.semester_results
for each row execute function app.set_updated_at();

create table public.cumulative_results (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  student_id uuid not null,
  program_registration_id uuid not null,
  attempted_credits numeric(10,2) not null default 0,
  earned_credits numeric(10,2) not null default 0,
  quality_points numeric(12,3) not null default 0,
  cgpa numeric(5,3),
  standing_code text,
  at_risk boolean not null default false,
  last_term_id uuid,
  correlation_id uuid not null,
  calculated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint cumulative_results_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint cumulative_results_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint cumulative_results_registration_scope_fk foreign key (institution_id, program_registration_id)
    references public.student_program_registrations(institution_id, id) on delete restrict,
  constraint cumulative_results_last_term_scope_fk foreign key (institution_id, last_term_id)
    references public.terms(institution_id, id) on delete set null,
  constraint cumulative_results_nonnegative_chk check (
    attempted_credits >= 0 and earned_credits >= 0 and quality_points >= 0
  ),
  constraint cumulative_results_cgpa_chk check (cgpa is null or cgpa >= 0),
  constraint cumulative_results_scope_uq unique (institution_id, id)
);
create unique index cumulative_results_student_registration_uq
  on public.cumulative_results (student_id, program_registration_id);
create trigger cumulative_results_set_updated_at before update on public.cumulative_results
for each row execute function app.set_updated_at();

create table public.academic_standing_history (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  student_id uuid not null,
  program_registration_id uuid not null,
  term_id uuid not null,
  semester_result_id uuid not null,
  standing_code text not null,
  at_risk boolean not null,
  grading_policy_id uuid not null,
  effective_at timestamptz not null default timezone('utc', now()),
  correlation_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint standing_history_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint standing_history_registration_scope_fk foreign key (institution_id, program_registration_id)
    references public.student_program_registrations(institution_id, id) on delete restrict,
  constraint standing_history_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint standing_history_semester_scope_fk foreign key (institution_id, semester_result_id)
    references public.semester_results(institution_id, id) on delete cascade,
  constraint standing_history_policy_scope_fk foreign key (institution_id, grading_policy_id)
    references public.grading_policies(institution_id, id) on delete restrict
);
create unique index standing_history_semester_uq on public.academic_standing_history (semester_result_id);

create or replace function app.resolve_grade(
  p_grading_policy_id uuid,
  p_total_score numeric
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (
      select jsonb_build_object(
        'letter_grade', gs.letter_grade,
        'grade_point', gs.grade_point,
        'outcome_code', gs.outcome_code
      )
      from public.grade_scales gs
      where gs.grading_policy_id = p_grading_policy_id
        and p_total_score between gs.minimum_score and gs.maximum_score
      order by gs.display_order
      limit 1
    ),
    jsonb_build_object(
      'letter_grade', null,
      'grade_point', null,
      'outcome_code', 'incomplete'
    )
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
  v_credit_hours numeric(5,2);
  v_total numeric(7,3);
  v_grade jsonb;
  v_result_id uuid;
begin
  select co.institution_id, co.campus_id, co.term_id, co.grading_policy_id,
         e.id, c.credit_hours
    into v_institution_id, v_campus_id, v_term_id, v_grading_policy_id,
         v_enrollment_id, v_credit_hours
  from public.course_offerings co
  join public.courses c on c.id = co.course_id
  join public.enrollments e
    on e.course_offering_id = co.id
   and e.student_id = p_student_id
  where co.id = p_course_offering_id
    and e.enrollment_status not in ('withdrawn','cancelled')
  limit 1;

  if v_enrollment_id is null then
    raise exception using errcode = 'P0001', message = 'RESULT_ENROLLMENT_NOT_FOUND';
  end if;

  with latest_marks as (
    select distinct on (sm.assessment_id)
      sm.assessment_id,
      sm.marks_obtained,
      sm.is_absent,
      sm.is_missing
    from public.student_marks sm
    join public.marks_batches mb on mb.id = sm.marks_batch_id
    join public.assessments a on a.id = sm.assessment_id
    where sm.student_id = p_student_id
      and mb.offering_id = p_course_offering_id
      and mb.batch_status = 'approved'
      and a.status = 'active'
    order by sm.assessment_id, mb.version_number desc, sm.updated_at desc
  )
  select round(
    coalesce(
      sum(
        case
          when lm.marks_obtained is null then 0
          else (lm.marks_obtained / nullif(a.maximum_marks, 0)) * ac.weight_percent
        end
      ),
      0
    ),
    3
  )
    into v_total
  from public.assessments a
  join public.assessment_components ac on ac.id = a.component_id
  left join latest_marks lm on lm.assessment_id = a.id
  where a.offering_id = p_course_offering_id
    and (a.section_id is null or a.section_id = (
      select e2.section_id from public.enrollments e2 where e2.id = v_enrollment_id
    ))
    and a.status = 'active';

  v_grade := app.resolve_grade(v_grading_policy_id, v_total);

  insert into public.course_results (
    institution_id, campus_id, student_id, term_id, course_offering_id,
    enrollment_id, grading_policy_id, total_score, letter_grade, grade_point,
    credit_hours, outcome_code, result_status, calculation_version,
    correlation_id
  )
  values (
    v_institution_id, v_campus_id, p_student_id, v_term_id, p_course_offering_id,
    v_enrollment_id, v_grading_policy_id, v_total,
    v_grade->>'letter_grade', nullif(v_grade->>'grade_point','')::numeric,
    v_credit_hours, v_grade->>'outcome_code', 'calculated', 1,
    p_correlation_id
  )
  on conflict (student_id, course_offering_id)
  do update set
    total_score = excluded.total_score,
    letter_grade = excluded.letter_grade,
    grade_point = excluded.grade_point,
    credit_hours = excluded.credit_hours,
    outcome_code = excluded.outcome_code,
    result_status = 'calculated',
    calculation_version = public.course_results.calculation_version + 1,
    correlation_id = excluded.correlation_id,
    calculated_at = timezone('utc', now()),
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
  v_attempted numeric(8,2);
  v_earned numeric(8,2);
  v_quality numeric(10,3);
  v_gpa numeric(5,3);
  v_standing_code text;
  v_at_risk boolean;
  v_semester_id uuid;
  v_cum_attempted numeric(10,2);
  v_cum_earned numeric(10,2);
  v_cum_quality numeric(12,3);
  v_cgpa numeric(5,3);
begin
  select s.institution_id, s.campus_id, spr.id
    into v_institution_id, v_campus_id, v_registration_id
  from public.students s
  join public.student_program_registrations spr
    on spr.student_id = s.id
   and spr.registration_status = 'active'
  where s.id = p_student_id
  order by spr.created_at desc
  limit 1;

  if v_registration_id is null then
    raise exception using errcode = 'P0001', message = 'RESULT_ACTIVE_PROGRAM_NOT_FOUND';
  end if;

  select
    coalesce(sum(cr.credit_hours) filter (where cr.outcome_code not in ('withdrawn','audit')), 0),
    coalesce(sum(cr.credit_hours) filter (where cr.outcome_code = 'pass'), 0),
    coalesce(sum(cr.credit_hours * coalesce(cr.grade_point,0))
      filter (where cr.outcome_code not in ('withdrawn','audit','incomplete')), 0)
  into v_attempted, v_earned, v_quality
  from public.course_results cr
  where cr.student_id = p_student_id
    and cr.term_id = p_term_id
    and cr.result_status in ('calculated','approved','published');

  select cr.grading_policy_id
    into v_grading_policy_id
  from public.course_results cr
  where cr.student_id = p_student_id
    and cr.term_id = p_term_id
    and cr.result_status in ('calculated','approved','published')
  order by cr.calculated_at desc, cr.id
  limit 1;

  v_gpa := case when v_attempted > 0 then round(v_quality / v_attempted, 3) else null end;

  select asr.standing_code, asr.at_risk
    into v_standing_code, v_at_risk
  from public.academic_standing_rules asr
  where asr.grading_policy_id = v_grading_policy_id
    and v_gpa between asr.minimum_cgpa and asr.maximum_cgpa
  order by asr.display_order
  limit 1;

  v_standing_code := coalesce(v_standing_code, 'UNCLASSIFIED');
  v_at_risk := coalesce(v_at_risk, false);

  insert into public.semester_results (
    institution_id, campus_id, student_id, program_registration_id, term_id,
    attempted_credits, earned_credits, quality_points, gpa, standing_code,
    at_risk, result_status, correlation_id
  )
  values (
    v_institution_id, v_campus_id, p_student_id, v_registration_id, p_term_id,
    v_attempted, v_earned, v_quality, v_gpa, v_standing_code,
    v_at_risk, 'calculated', p_correlation_id
  )
  on conflict (student_id, term_id)
  do update set
    attempted_credits = excluded.attempted_credits,
    earned_credits = excluded.earned_credits,
    quality_points = excluded.quality_points,
    gpa = excluded.gpa,
    standing_code = excluded.standing_code,
    at_risk = excluded.at_risk,
    result_status = 'calculated',
    correlation_id = excluded.correlation_id,
    calculated_at = timezone('utc', now()),
    updated_at = timezone('utc', now())
  returning id into v_semester_id;

  select
    coalesce(sum(sr.attempted_credits),0),
    coalesce(sum(sr.earned_credits),0),
    coalesce(sum(sr.quality_points),0)
  into v_cum_attempted, v_cum_earned, v_cum_quality
  from public.semester_results sr
  where sr.student_id = p_student_id;

  v_cgpa := case when v_cum_attempted > 0 then round(v_cum_quality / v_cum_attempted, 3) else null end;

  select asr.standing_code, asr.at_risk
    into v_standing_code, v_at_risk
  from public.academic_standing_rules asr
  where asr.grading_policy_id = v_grading_policy_id
    and v_cgpa between asr.minimum_cgpa and asr.maximum_cgpa
  order by asr.display_order
  limit 1;

  v_standing_code := coalesce(v_standing_code, 'UNCLASSIFIED');
  v_at_risk := coalesce(v_at_risk, false);

  insert into public.cumulative_results (
    institution_id, campus_id, student_id, program_registration_id,
    attempted_credits, earned_credits, quality_points, cgpa,
    standing_code, at_risk, last_term_id, correlation_id
  )
  values (
    v_institution_id, v_campus_id, p_student_id, v_registration_id,
    v_cum_attempted, v_cum_earned, v_cum_quality, v_cgpa,
    v_standing_code, v_at_risk, p_term_id, p_correlation_id
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
    institution_id, student_id, program_registration_id, term_id,
    semester_result_id, standing_code, at_risk, grading_policy_id,
    correlation_id
  )
  values (
    v_institution_id, p_student_id, v_registration_id, p_term_id,
    v_semester_id, v_standing_code, v_at_risk, v_grading_policy_id,
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
    'standing_code', v_standing_code,
    'at_risk', v_at_risk
  );
end;
$function$;

revoke all on function app.resolve_grade(uuid, numeric) from public, anon, authenticated;
revoke all on function app.calculate_course_result(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function app.recalculate_academic_record(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function app.resolve_grade(uuid, numeric) to authenticated, service_role;
grant execute on function app.calculate_course_result(uuid, uuid, uuid) to service_role;
grant execute on function app.recalculate_academic_record(uuid, uuid, uuid) to service_role;

do $do$
declare
  t text;
begin
  foreach t in array array[
    'marks_batches','marks_batch_files','student_marks','marks_validation_issues',
    'marks_approval_history','mark_correction_requests','course_results',
    'semester_results','cumulative_results','academic_standing_history'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to service_role', t);
    execute format('grant select on table public.%I to authenticated', t);
  end loop;
end
$do$;

create policy marks_batches_select_scoped on public.marks_batches
for select to authenticated using (
  submitted_by_staff_profile_id = (select app.current_staff_profile_id())
  or (select app.is_teacher_for_section(section_id))
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy marks_batch_files_select_scoped on public.marks_batch_files
for select to authenticated using (
  exists (
    select 1 from public.marks_batches mb
    where mb.id = marks_batch_files.marks_batch_id
      and (
        mb.submitted_by_staff_profile_id = (select app.current_staff_profile_id())
        or (select app.is_teacher_for_section(mb.section_id))
        or (select app.can_access_campus(mb.institution_id, mb.campus_id))
      )
  )
);
create policy student_marks_select_scoped on public.student_marks
for select to authenticated using (
  (select app.student_owns(student_id))
  or exists (
    select 1 from public.marks_batches mb
    where mb.id = student_marks.marks_batch_id
      and (
        (select app.is_teacher_for_section(mb.section_id))
        or (select app.can_access_campus(mb.institution_id, mb.campus_id))
      )
  )
);
create policy marks_validation_issues_select_scoped on public.marks_validation_issues
for select to authenticated using (
  exists (
    select 1 from public.marks_batches mb
    where mb.id = marks_validation_issues.marks_batch_id
      and (
        mb.submitted_by_staff_profile_id = (select app.current_staff_profile_id())
        or (select app.is_teacher_for_section(mb.section_id))
        or (select app.can_access_campus(mb.institution_id, mb.campus_id))
      )
  )
);
create policy marks_approval_history_select_scoped on public.marks_approval_history
for select to authenticated using (
  exists (
    select 1 from public.marks_batches mb
    where mb.id = marks_approval_history.marks_batch_id
      and (
        (select app.is_teacher_for_section(mb.section_id))
        or (select app.can_access_campus(mb.institution_id, mb.campus_id))
      )
  )
);
create policy mark_corrections_select_scoped on public.mark_correction_requests
for select to authenticated using (
  (requested_by_student_id is not null and (select app.student_owns(requested_by_student_id)))
  or requested_by_staff_profile_id = (select app.current_staff_profile_id())
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy course_results_select_scoped on public.course_results
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
  or exists (
    select 1 from public.enrollments e
    where e.id = course_results.enrollment_id
      and (select app.is_teacher_for_section(e.section_id))
  )
);
create policy semester_results_select_scoped on public.semester_results
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy cumulative_results_select_scoped on public.cumulative_results
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy academic_standing_history_select_scoped on public.academic_standing_history
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_administer_institution(institution_id))
);

commit;
