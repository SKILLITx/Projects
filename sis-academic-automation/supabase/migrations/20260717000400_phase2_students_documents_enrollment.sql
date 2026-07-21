-- Phase 2 accelerated completion, migration 4:
-- students, documents, enrollment requests, decisions, capacity and waitlists.

begin;

create type public.student_status as enum (
  'applicant','active','inactive','suspended','withdrawn','graduated'
);
create type public.program_registration_status as enum (
  'pending','active','completed','withdrawn','cancelled'
);
create type public.student_document_status as enum (
  'missing','submitted','verified','rejected','expired'
);
create type public.business_request_status as enum (
  'received','validating','accepted','rejected','manual_review','completed','failed'
);
create type public.enrollment_outcome as enum (
  'enrolled','waitlisted','rejected','manual_review','cancelled'
);
create type public.waitlist_entry_status as enum (
  'waiting','promoted','declined','expired','cancelled'
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete restrict,
  campus_id uuid not null,
  student_number text not null,
  full_name text not null,
  date_of_birth date,
  cnic_hash text,
  primary_email text,
  status public.student_status not null default 'applicant',
  admitted_on date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint students_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint students_number_chk check (btrim(student_number) <> ''),
  constraint students_name_chk check (btrim(full_name) <> ''),
  constraint students_email_chk check (primary_email is null or position('@' in primary_email) > 1),
  constraint students_metadata_chk check (jsonb_typeof(metadata) = 'object'),
  constraint students_scope_uq unique (institution_id, id)
);
create unique index students_number_uq on public.students (institution_id, upper(student_number));
create unique index students_email_uq on public.students (institution_id, lower(primary_email))
  where primary_email is not null;
create unique index students_cnic_hash_uq on public.students (institution_id, cnic_hash)
  where cnic_hash is not null;
create index students_search_idx on public.students (institution_id, campus_id, status, full_name);
create trigger students_set_updated_at before update on public.students
for each row execute function app.set_updated_at();

create table public.student_auth_links (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  student_id uuid not null,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  constraint student_auth_links_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete cascade,
  constraint student_auth_links_scope_uq unique (institution_id, id),
  constraint student_auth_links_student_uq unique (student_id),
  constraint student_auth_links_auth_uq unique (auth_user_id)
);
create index student_auth_links_auth_idx on public.student_auth_links (auth_user_id, status);

create table public.student_contacts (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  student_id uuid not null,
  contact_type text not null,
  contact_name text,
  email text,
  phone text,
  is_primary boolean not null default false,
  is_guardian boolean not null default false,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint student_contacts_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete cascade,
  constraint student_contacts_type_chk check (
    contact_type in ('student_email','student_phone','guardian','parent','emergency','other')
  ),
  constraint student_contacts_value_chk check (email is not null or phone is not null),
  constraint student_contacts_email_chk check (email is null or position('@' in email) > 1),
  constraint student_contacts_scope_uq unique (institution_id, id)
);
create unique index student_contacts_primary_uq
  on public.student_contacts (student_id, contact_type)
  where is_primary and status = 'active';
create trigger student_contacts_set_updated_at before update on public.student_contacts
for each row execute function app.set_updated_at();

