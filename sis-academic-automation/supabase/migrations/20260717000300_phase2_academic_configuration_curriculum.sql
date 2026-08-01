-- Phase 2 accelerated completion, migration 3:
-- academic configuration, curriculum, offerings, scheduling and assessments.

begin;


-- Complete the composite tenant key needed by later enrollment foreign keys.
alter table public.enrollment_periods
  add constraint enrollment_periods_institution_id_id_uq
  unique (institution_id, id);


create type public.course_kind as enum ('course', 'subject');
create type public.offering_status as enum ('planned', 'open', 'closed', 'completed', 'cancelled');
create type public.section_status as enum ('planned', 'open', 'closed', 'completed', 'cancelled');
create type public.full_section_behavior as enum ('reject', 'waitlist', 'manual_review');

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  code text not null,
  name text not null,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint departments_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint departments_name_chk check (btrim(name) <> ''),
  constraint departments_scope_uq unique (institution_id, id)
);
create unique index departments_code_uq on public.departments (institution_id, upper(code));
create trigger departments_set_updated_at before update on public.departments
for each row execute function app.set_updated_at();

create table public.programs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  department_id uuid,
  code text not null,
  name text not null,
  academic_model public.academic_model not null,
  level_name text not null,
  duration_terms integer,
  default_maximum_load numeric(6,2),
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint programs_department_scope_fk foreign key (institution_id, department_id)
    references public.departments(institution_id, id) on delete set null,
  constraint programs_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint programs_name_chk check (btrim(name) <> ''),
  constraint programs_level_chk check (btrim(level_name) <> ''),
  constraint programs_duration_chk check (duration_terms is null or duration_terms > 0),
  constraint programs_load_chk check (default_maximum_load is null or default_maximum_load > 0),
  constraint programs_scope_uq unique (institution_id, id)
);
create unique index programs_code_uq on public.programs (institution_id, upper(code));
create index programs_department_idx on public.programs (institution_id, department_id, status);
create trigger programs_set_updated_at before update on public.programs
for each row execute function app.set_updated_at();

create table public.grading_policies (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  program_id uuid,
  name text not null,
  version integer not null,
  effective_from date not null,
  effective_to date,
  pass_mark numeric(6,2) not null default 50,
  calculation_method jsonb not null default '{"rounding_scale":2}'::jsonb,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint grading_policies_program_scope_fk foreign key (institution_id, program_id)
    references public.programs(institution_id, id) on delete cascade,
  constraint grading_policies_name_chk check (btrim(name) <> ''),
  constraint grading_policies_version_chk check (version > 0),
  constraint grading_policies_date_chk check (effective_to is null or effective_to >= effective_from),
  constraint grading_policies_pass_chk check (pass_mark between 0 and 100),
  constraint grading_policies_method_chk check (jsonb_typeof(calculation_method) = 'object'),
  constraint grading_policies_scope_uq unique (institution_id, id)
);
create unique index grading_policies_version_uq
  on public.grading_policies (institution_id, coalesce(program_id, '00000000-0000-0000-0000-000000000000'::uuid), version);
create trigger grading_policies_set_updated_at before update on public.grading_policies
for each row execute function app.set_updated_at();

create table public.grade_scales (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  grading_policy_id uuid not null,
  minimum_score numeric(6,2) not null,
  maximum_score numeric(6,2) not null,
  letter_grade text not null,
  grade_point numeric(5,2),
  outcome_code text not null default 'pass',
  display_order integer not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint grade_scales_policy_scope_fk foreign key (institution_id, grading_policy_id)
    references public.grading_policies(institution_id, id) on delete cascade,
  constraint grade_scales_range_chk check (
    minimum_score >= 0 and maximum_score <= 100 and maximum_score >= minimum_score
  ),
  constraint grade_scales_letter_chk check (btrim(letter_grade) <> ''),
  constraint grade_scales_point_chk check (grade_point is null or grade_point between 0 and 10),
  constraint grade_scales_outcome_chk check (outcome_code in ('pass','fail','incomplete','withdrawn','audit')),
  constraint grade_scales_order_chk check (display_order > 0),
  constraint grade_scales_scope_uq unique (institution_id, id)
);
create unique index grade_scales_order_uq on public.grade_scales (grading_policy_id, display_order);
create index grade_scales_lookup_idx on public.grade_scales (grading_policy_id, minimum_score, maximum_score);
create trigger grade_scales_set_updated_at before update on public.grade_scales
for each row execute function app.set_updated_at();

