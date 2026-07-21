-- Phase 2 accelerated completion, migration 6:
-- transcripts, HEC/report jobs, notifications, workflow evidence, incidents and audit.

begin;

create type public.transcript_request_status as enum (
  'requested','authorized','generating','ready','delivered','failed','cancelled'
);
create type ops.job_status as enum (
  'pending','claimed','running','completed','failed','dead_letter','cancelled'
);
create type ops.notification_channel as enum ('email','whatsapp','sms','internal');
create type ops.delivery_status as enum (
  'pending','sending','delivered','temporary_failure','permanent_failure','dead_letter'
);
create type ops.workflow_run_status as enum (
  'started','completed','failed','cancelled'
);
create type ops.incident_status as enum (
  'open','acknowledged','resolved','suppressed'
);
create type ops.incident_severity as enum ('info','warning','error','critical');

create table ops.idempotency_records (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  operation text not null,
  idempotency_key text not null,
  request_hash text not null,
  correlation_id uuid not null,
  state text not null default 'processing',
  result_payload jsonb,
  error_payload jsonb,
  locked_until timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint idempotency_operation_chk check (operation ~ '^[a-z][a-z0-9_.:-]{2,99}$'),
  constraint idempotency_key_chk check (btrim(idempotency_key) <> ''),
  constraint idempotency_hash_chk check (request_hash ~ '^[A-Fa-f0-9]{64}$'),
  constraint idempotency_state_chk check (state in ('processing','completed','failed')),
  constraint idempotency_result_chk check (
    result_payload is null or jsonb_typeof(result_payload) = 'object'
  ),
  constraint idempotency_error_chk check (
    error_payload is null or jsonb_typeof(error_payload) = 'object'
  )
);
create unique index idempotency_operation_key_uq
  on ops.idempotency_records (institution_id, operation, idempotency_key);
create index idempotency_state_idx
  on ops.idempotency_records (institution_id, state, locked_until);
create trigger idempotency_records_set_updated_at before update on ops.idempotency_records
for each row execute function app.set_updated_at();

create table ops.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  campus_id uuid,
  channel ops.notification_channel not null default 'email',
  notification_type text not null,
  recipient_address text not null,
  recipient_name text,
  subject text,
  template_code text,
  payload jsonb not null default '{}'::jsonb,
  correlation_id uuid not null,
  idempotency_key text not null,
  job_status ops.job_status not null default 'pending',
  priority integer not null default 100,
  available_at timestamptz not null default timezone('utc', now()),
  claimed_at timestamptz,
  claimed_by text,
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  last_error_code text,
  last_error_message text,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint notification_outbox_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint notification_outbox_type_chk check (
    notification_type ~ '^[a-z][a-z0-9_.:-]{2,99}$'
  ),
  constraint notification_outbox_recipient_chk check (btrim(recipient_address) <> ''),
  constraint notification_outbox_payload_chk check (jsonb_typeof(payload) = 'object'),
  constraint notification_outbox_idem_chk check (btrim(idempotency_key) <> ''),
  constraint notification_outbox_priority_chk check (priority between 1 and 1000),
  constraint notification_outbox_attempts_chk check (
    attempt_count >= 0 and max_attempts > 0 and attempt_count <= max_attempts
  )
);
create unique index notification_outbox_idem_uq
  on ops.notification_outbox (institution_id, channel, notification_type, idempotency_key);
create index notification_outbox_claim_idx
  on ops.notification_outbox (job_status, available_at, priority, created_at);
create trigger notification_outbox_set_updated_at before update on ops.notification_outbox
for each row execute function app.set_updated_at();