create table public.student_program_registrations (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  student_id uuid not null,
  program_id uuid not null,
  academic_year_id uuid not null,
  start_term_id uuid,
  end_term_id uuid,
  cohort_code text,
  registration_status public.program_registration_status not null default 'pending',
  current_term_sequence integer,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint student_programs_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint student_programs_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete cascade,
  constraint student_programs_program_scope_fk foreign key (institution_id, program_id)
    references public.programs(institution_id, id) on delete restrict,
  constraint student_programs_year_scope_fk foreign key (institution_id, academic_year_id)
    references public.academic_years(institution_id, id) on delete restrict,
  constraint student_programs_start_term_scope_fk foreign key (institution_id, start_term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint student_programs_end_term_scope_fk foreign key (institution_id, end_term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint student_programs_term_sequence_chk check (
    current_term_sequence is null or current_term_sequence > 0
  ),
  constraint student_programs_scope_uq unique (institution_id, id)
);
create unique index student_programs_active_uq
  on public.student_program_registrations (student_id, program_id)
  where registration_status in ('pending','active');
create index student_programs_lookup_idx
  on public.student_program_registrations (institution_id, campus_id, program_id, registration_status);
create trigger student_program_registrations_set_updated_at before update on public.student_program_registrations
for each row execute function app.set_updated_at();

create table public.document_requirements (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  program_id uuid,
  document_code text not null,
  document_name text not null,
  required_for_enrollment boolean not null default true,
  valid_for_days integer,
  status public.record_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint document_requirements_program_scope_fk foreign key (institution_id, program_id)
    references public.programs(institution_id, id) on delete cascade,
  constraint document_requirements_code_chk check (document_code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  constraint document_requirements_name_chk check (btrim(document_name) <> ''),
  constraint document_requirements_days_chk check (valid_for_days is null or valid_for_days > 0),
  constraint document_requirements_scope_uq unique (institution_id, id)
);
create unique index document_requirements_code_uq
  on public.document_requirements (
    institution_id,
    coalesce(program_id, '00000000-0000-0000-0000-000000000000'::uuid),
    upper(document_code)
  );
create trigger document_requirements_set_updated_at before update on public.document_requirements
for each row execute function app.set_updated_at();

create table public.student_documents (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  student_id uuid not null,
  requirement_id uuid not null,
  file_name text,
  storage_provider text,
  storage_object_id text,
  checksum_sha256 text,
  document_status public.student_document_status not null default 'submitted',
  submitted_at timestamptz not null default timezone('utc', now()),
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  expires_on date,
  rejection_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint student_documents_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete cascade,
  constraint student_documents_requirement_scope_fk foreign key (institution_id, requirement_id)
    references public.document_requirements(institution_id, id) on delete restrict,
  constraint student_documents_checksum_chk check (
    checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'
  ),
  constraint student_documents_verify_chk check (
    (document_status = 'verified' and verified_at is not null)
    or document_status <> 'verified'
  ),
  constraint student_documents_reject_chk check (
    (document_status = 'rejected' and btrim(coalesce(rejection_reason,'')) <> '')
    or document_status <> 'rejected'
  ),
  constraint student_documents_scope_uq unique (institution_id, id)
);
create unique index student_documents_current_uq
  on public.student_documents (student_id, requirement_id, submitted_at);
create index student_documents_status_idx
  on public.student_documents (institution_id, student_id, document_status);
create trigger student_documents_set_updated_at before update on public.student_documents
for each row execute function app.set_updated_at();

create table public.student_profile_requests (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete restrict,
  campus_id uuid not null,
  student_id uuid,
  operation text not null,
  correlation_id uuid not null,
  idempotency_key text not null,
  source_submission_id text,
  request_payload jsonb not null,
  request_hash text not null,
  request_status public.business_request_status not null default 'received',
  result_payload jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint student_profile_requests_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint student_profile_requests_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete set null,
  constraint student_profile_requests_operation_chk check (
    operation in ('student.profile.create','student.profile.update')
  ),
  constraint student_profile_requests_idem_chk check (btrim(idempotency_key) <> ''),
  constraint student_profile_requests_payload_chk check (jsonb_typeof(request_payload) = 'object'),
  constraint student_profile_requests_result_chk check (
    result_payload is null or jsonb_typeof(result_payload) = 'object'
  ),
  constraint student_profile_requests_scope_uq unique (institution_id, id)
);
create unique index student_profile_requests_idem_uq
  on public.student_profile_requests (institution_id, operation, idempotency_key);
create index student_profile_requests_status_idx
  on public.student_profile_requests (institution_id, campus_id, request_status, created_at);
create trigger student_profile_requests_set_updated_at before update on public.student_profile_requests
for each row execute function app.set_updated_at();

create table public.enrollment_requests (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete restrict,
  campus_id uuid not null,
  student_id uuid not null,
  enrollment_period_id uuid not null,
  term_id uuid not null,
  program_registration_id uuid not null,
  correlation_id uuid not null,
  idempotency_key text not null,
  source_submission_id text,
  request_payload jsonb not null,
  request_hash text not null,
  request_status public.business_request_status not null default 'received',
  final_outcome public.enrollment_outcome,
  result_payload jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint enrollment_requests_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint enrollment_requests_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint enrollment_requests_period_scope_fk foreign key (institution_id, enrollment_period_id)
    references public.enrollment_periods(institution_id, id) on delete restrict,
  constraint enrollment_requests_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint enrollment_requests_registration_scope_fk foreign key (institution_id, program_registration_id)
    references public.student_program_registrations(institution_id, id) on delete restrict,
  constraint enrollment_requests_idem_chk check (btrim(idempotency_key) <> ''),
  constraint enrollment_requests_payload_chk check (jsonb_typeof(request_payload) = 'object'),
  constraint enrollment_requests_result_chk check (
    result_payload is null or jsonb_typeof(result_payload) = 'object'
  ),
  constraint enrollment_requests_scope_uq unique (institution_id, id)
);
create unique index enrollment_requests_idem_uq
  on public.enrollment_requests (institution_id, idempotency_key);
create index enrollment_requests_status_idx
  on public.enrollment_requests (institution_id, campus_id, term_id, request_status, created_at);
create trigger enrollment_requests_set_updated_at before update on public.enrollment_requests
for each row execute function app.set_updated_at();

create table public.enrollment_request_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  enrollment_request_id uuid not null,
  course_offering_id uuid not null,
  preferred_section_id uuid,
  preference_order integer not null default 1,
  requested_load numeric(6,2) not null,
  item_outcome public.enrollment_outcome,
  assigned_section_id uuid,
  decision_code text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint enrollment_items_request_scope_fk foreign key (institution_id, enrollment_request_id)
    references public.enrollment_requests(institution_id, id) on delete cascade,
  constraint enrollment_items_offering_scope_fk foreign key (institution_id, course_offering_id)
    references public.course_offerings(institution_id, id) on delete restrict,
  constraint enrollment_items_preferred_section_scope_fk foreign key (institution_id, preferred_section_id)
    references public.sections(institution_id, id) on delete restrict,
  constraint enrollment_items_assigned_section_scope_fk foreign key (institution_id, assigned_section_id)
    references public.sections(institution_id, id) on delete restrict,
  constraint enrollment_items_preference_chk check (preference_order > 0),
  constraint enrollment_items_load_chk check (requested_load > 0),
  constraint enrollment_items_scope_uq unique (institution_id, id)
);
create unique index enrollment_request_items_offering_uq
  on public.enrollment_request_items (enrollment_request_id, course_offering_id);
create trigger enrollment_request_items_set_updated_at before update on public.enrollment_request_items
for each row execute function app.set_updated_at();

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  student_id uuid not null,
  program_registration_id uuid not null,
  term_id uuid not null,
  course_offering_id uuid not null,
  section_id uuid not null,
  enrollment_request_item_id uuid,
  enrollment_status text not null default 'active',
  enrolled_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint enrollments_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint enrollments_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint enrollments_registration_scope_fk foreign key (institution_id, program_registration_id)
    references public.student_program_registrations(institution_id, id) on delete restrict,
  constraint enrollments_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint enrollments_offering_scope_fk foreign key (institution_id, course_offering_id)
    references public.course_offerings(institution_id, id) on delete restrict,
  constraint enrollments_section_scope_fk foreign key (institution_id, section_id)
    references public.sections(institution_id, id) on delete restrict,
  constraint enrollments_request_item_scope_fk foreign key (institution_id, enrollment_request_item_id)
    references public.enrollment_request_items(institution_id, id) on delete set null,
  constraint enrollments_status_chk check (
    enrollment_status in ('active','completed','failed','withdrawn','incomplete','audit','cancelled')
  ),
  constraint enrollments_scope_uq unique (institution_id, id)
);
create unique index enrollments_student_offering_active_uq
  on public.enrollments (student_id, course_offering_id)
  where enrollment_status in ('active','completed','failed','incomplete','audit');
create index enrollments_section_status_idx
  on public.enrollments (institution_id, section_id, enrollment_status);
create index enrollments_student_term_idx
  on public.enrollments (institution_id, student_id, term_id, enrollment_status);
create trigger enrollments_set_updated_at before update on public.enrollments
for each row execute function app.set_updated_at();

create table public.enrollment_decisions (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  enrollment_request_id uuid not null,
  enrollment_request_item_id uuid,
  decision public.enrollment_outcome not null,
  decision_code text not null,
  decision_reason text,
  evidence jsonb not null default '{}'::jsonb,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz not null default timezone('utc', now()),
  correlation_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint enrollment_decisions_request_scope_fk foreign key (institution_id, enrollment_request_id)
    references public.enrollment_requests(institution_id, id) on delete cascade,
  constraint enrollment_decisions_item_scope_fk foreign key (institution_id, enrollment_request_item_id)
    references public.enrollment_request_items(institution_id, id) on delete cascade,
  constraint enrollment_decisions_code_chk check (btrim(decision_code) <> ''),
  constraint enrollment_decisions_evidence_chk check (jsonb_typeof(evidence) = 'object'),
  constraint enrollment_decisions_scope_uq unique (institution_id, id)
);
create index enrollment_decisions_request_idx
  on public.enrollment_decisions (institution_id, enrollment_request_id, decided_at);

create table public.waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  campus_id uuid not null,
  student_id uuid not null,
  enrollment_request_item_id uuid not null,
  course_offering_id uuid not null,
  preferred_section_id uuid,
  position_number bigint not null,
  waitlist_status public.waitlist_entry_status not null default 'waiting',
  queued_at timestamptz not null default timezone('utc', now()),
  promoted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint waitlist_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint waitlist_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint waitlist_item_scope_fk foreign key (institution_id, enrollment_request_item_id)
    references public.enrollment_request_items(institution_id, id) on delete cascade,
  constraint waitlist_offering_scope_fk foreign key (institution_id, course_offering_id)
    references public.course_offerings(institution_id, id) on delete restrict,
  constraint waitlist_section_scope_fk foreign key (institution_id, preferred_section_id)
    references public.sections(institution_id, id) on delete restrict,
  constraint waitlist_position_chk check (position_number > 0),
  constraint waitlist_promoted_chk check (
    (waitlist_status = 'promoted' and promoted_at is not null)
    or waitlist_status <> 'promoted'
  ),
  constraint waitlist_scope_uq unique (institution_id, id)
);
create unique index waitlist_active_student_offering_uq
  on public.waitlist_entries (student_id, course_offering_id)
  where waitlist_status = 'waiting';