create table public.academic_standing_rules (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  grading_policy_id uuid not null,
  minimum_cgpa numeric(5,2) not null,
  maximum_cgpa numeric(5,2) not null,
  standing_code text not null,
  standing_label text not null,
  at_risk boolean not null default false,
  display_order integer not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint academic_standing_policy_scope_fk foreign key (institution_id, grading_policy_id)
    references public.grading_policies(institution_id, id) on delete cascade,
  constraint academic_standing_range_chk check (
    minimum_cgpa >= 0 and maximum_cgpa >= minimum_cgpa and maximum_cgpa <= 10
  ),
  constraint academic_standing_code_chk check (standing_code ~ '^[A-Z][A-Z0-9_]{1,31}$'),
  constraint academic_standing_label_chk check (btrim(standing_label) <> ''),
  constraint academic_standing_order_chk check (display_order > 0),
  constraint academic_standing_scope_uq unique (institution_id, id)
);
create unique index academic_standing_order_uq on public.academic_standing_rules (grading_policy_id, display_order);
create trigger academic_standing_rules_set_updated_at before update on public.academic_standing_rules
for each row execute function app.set_updated_at();

create table public.enrollment_policies (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  program_id uuid,
  version integer not null,
  effective_from date not null,
  effective_to date,
  maximum_load numeric(6,2) not null,
  full_section_behavior public.full_section_behavior not null default 'waitlist',
  allow_section_fallback boolean not null default true,
  requires_verified_documents boolean not null default true,
  allow_waitlist_promotion boolean not null default true,
  policy jsonb not null default '{}'::jsonb,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint enrollment_policies_program_scope_fk foreign key (institution_id, program_id)
    references public.programs(institution_id, id) on delete cascade,
  constraint enrollment_policies_version_chk check (version > 0),
  constraint enrollment_policies_date_chk check (effective_to is null or effective_to >= effective_from),
  constraint enrollment_policies_load_chk check (maximum_load > 0),
  constraint enrollment_policies_json_chk check (jsonb_typeof(policy) = 'object'),
  constraint enrollment_policies_scope_uq unique (institution_id, id)
);
create unique index enrollment_policies_version_uq
  on public.enrollment_policies (institution_id, coalesce(program_id, '00000000-0000-0000-0000-000000000000'::uuid), version);
create trigger enrollment_policies_set_updated_at before update on public.enrollment_policies
for each row execute function app.set_updated_at();

create table public.transcript_settings (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  version integer not null,
  effective_from date not null,
  effective_to date,
  reference_prefix text not null default 'TR',
  disclaimer text,
  template_configuration jsonb not null default '{}'::jsonb,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint transcript_settings_version_chk check (version > 0),
  constraint transcript_settings_date_chk check (effective_to is null or effective_to >= effective_from),
  constraint transcript_settings_prefix_chk check (reference_prefix ~ '^[A-Z0-9_-]{1,16}$'),
  constraint transcript_settings_json_chk check (jsonb_typeof(template_configuration) = 'object'),
  constraint transcript_settings_scope_uq unique (institution_id, id)
);
create unique index transcript_settings_version_uq on public.transcript_settings (institution_id, version);
create trigger transcript_settings_set_updated_at before update on public.transcript_settings
for each row execute function app.set_updated_at();

create table public.notification_settings (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  version integer not null,
  effective_from date not null,
  effective_to date,
  sender_name text,
  reply_to_email text,
  configuration jsonb not null default '{}'::jsonb,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint notification_settings_version_chk check (version > 0),
  constraint notification_settings_date_chk check (effective_to is null or effective_to >= effective_from),
  constraint notification_settings_json_chk check (jsonb_typeof(configuration) = 'object'),
  constraint notification_settings_scope_uq unique (institution_id, id)
);
create unique index notification_settings_version_uq on public.notification_settings (institution_id, version);
create trigger notification_settings_set_updated_at before update on public.notification_settings
for each row execute function app.set_updated_at();