create table ops.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  outbox_id uuid not null references ops.notification_outbox(id) on delete cascade,
  attempt_number integer not null,
  delivery_status ops.delivery_status not null,
  provider text not null,
  provider_message_id text,
  error_code text,
  sanitized_error_message text,
  retryable boolean not null default false,
  started_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint notification_deliveries_attempt_chk check (attempt_number > 0),
  constraint notification_deliveries_provider_chk check (btrim(provider) <> ''),
  constraint notification_deliveries_time_chk check (
    finished_at is null or finished_at >= started_at
  )
);
create unique index notification_deliveries_attempt_uq
  on ops.notification_deliveries (outbox_id, attempt_number);
create index notification_deliveries_status_idx
  on ops.notification_deliveries (institution_id, delivery_status, created_at);

create table ops.workflow_runs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid references public.institutions(id) on delete set null,
  campus_id uuid,
  workflow_code text not null,
  n8n_execution_id text,
  operation text,
  correlation_id uuid not null,
  idempotency_key text,
  run_status ops.workflow_run_status not null default 'started',
  started_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz,
  input_summary jsonb not null default '{}'::jsonb,
  output_summary jsonb not null default '{}'::jsonb,
  error_code text,
  sanitized_error_message text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint workflow_runs_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete set null,
  constraint workflow_runs_code_chk check (workflow_code ~ '^[0-9]{2}-[a-z0-9-]{3,80}$'),
  constraint workflow_runs_time_chk check (
    finished_at is null or finished_at >= started_at
  ),
  constraint workflow_runs_input_chk check (jsonb_typeof(input_summary) = 'object'),
  constraint workflow_runs_output_chk check (jsonb_typeof(output_summary) = 'object')
);
create index workflow_runs_corr_idx on ops.workflow_runs (correlation_id, started_at);
create index workflow_runs_status_idx on ops.workflow_runs (run_status, started_at);
create unique index workflow_runs_execution_uq on ops.workflow_runs (n8n_execution_id)
  where n8n_execution_id is not null;
create trigger workflow_runs_set_updated_at before update on ops.workflow_runs
for each row execute function app.set_updated_at();

create table ops.incidents (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid references public.institutions(id) on delete set null,
  campus_id uuid,
  fingerprint text not null,
  root_correlation_id uuid,
  workflow_code text,
  operation text,
  severity ops.incident_severity not null default 'error',
  incident_status ops.incident_status not null default 'open',
  title text not null,
  summary text not null,
  first_seen_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  occurrence_count integer not null default 1,
  acknowledged_by uuid references auth.users(id) on delete set null,
  acknowledged_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint incidents_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete set null,
  constraint incidents_fingerprint_chk check (fingerprint ~ '^[A-Fa-f0-9]{64}$'),
  constraint incidents_title_chk check (btrim(title) <> ''),
  constraint incidents_summary_chk check (btrim(summary) <> ''),
  constraint incidents_occurrence_chk check (occurrence_count > 0),
  constraint incidents_seen_chk check (last_seen_at >= first_seen_at),
  constraint incidents_ack_chk check (
    (incident_status in ('acknowledged','resolved') and acknowledged_at is not null)
    or incident_status in ('open','suppressed')
  ),
  constraint incidents_resolve_chk check (
    (incident_status = 'resolved' and resolved_at is not null)
    or incident_status <> 'resolved'
  )
);
create unique index incidents_active_fingerprint_uq
  on ops.incidents (fingerprint)
  where incident_status in ('open','acknowledged');
create index incidents_status_idx
  on ops.incidents (incident_status, severity, last_seen_at);
create trigger incidents_set_updated_at before update on ops.incidents
for each row execute function app.set_updated_at();

create table ops.incident_events (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references ops.incidents(id) on delete cascade,
  event_type text not null,
  correlation_id uuid,
  n8n_execution_id text,
  retry_number integer,
  retryable boolean,
  sanitized_details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint incident_events_type_chk check (event_type ~ '^[a-z][a-z0-9_.:-]{2,99}$'),
  constraint incident_events_retry_chk check (retry_number is null or retry_number >= 0),
  constraint incident_events_details_chk check (jsonb_typeof(sanitized_details) = 'object')
);
create index incident_events_incident_idx on ops.incident_events (incident_id, occurred_at);