create unique index waitlist_position_uq
  on public.waitlist_entries (course_offering_id, position_number)
  where waitlist_status = 'waiting';
create index waitlist_queue_idx
  on public.waitlist_entries (institution_id, course_offering_id, waitlist_status, position_number);
create trigger waitlist_entries_set_updated_at before update on public.waitlist_entries
for each row execute function app.set_updated_at();

create table public.timetable_conflict_evidence (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  enrollment_request_item_id uuid not null,
  requested_section_id uuid not null,
  conflicting_enrollment_id uuid not null,
  requested_schedule_id uuid not null,
  conflicting_schedule_id uuid not null,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint timetable_conflicts_item_scope_fk foreign key (institution_id, enrollment_request_item_id)
    references public.enrollment_request_items(institution_id, id) on delete cascade,
  constraint timetable_conflicts_requested_section_scope_fk foreign key (institution_id, requested_section_id)
    references public.sections(institution_id, id) on delete cascade,
  constraint timetable_conflicts_enrollment_scope_fk foreign key (institution_id, conflicting_enrollment_id)
    references public.enrollments(institution_id, id) on delete cascade,
  constraint timetable_conflicts_requested_schedule_scope_fk foreign key (institution_id, requested_schedule_id)
    references public.section_schedules(institution_id, id) on delete cascade,
  constraint timetable_conflicts_conflicting_schedule_scope_fk foreign key (institution_id, conflicting_schedule_id)
    references public.section_schedules(institution_id, id) on delete cascade,
  constraint timetable_conflicts_evidence_chk check (jsonb_typeof(evidence) = 'object')
);
create index timetable_conflicts_item_idx on public.timetable_conflict_evidence (enrollment_request_item_id);