create table public.hec_report_settings (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  version integer not null,
  effective_from date not null,
  effective_to date,
  template_label text not null default 'Demonstration HEC Enrollment Format',
  configuration jsonb not null default '{}'::jsonb,
  status public.record_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint hec_report_settings_version_chk check (version > 0),
  constraint hec_report_settings_date_chk check (effective_to is null or effective_to >= effective_from),
  constraint hec_report_settings_label_chk check (btrim(template_label) <> ''),
  constraint hec_report_settings_json_chk check (jsonb_typeof(configuration) = 'object'),
  constraint hec_report_settings_scope_uq unique (institution_id, id)
);
create unique index hec_report_settings_version_uq on public.hec_report_settings (institution_id, version);
create trigger hec_report_settings_set_updated_at before update on public.hec_report_settings
for each row execute function app.set_updated_at();

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  code text not null,
  name text not null,
  capacity integer,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint rooms_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint rooms_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint rooms_name_chk check (btrim(name) <> ''),
  constraint rooms_capacity_chk check (capacity is null or capacity >= 0),
  constraint rooms_scope_uq unique (institution_id, id)
);
create unique index rooms_code_uq on public.rooms (institution_id, campus_id, upper(code));
create trigger rooms_set_updated_at before update on public.rooms
for each row execute function app.set_updated_at();

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  department_id uuid,
  code text not null,
  title text not null,
  course_kind public.course_kind not null,
  credit_hours numeric(5,2) not null default 0,
  subject_load numeric(5,2) not null default 1,
  level_number integer,
  metadata jsonb not null default '{}'::jsonb,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint courses_department_scope_fk foreign key (institution_id, department_id)
    references public.departments(institution_id, id) on delete set null,
  constraint courses_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint courses_title_chk check (btrim(title) <> ''),
  constraint courses_credit_chk check (credit_hours >= 0),
  constraint courses_subject_load_chk check (subject_load > 0),
  constraint courses_level_chk check (level_number is null or level_number > 0),
  constraint courses_metadata_chk check (jsonb_typeof(metadata) = 'object'),
  constraint courses_scope_uq unique (institution_id, id)
);
create unique index courses_code_uq on public.courses (institution_id, upper(code));
create index courses_department_idx on public.courses (institution_id, department_id, status);
create trigger courses_set_updated_at before update on public.courses
for each row execute function app.set_updated_at();

create table public.course_prerequisites (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  course_id uuid not null,
  prerequisite_course_id uuid not null,
  minimum_letter_grade text,
  minimum_grade_point numeric(5,2),
  rule_group integer not null default 1,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint course_prerequisites_course_scope_fk foreign key (institution_id, course_id)
    references public.courses(institution_id, id) on delete cascade,
  constraint course_prerequisites_prereq_scope_fk foreign key (institution_id, prerequisite_course_id)
    references public.courses(institution_id, id) on delete cascade,
  constraint course_prerequisites_not_self_chk check (course_id <> prerequisite_course_id),
  constraint course_prerequisites_point_chk check (minimum_grade_point is null or minimum_grade_point >= 0),
  constraint course_prerequisites_group_chk check (rule_group > 0),
  constraint course_prerequisites_scope_uq unique (institution_id, id)
);
create unique index course_prerequisites_edge_uq
  on public.course_prerequisites (course_id, prerequisite_course_id, rule_group);
create trigger course_prerequisites_set_updated_at before update on public.course_prerequisites
for each row execute function app.set_updated_at();

create table public.course_equivalencies (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  course_id uuid not null,
  equivalent_course_id uuid not null,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  constraint course_equivalencies_course_scope_fk foreign key (institution_id, course_id)
    references public.courses(institution_id, id) on delete cascade,
  constraint course_equivalencies_equiv_scope_fk foreign key (institution_id, equivalent_course_id)
    references public.courses(institution_id, id) on delete cascade,
  constraint course_equivalencies_not_self_chk check (course_id <> equivalent_course_id)
);
create unique index course_equivalencies_edge_uq
  on public.course_equivalencies (course_id, equivalent_course_id);

create table public.course_offerings (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  term_id uuid not null,
  course_id uuid not null,
  program_id uuid,
  grading_policy_id uuid not null,
  enrollment_policy_id uuid not null,
  offering_code text not null,
  status public.offering_status not null default 'planned',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint course_offerings_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint course_offerings_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete cascade,
  constraint course_offerings_course_scope_fk foreign key (institution_id, course_id)
    references public.courses(institution_id, id) on delete restrict,
  constraint course_offerings_program_scope_fk foreign key (institution_id, program_id)
    references public.programs(institution_id, id) on delete cascade,
  constraint course_offerings_grading_scope_fk foreign key (institution_id, grading_policy_id)
    references public.grading_policies(institution_id, id) on delete restrict,
  constraint course_offerings_enrollment_scope_fk foreign key (institution_id, enrollment_policy_id)
    references public.enrollment_policies(institution_id, id) on delete restrict,
  constraint course_offerings_code_chk check (btrim(offering_code) <> ''),
  constraint course_offerings_scope_uq unique (institution_id, id)
);
create unique index course_offerings_code_uq
  on public.course_offerings (institution_id, term_id, upper(offering_code));