create table ops.hec_report_runs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  campus_id uuid,
  academic_year_id uuid not null,
  term_id uuid,
  program_id uuid,
  requested_by uuid references auth.users(id) on delete set null,
  correlation_id uuid not null,
  idempotency_key text not null,
  filters jsonb not null default '{}'::jsonb,
  job_status ops.job_status not null default 'pending',
  template_label text not null default 'Demonstration HEC Enrollment Format',
  requested_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  error_code text,
  sanitized_error_message text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint hec_runs_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete set null,
  constraint hec_runs_year_scope_fk foreign key (institution_id, academic_year_id)
    references public.academic_years(institution_id, id) on delete restrict,
  constraint hec_runs_term_scope_fk foreign key (institution_id, term_id)
    references public.terms(institution_id, id) on delete restrict,
  constraint hec_runs_program_scope_fk foreign key (institution_id, program_id)
    references public.programs(institution_id, id) on delete restrict,
  constraint hec_runs_idem_chk check (btrim(idempotency_key) <> ''),
  constraint hec_runs_filters_chk check (jsonb_typeof(filters) = 'object'),
  constraint hec_runs_template_chk check (btrim(template_label) <> ''),
  constraint hec_runs_complete_chk check (
    (job_status = 'completed' and completed_at is not null)
    or job_status <> 'completed'
  )
);
create unique index hec_report_runs_idem_uq
  on ops.hec_report_runs (institution_id, idempotency_key);
create index hec_report_runs_status_idx
  on ops.hec_report_runs (institution_id, job_status, requested_at);
create trigger hec_report_runs_set_updated_at before update on ops.hec_report_runs
for each row execute function app.set_updated_at();

create table ops.generated_report_files (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  hec_report_run_id uuid references ops.hec_report_runs(id) on delete cascade,
  report_type text not null,
  file_format text not null,
  storage_provider text not null,
  storage_object_id text not null,
  file_url text,
  checksum_sha256 text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint generated_report_type_chk check (
    report_type in ('hec_enrollment','dashboard_snapshot','other')
  ),
  constraint generated_report_format_chk check (
    file_format in ('google_sheet','csv','xlsx','pdf','json')
  ),
  constraint generated_report_provider_chk check (btrim(storage_provider) <> ''),
  constraint generated_report_object_chk check (btrim(storage_object_id) <> ''),
  constraint generated_report_checksum_chk check (
    checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'
  )
);
create index generated_report_run_idx on ops.generated_report_files (hec_report_run_id);

create table ops.dashboard_refresh_runs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  campus_id uuid,
  correlation_id uuid not null,
  job_status ops.job_status not null default 'pending',
  snapshot jsonb,
  requested_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint dashboard_runs_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete cascade,
  constraint dashboard_runs_snapshot_chk check (
    snapshot is null or jsonb_typeof(snapshot) = 'object'
  ),
  constraint dashboard_runs_complete_chk check (
    (job_status = 'completed' and completed_at is not null)
    or job_status <> 'completed'
  )
);
create index dashboard_refresh_status_idx
  on ops.dashboard_refresh_runs (institution_id, job_status, requested_at);
create trigger dashboard_refresh_runs_set_updated_at before update on ops.dashboard_refresh_runs
for each row execute function app.set_updated_at();

create table ops.maintenance_runs (
  id uuid primary key default gen_random_uuid(),
  operation text not null,
  correlation_id uuid not null,
  job_status ops.job_status not null default 'running',
  metrics jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint maintenance_runs_operation_chk check (
    operation ~ '^[a-z][a-z0-9_.:-]{2,99}$'
  ),
  constraint maintenance_runs_metrics_chk check (jsonb_typeof(metrics) = 'object'),
  constraint maintenance_runs_time_chk check (
    completed_at is null or completed_at >= started_at
  )
);
create index maintenance_runs_status_idx on ops.maintenance_runs (job_status, started_at);