create table public.prerequisite_evidence (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  enrollment_request_item_id uuid not null,
  prerequisite_id uuid not null,
  satisfied boolean not null,
  supporting_course_result_id uuid,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint prerequisite_evidence_item_scope_fk foreign key (institution_id, enrollment_request_item_id)
    references public.enrollment_request_items(institution_id, id) on delete cascade,
  constraint prerequisite_evidence_prereq_scope_fk foreign key (institution_id, prerequisite_id)
    references public.course_prerequisites(institution_id, id) on delete cascade,
  constraint prerequisite_evidence_json_chk check (jsonb_typeof(evidence) = 'object')
);
create index prerequisite_evidence_item_idx on public.prerequisite_evidence (enrollment_request_item_id);

create or replace function app.current_student_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select sal.student_id
  from public.student_auth_links sal
  where sal.auth_user_id = (select auth.uid())
    and sal.status = 'active'
  limit 1;
$function$;

create or replace function app.student_owns(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_student_id is not null and p_student_id = app.current_student_id();
$function$;

create or replace function app.can_view_student(
  p_institution_id uuid,
  p_campus_id uuid,
  p_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    app.student_owns(p_student_id)
    or app.can_administer_institution(p_institution_id)
    or app.can_access_campus(p_institution_id, p_campus_id);
$function$;

create or replace function app.section_active_enrollment_count(p_section_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $function$
  select count(*)::integer
  from public.enrollments e
  where e.section_id = p_section_id
    and e.enrollment_status = 'active';
$function$;

create or replace function app.section_remaining_capacity(p_section_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $function$
  select greatest(s.capacity - app.section_active_enrollment_count(s.id), 0)
  from public.sections s
  where s.id = p_section_id;
$function$;

create or replace function app.has_schedule_conflict(
  p_student_id uuid,
  p_section_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.section_schedules requested
    join public.enrollments e
      on e.student_id = p_student_id
     and e.enrollment_status = 'active'
    join public.section_schedules existing
      on existing.section_id = e.section_id
     and existing.day_of_week = requested.day_of_week
     and existing.starts_at < requested.ends_at
     and requested.starts_at < existing.ends_at
    where requested.section_id = p_section_id
  );
$function$;

revoke all on function app.current_student_id() from public, anon, authenticated;
revoke all on function app.student_owns(uuid) from public, anon, authenticated;
revoke all on function app.can_view_student(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function app.section_active_enrollment_count(uuid) from public, anon, authenticated;
revoke all on function app.section_remaining_capacity(uuid) from public, anon, authenticated;
revoke all on function app.has_schedule_conflict(uuid, uuid) from public, anon, authenticated;

grant execute on function app.current_student_id() to authenticated, service_role;
grant execute on function app.student_owns(uuid) to authenticated, service_role;
grant execute on function app.can_view_student(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.section_active_enrollment_count(uuid) to authenticated, service_role;
grant execute on function app.section_remaining_capacity(uuid) to authenticated, service_role;
grant execute on function app.has_schedule_conflict(uuid, uuid) to authenticated, service_role;

do $do$
declare
  t text;
begin
  foreach t in array array[
    'students','student_auth_links','student_contacts','student_program_registrations',
    'document_requirements','student_documents','student_profile_requests',
    'enrollment_requests','enrollment_request_items','enrollments','enrollment_decisions',
    'waitlist_entries','timetable_conflict_evidence','prerequisite_evidence'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to service_role', t);
  end loop;
end
$do$;

grant select on table public.students to authenticated;
grant select on table public.student_contacts to authenticated;
grant select on table public.student_program_registrations to authenticated;
grant select on table public.document_requirements to authenticated;
grant select on table public.student_documents to authenticated;
grant select on table public.student_profile_requests to authenticated;
grant select on table public.enrollment_requests to authenticated;
grant select on table public.enrollment_request_items to authenticated;
grant select on table public.enrollments to authenticated;
grant select on table public.enrollment_decisions to authenticated;
grant select on table public.waitlist_entries to authenticated;
grant select on table public.timetable_conflict_evidence to authenticated;
grant select on table public.prerequisite_evidence to authenticated;

create policy students_select_scoped on public.students
for select to authenticated using (
  (select app.can_view_student(institution_id, campus_id, id))
);
create policy student_contacts_select_scoped on public.student_contacts
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_administer_institution(institution_id))
);
create policy student_programs_select_scoped on public.student_program_registrations
for select to authenticated using (
  (select app.can_view_student(institution_id, campus_id, student_id))
);
create policy document_requirements_select_scoped on public.document_requirements
for select to authenticated using (
  (select app.can_access_institution(institution_id))
  or exists (
    select 1 from public.students s
    where s.id = (select app.current_student_id())
      and s.institution_id = document_requirements.institution_id
  )
);
create policy student_documents_select_scoped on public.student_documents
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_administer_institution(institution_id))
);
create policy student_profile_requests_select_scoped on public.student_profile_requests
for select to authenticated using (
  (student_id is not null and (select app.student_owns(student_id)))
  or (select app.can_administer_institution(institution_id))
);
create policy enrollment_requests_select_scoped on public.enrollment_requests
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy enrollment_request_items_select_scoped on public.enrollment_request_items
for select to authenticated using (
  exists (
    select 1
    from public.enrollment_requests er
    where er.id = enrollment_request_items.enrollment_request_id
      and (
        (select app.student_owns(er.student_id))
        or (select app.can_access_campus(er.institution_id, er.campus_id))
      )
  )
);
create policy enrollments_select_scoped on public.enrollments
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
  or (select app.is_teacher_for_section(section_id))
);
create policy enrollment_decisions_select_scoped on public.enrollment_decisions
for select to authenticated using (
  exists (
    select 1
    from public.enrollment_requests er
    where er.id = enrollment_decisions.enrollment_request_id
      and (
        (select app.student_owns(er.student_id))
        or (select app.can_access_campus(er.institution_id, er.campus_id))
      )
  )
);
create policy waitlist_entries_select_scoped on public.waitlist_entries
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy timetable_conflicts_select_scoped on public.timetable_conflict_evidence
for select to authenticated using (
  exists (
    select 1
    from public.enrollment_request_items eri
    join public.enrollment_requests er on er.id = eri.enrollment_request_id
    where eri.id = timetable_conflict_evidence.enrollment_request_item_id
      and (
        (select app.student_owns(er.student_id))
        or (select app.can_access_campus(er.institution_id, er.campus_id))
      )
  )
);
create policy prerequisite_evidence_select_scoped on public.prerequisite_evidence
for select to authenticated using (
  exists (
    select 1
    from public.enrollment_request_items eri
    join public.enrollment_requests er on er.id = eri.enrollment_request_id
    where eri.id = prerequisite_evidence.enrollment_request_item_id
      and (
        (select app.student_owns(er.student_id))
        or (select app.can_access_campus(er.institution_id, er.campus_id))
      )
  )
);

-- Student catalog visibility is intentionally read-only.
create policy courses_select_student on public.courses
for select to authenticated using (
  exists (
    select 1 from public.students s
    where s.id = (select app.current_student_id())
      and s.institution_id = courses.institution_id
  )
);
create policy course_offerings_select_student on public.course_offerings
for select to authenticated using (
  status = 'open'
  and exists (
    select 1 from public.students s
    where s.id = (select app.current_student_id())
      and s.institution_id = course_offerings.institution_id
      and s.campus_id = course_offerings.campus_id
  )
);
create policy sections_select_student on public.sections
for select to authenticated using (
  status = 'open'
  and exists (
    select 1 from public.students s
    where s.id = (select app.current_student_id())
      and s.institution_id = sections.institution_id
      and s.campus_id = sections.campus_id
  )
);
create policy section_schedules_select_student on public.section_schedules
for select to authenticated using (
  exists (
    select 1 from public.students s
    where s.id = (select app.current_student_id())
      and s.institution_id = section_schedules.institution_id
      and s.campus_id = section_schedules.campus_id
  )
);

commit;