create index course_offerings_lookup_idx
  on public.course_offerings (institution_id, campus_id, term_id, course_id, status);
create trigger course_offerings_set_updated_at before update on public.course_offerings
for each row execute function app.set_updated_at();

create table public.sections (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  offering_id uuid not null,
  code text not null,
  room_id uuid,
  capacity integer not null,
  status public.section_status not null default 'planned',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint sections_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint sections_offering_scope_fk foreign key (institution_id, offering_id)
    references public.course_offerings(institution_id, id) on delete cascade,
  constraint sections_room_scope_fk foreign key (institution_id, room_id)
    references public.rooms(institution_id, id) on delete set null,
  constraint sections_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
  constraint sections_capacity_chk check (capacity >= 0),
  constraint sections_scope_uq unique (institution_id, id)
);
create unique index sections_code_uq on public.sections (offering_id, upper(code));
create index sections_capacity_idx on public.sections (institution_id, campus_id, offering_id, status, capacity);
create trigger sections_set_updated_at before update on public.sections
for each row execute function app.set_updated_at();

create table public.section_schedules (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  section_id uuid not null,
  room_id uuid,
  day_of_week smallint not null,
  starts_at time not null,
  ends_at time not null,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint section_schedules_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint section_schedules_section_scope_fk foreign key (institution_id, section_id)
    references public.sections(institution_id, id) on delete cascade,
  constraint section_schedules_room_scope_fk foreign key (institution_id, room_id)
    references public.rooms(institution_id, id) on delete set null,
  constraint section_schedules_day_chk check (day_of_week between 1 and 7),
  constraint section_schedules_time_chk check (ends_at > starts_at),
  constraint section_schedules_date_chk check (valid_to is null or valid_from is null or valid_to >= valid_from),
  constraint section_schedules_scope_uq unique (institution_id, id)
);
create unique index section_schedules_slot_uq
  on public.section_schedules (section_id, day_of_week, starts_at, ends_at);
create index section_schedules_conflict_idx
  on public.section_schedules (institution_id, campus_id, day_of_week, starts_at, ends_at);
create trigger section_schedules_set_updated_at before update on public.section_schedules
for each row execute function app.set_updated_at();

create table public.teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  staff_profile_id uuid not null references public.staff_profiles(id) on delete cascade,
  offering_id uuid not null,
  section_id uuid not null,
  role_label text not null default 'teacher',
  valid_from date,
  valid_to date,
  status public.assignment_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint teacher_assignments_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint teacher_assignments_offering_scope_fk foreign key (institution_id, offering_id)
    references public.course_offerings(institution_id, id) on delete cascade,
  constraint teacher_assignments_section_scope_fk foreign key (institution_id, section_id)
    references public.sections(institution_id, id) on delete cascade,
  constraint teacher_assignments_date_chk check (valid_to is null or valid_from is null or valid_to >= valid_from),
  constraint teacher_assignments_role_chk check (btrim(role_label) <> ''),
  constraint teacher_assignments_scope_uq unique (institution_id, id)
);
create unique index teacher_assignments_unique_active
  on public.teacher_assignments (staff_profile_id, section_id, role_label, coalesce(valid_from, date '1900-01-01'));
create index teacher_assignments_staff_idx
  on public.teacher_assignments (staff_profile_id, institution_id, campus_id, status);
create trigger teacher_assignments_set_updated_at before update on public.teacher_assignments
for each row execute function app.set_updated_at();