create table public.transcript_requests (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete restrict,
  campus_id uuid not null,
  student_id uuid not null,
  requested_by_auth_user_id uuid references auth.users(id) on delete set null,
  recipient_email text not null,
  purpose text,
  correlation_id uuid not null,
  idempotency_key text not null,
  request_status public.transcript_request_status not null default 'requested',
  reference_number text not null,
  verification_code text,
  authorized_at timestamptz,
  completed_at timestamptz,
  error_code text,
  sanitized_error_message text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint transcript_requests_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete restrict,
  constraint transcript_requests_student_scope_fk foreign key (institution_id, student_id)
    references public.students(institution_id, id) on delete restrict,
  constraint transcript_requests_email_chk check (position('@' in recipient_email) > 1),
  constraint transcript_requests_idem_chk check (btrim(idempotency_key) <> ''),
  constraint transcript_requests_reference_chk check (btrim(reference_number) <> ''),
  constraint transcript_requests_authorized_chk check (
    (request_status in ('authorized','generating','ready','delivered') and authorized_at is not null)
    or request_status in ('requested','failed','cancelled')
  ),
  constraint transcript_requests_complete_chk check (
    (request_status in ('ready','delivered') and completed_at is not null)
    or request_status not in ('ready','delivered')
  ),
  constraint transcript_requests_scope_uq unique (institution_id, id)
);
create unique index transcript_requests_idem_uq
  on public.transcript_requests (institution_id, idempotency_key);
create unique index transcript_requests_reference_uq
  on public.transcript_requests (institution_id, upper(reference_number));
create index transcript_requests_status_idx
  on public.transcript_requests (institution_id, campus_id, request_status, created_at);
create trigger transcript_requests_set_updated_at before update on public.transcript_requests
for each row execute function app.set_updated_at();

create table public.transcript_documents (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  transcript_request_id uuid not null,
  document_version integer not null default 1,
  google_doc_id text,
  pdf_drive_file_id text,
  pdf_file_url text,
  checksum_sha256 text,
  generated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint transcript_documents_request_scope_fk foreign key (institution_id, transcript_request_id)
    references public.transcript_requests(institution_id, id) on delete cascade,
  constraint transcript_documents_version_chk check (document_version > 0),
  constraint transcript_documents_file_chk check (
    google_doc_id is not null or pdf_drive_file_id is not null
  ),
  constraint transcript_documents_checksum_chk check (
    checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'
  ),
  constraint transcript_documents_scope_uq unique (institution_id, id)
);
create unique index transcript_documents_version_uq
  on public.transcript_documents (transcript_request_id, document_version);

create table public.transcript_delivery_records (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  transcript_request_id uuid not null,
  transcript_document_id uuid not null,
  recipient_email text not null,
  outbox_id uuid references ops.notification_outbox(id) on delete set null,
  delivery_status ops.delivery_status not null default 'pending',
  provider_message_id text,
  delivered_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint transcript_delivery_request_scope_fk foreign key (institution_id, transcript_request_id)
    references public.transcript_requests(institution_id, id) on delete cascade,
  constraint transcript_delivery_document_scope_fk foreign key (institution_id, transcript_document_id)
    references public.transcript_documents(institution_id, id) on delete cascade,
  constraint transcript_delivery_email_chk check (position('@' in recipient_email) > 1),
  constraint transcript_delivery_done_chk check (
    (delivery_status = 'delivered' and delivered_at is not null)
    or delivery_status <> 'delivered'
  ),
  constraint transcript_delivery_scope_uq unique (institution_id, id)
);
create unique index transcript_delivery_document_recipient_uq
  on public.transcript_delivery_records (transcript_document_id, lower(recipient_email));
create trigger transcript_delivery_records_set_updated_at before update on public.transcript_delivery_records
for each row execute function app.set_updated_at();

create table audit.audit_logs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid references public.institutions(id) on delete set null,
  campus_id uuid,
  actor_auth_user_id uuid references auth.users(id) on delete set null,
  actor_staff_profile_id uuid references public.staff_profiles(id) on delete set null,
  actor_student_id uuid,
  operation text not null,
  entity_type text,
  entity_id uuid,
  correlation_id uuid,
  outcome text not null,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint audit_logs_campus_scope_fk foreign key (institution_id, campus_id)
    references public.campuses(institution_id, id) on delete set null,
  constraint audit_logs_student_scope_fk foreign key (institution_id, actor_student_id)
    references public.students(institution_id, id) on delete set null,
  constraint audit_logs_operation_chk check (operation ~ '^[a-z][a-z0-9_.:-]{2,99}$'),
  constraint audit_logs_outcome_chk check (outcome in ('success','failure','denied','warning')),
  constraint audit_logs_details_chk check (jsonb_typeof(details) = 'object')
);
create index audit_logs_scope_time_idx
  on audit.audit_logs (institution_id, campus_id, occurred_at desc);
create index audit_logs_corr_idx on audit.audit_logs (correlation_id);

create table audit.data_change_events (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid references public.institutions(id) on delete set null,
  table_name text not null,
  record_id uuid,
  action text not null,
  changed_by uuid references auth.users(id) on delete set null,
  correlation_id uuid,
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default timezone('utc', now()),
  constraint data_change_table_chk check (table_name ~ '^[a-z][a-z0-9_]{2,99}$'),
  constraint data_change_action_chk check (action in ('insert','update','delete')),
  constraint data_change_before_chk check (
    before_data is null or jsonb_typeof(before_data) = 'object'
  ),
  constraint data_change_after_chk check (
    after_data is null or jsonb_typeof(after_data) = 'object'
  )
);
create index data_change_events_record_idx
  on audit.data_change_events (table_name, record_id, occurred_at desc);

create or replace view reporting.section_capacity_snapshot
with (security_invoker = true)
as
select
  s.institution_id,
  s.campus_id,
  co.term_id,
  co.course_id,
  s.offering_id,
  s.id as section_id,
  s.code as section_code,
  s.capacity,
  app.section_active_enrollment_count(s.id) as enrolled_count,
  app.section_remaining_capacity(s.id) as remaining_capacity,
  count(w.id) filter (where w.waitlist_status = 'waiting')::integer as waitlist_count
from public.sections s
join public.course_offerings co on co.id = s.offering_id
left join public.waitlist_entries w on w.course_offering_id = s.offering_id
group by s.institution_id, s.campus_id, co.term_id, co.course_id, s.offering_id, s.id, s.code, s.capacity;

create or replace view reporting.student_academic_snapshot
with (security_invoker = true)
as
select
  s.institution_id,
  s.campus_id,
  s.id as student_id,
  s.student_number,
  s.full_name,
  spr.program_id,
  cr.cgpa,
  cr.standing_code,
  cr.at_risk,
  cr.last_term_id
from public.students s
left join public.student_program_registrations spr
  on spr.student_id = s.id and spr.registration_status = 'active'
left join public.cumulative_results cr
  on cr.student_id = s.id and cr.program_registration_id = spr.id;

revoke all on reporting.section_capacity_snapshot from public, anon, authenticated;
revoke all on reporting.student_academic_snapshot from public, anon, authenticated;
grant select on reporting.section_capacity_snapshot to service_role;
grant select on reporting.student_academic_snapshot to service_role;

create or replace function ops.claim_notification_batch(
  p_worker_id text,
  p_limit integer
)
returns setof ops.notification_outbox
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if btrim(coalesce(p_worker_id,'')) = '' then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_WORKER_REQUIRED';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = 'P0001', message = 'NOTIFICATION_LIMIT_INVALID';
  end if;

  return query
  with candidates as (
    select no.id
    from ops.notification_outbox no
    where no.job_status = 'pending'
      and no.available_at <= timezone('utc', now())
      and no.attempt_count < no.max_attempts
    order by no.priority, no.created_at
    for update skip locked
    limit p_limit
  )
  update ops.notification_outbox no
  set job_status = 'claimed',
      claimed_at = timezone('utc', now()),
      claimed_by = p_worker_id,
      updated_at = timezone('utc', now())
  from candidates c
  where no.id = c.id
  returning no.*;