create table public.assessment_components (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  grading_policy_id uuid not null,
  code text not null,
  name text not null,
  weight_percent numeric(6,3) not null,
  sequence_number integer not null,
  required boolean not null default true,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint assessment_components_policy_scope_fk foreign key (institution_id, grading_policy_id)
    references public.grading_policies(institution_id, id) on delete cascade,
  constraint assessment_components_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint assessment_components_name_chk check (btrim(name) <> ''),
  constraint assessment_components_weight_chk check (weight_percent > 0 and weight_percent <= 100),
  constraint assessment_components_sequence_chk check (sequence_number > 0),
  constraint assessment_components_scope_uq unique (institution_id, id)
);
create unique index assessment_components_code_uq on public.assessment_components (grading_policy_id, upper(code));
create unique index assessment_components_sequence_uq on public.assessment_components (grading_policy_id, sequence_number);
create trigger assessment_components_set_updated_at before update on public.assessment_components
for each row execute function app.set_updated_at();

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  offering_id uuid not null,
  section_id uuid,
  component_id uuid not null,
  code text not null,
  title text not null,
  maximum_marks numeric(8,2) not null,
  due_at timestamptz,
  sequence_number integer not null,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint assessments_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint assessments_offering_scope_fk foreign key (institution_id, offering_id)
    references public.course_offerings(institution_id, id) on delete cascade,
  constraint assessments_section_scope_fk foreign key (institution_id, section_id)
    references public.sections(institution_id, id) on delete cascade,
  constraint assessments_component_scope_fk foreign key (institution_id, component_id)
    references public.assessment_components(institution_id, id) on delete restrict,
  constraint assessments_code_chk check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint assessments_title_chk check (btrim(title) <> ''),
  constraint assessments_max_chk check (maximum_marks > 0),
  constraint assessments_sequence_chk check (sequence_number > 0),
  constraint assessments_scope_uq unique (institution_id, id)
);
create unique index assessments_code_uq
  on public.assessments (offering_id, coalesce(section_id, '00000000-0000-0000-0000-000000000000'::uuid), upper(code));
create index assessments_lookup_idx on public.assessments (institution_id, offering_id, section_id, status);
create trigger assessments_set_updated_at before update on public.assessments
for each row execute function app.set_updated_at();

create or replace function app.is_teacher_for_section(p_section_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.teacher_assignments ta
    where ta.section_id = p_section_id
      and ta.staff_profile_id = app.current_staff_profile_id()
      and ta.status = 'active'
      and (ta.valid_from is null or ta.valid_from <= current_date)
      and (ta.valid_to is null or ta.valid_to >= current_date)
  );
$function$;

revoke all on function app.is_teacher_for_section(uuid) from public, anon, authenticated;
grant execute on function app.is_teacher_for_section(uuid) to authenticated, service_role;

do $do$
declare
  t text;
begin
  foreach t in array array[
    'departments','programs','grading_policies','grade_scales','academic_standing_rules',
    'enrollment_policies','transcript_settings','notification_settings','hec_report_settings',
    'rooms','courses','course_prerequisites','course_equivalencies','course_offerings',
    'sections','section_schedules','teacher_assignments','assessment_components','assessments'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to service_role', t);
    execute format('grant select on table public.%I to authenticated', t);
  end loop;
end
$do$;

create policy departments_select_scoped on public.departments
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy programs_select_scoped on public.programs
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy grading_policies_select_scoped on public.grading_policies
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy grade_scales_select_scoped on public.grade_scales
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy academic_standing_rules_select_scoped on public.academic_standing_rules
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy enrollment_policies_select_admin on public.enrollment_policies
for select to authenticated using ((select app.can_administer_institution(institution_id)));
create policy transcript_settings_select_admin on public.transcript_settings
for select to authenticated using ((select app.can_administer_institution(institution_id)));
create policy notification_settings_select_admin on public.notification_settings
for select to authenticated using ((select app.can_administer_institution(institution_id)));
create policy hec_report_settings_select_admin on public.hec_report_settings
for select to authenticated using ((select app.can_administer_institution(institution_id)));
create policy rooms_select_scoped on public.rooms
for select to authenticated using ((select app.can_access_campus(institution_id, campus_id)));
create policy courses_select_scoped on public.courses
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy course_prerequisites_select_scoped on public.course_prerequisites
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy course_equivalencies_select_scoped on public.course_equivalencies
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy course_offerings_select_scoped on public.course_offerings
for select to authenticated using ((select app.can_access_campus(institution_id, campus_id)));
create policy sections_select_scoped on public.sections
for select to authenticated using (
  (select app.can_access_campus(institution_id, campus_id))
  or (select app.is_teacher_for_section(id))
);
create policy section_schedules_select_scoped on public.section_schedules
for select to authenticated using (
  (select app.can_access_campus(institution_id, campus_id))
  or (select app.is_teacher_for_section(section_id))
);
create policy teacher_assignments_select_scoped on public.teacher_assignments
for select to authenticated using (
  staff_profile_id = (select app.current_staff_profile_id())
  or (select app.can_administer_institution(institution_id))
  or (select app.is_super_administrator())
);
create policy assessment_components_select_scoped on public.assessment_components
for select to authenticated using ((select app.can_access_institution(institution_id)));
create policy assessments_select_scoped on public.assessments
for select to authenticated using (
  (select app.can_access_campus(institution_id, campus_id))
  or (section_id is not null and (select app.is_teacher_for_section(section_id)))
);

commit;