end;
$function$;

create or replace function ops.upsert_incident(
  p_institution_id uuid,
  p_campus_id uuid,
  p_fingerprint text,
  p_correlation_id uuid,
  p_workflow_code text,
  p_operation text,
  p_severity ops.incident_severity,
  p_title text,
  p_summary text,
  p_event_type text,
  p_event_details jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_incident_id uuid;
begin
  insert into ops.incidents (
    institution_id, campus_id, fingerprint, root_correlation_id,
    workflow_code, operation, severity, title, summary
  )
  values (
    p_institution_id, p_campus_id, p_fingerprint, p_correlation_id,
    p_workflow_code, p_operation, p_severity, p_title, p_summary
  )
  on conflict (fingerprint) where incident_status in ('open','acknowledged')
  do update set
    last_seen_at = timezone('utc', now()),
    occurrence_count = ops.incidents.occurrence_count + 1,
    severity = case
      when excluded.severity = 'critical' then 'critical'::ops.incident_severity
      when ops.incidents.severity = 'critical' then ops.incidents.severity
      when excluded.severity = 'error' then 'error'::ops.incident_severity
      else ops.incidents.severity
    end,
    updated_at = timezone('utc', now())
  returning id into v_incident_id;

  insert into ops.incident_events (
    incident_id, event_type, correlation_id, sanitized_details
  )
  values (
    v_incident_id, p_event_type, p_correlation_id, coalesce(p_event_details, '{}'::jsonb)
  );

  return v_incident_id;
end;
$function$;

revoke all on function ops.claim_notification_batch(text, integer) from public, anon, authenticated;
revoke all on function ops.upsert_incident(
  uuid, uuid, text, uuid, text, text, ops.incident_severity, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function ops.claim_notification_batch(text, integer) to service_role;
grant execute on function ops.upsert_incident(
  uuid, uuid, text, uuid, text, text, ops.incident_severity, text, text, text, jsonb
) to service_role;

do $do$
declare
  t text;
begin
  foreach t in array array[
    'transcript_requests','transcript_documents','transcript_delivery_records'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to service_role', t);
    execute format('grant select on table public.%I to authenticated', t);
  end loop;
end
$do$;

create policy transcript_requests_select_scoped on public.transcript_requests
for select to authenticated using (
  (select app.student_owns(student_id))
  or (select app.can_access_campus(institution_id, campus_id))
);
create policy transcript_documents_select_scoped on public.transcript_documents
for select to authenticated using (
  exists (
    select 1
    from public.transcript_requests tr
    where tr.id = transcript_documents.transcript_request_id
      and (
        (select app.student_owns(tr.student_id))
        or (select app.can_access_campus(tr.institution_id, tr.campus_id))
      )
  )
);
create policy transcript_delivery_select_scoped on public.transcript_delivery_records
for select to authenticated using (
  exists (
    select 1
    from public.transcript_requests tr
    where tr.id = transcript_delivery_records.transcript_request_id
      and (
        (select app.student_owns(tr.student_id))
        or (select app.can_access_campus(tr.institution_id, tr.campus_id))
      )
  )
);

grant usage on schema ops, audit, reporting to service_role;
grant select, insert, update, delete on all tables in schema ops to service_role;
grant select, insert on all tables in schema audit to service_role;

comment on view reporting.section_capacity_snapshot is
  'Internal capacity model; accessed only through stable public RPCs.';
comment on view reporting.student_academic_snapshot is
  'Internal academic summary; accessed only through stable public RPCs.';

commit;
