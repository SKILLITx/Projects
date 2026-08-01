-- Workflow 09 — Scheduled Operations and Monitoring.
-- Immutable repair/completion migration for the controlled pilot.
-- This migration keeps host-level backup execution outside n8n and exposes only
-- stable public RPC wrappers. It does not delete academic records.

begin;

create unique index if not exists maintenance_runs_operation_corr_uq
  on ops.maintenance_runs (operation, correlation_id);

create index if not exists maintenance_runs_operation_completed_idx
  on ops.maintenance_runs (operation, completed_at desc, started_at desc);

create index if not exists workflow_runs_monitoring_idx
  on ops.workflow_runs (institution_id, started_at desc, run_status);

create index if not exists notification_outbox_monitoring_idx
  on ops.notification_outbox (institution_id, job_status, created_at);

create index if not exists incidents_monitoring_idx
  on ops.incidents (institution_id, incident_status, severity, last_seen_at desc);

create index if not exists waitlist_monitoring_idx
  on public.waitlist_entries (institution_id, waitlist_status, queued_at);

create index if not exists marks_batches_monitoring_idx
  on public.marks_batches (institution_id, batch_status, created_at);

create or replace function public.rpc_get_operations_snapshot(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'operations.snapshot';
  v_correlation_id uuid;
  v_institution_text text := nullif(p_request#>>'{context,institution_id}','');
  v_institution_id uuid;
  v_backup_max_age_hours integer := 48;
  v_retention_workflow_days integer := 90;
  v_retention_incident_days integer := 180;
  v_retention_delivery_days integer := 180;
  v_now timestamptz := now();

  v_workflow_started bigint := 0;
  v_workflow_completed bigint := 0;
  v_workflow_failed bigint := 0;
  v_workflow_stale bigint := 0;

  v_notifications_pending bigint := 0;
  v_notifications_claimed bigint := 0;
  v_notifications_dead bigint := 0;
  v_notifications_oldest_minutes numeric;

  v_incidents_open bigint := 0;
  v_incidents_ack bigint := 0;
  v_incidents_critical bigint := 0;

  v_waitlist_waiting bigint := 0;
  v_waitlist_oldest_hours numeric;

  v_marks_drafts bigint := 0;
  v_marks_stale_drafts bigint := 0;
  v_marks_overdue_sections bigint := 0;

  v_dashboard_pending bigint := 0;

  v_backup_job_status text;
  v_backup_verified_at timestamptz;
  v_backup_age_hours numeric;
  v_backup_status text;

  v_old_workflow_runs bigint := 0;
  v_old_incident_events bigint := 0;
  v_old_delivery_records bigint := 0;

  v_by_institution jsonb := '[]'::jsonb;
  v_snapshot jsonb;
  v_warnings jsonb := '[]'::jsonb;
begin
  if coalesce(p_request->>'correlation_id','') !~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return app.rpc_error(
      v_operation,
      gen_random_uuid(),
      'VALIDATION_CORRELATION_UUID_INVALID',
      'The monitoring correlation identifier is invalid.',
      false
    );
  end if;
  v_correlation_id := (p_request->>'correlation_id')::uuid;

  if v_institution_text is not null and v_institution_text !~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return app.rpc_error(
      v_operation,
      v_correlation_id,
      'VALIDATION_INSTITUTION_UUID_INVALID',
      'The monitoring institution identifier is invalid.',
      false
    );
  end if;
  v_institution_id := v_institution_text::uuid;

  if not app.is_service_request() then
    if v_institution_id is null then
      if not app.is_super_administrator() then
        raise exception using errcode='P0001', message='AUTH_SCOPE_DENIED';
      end if;
    elsif not (
      app.is_super_administrator()
      or app.can_administer_institution(v_institution_id)
    ) then
      raise exception using errcode='P0001', message='AUTH_SCOPE_DENIED';
    end if;
  end if;

  if coalesce(p_request#>>'{payload,backup_max_age_hours}','') ~ '^[0-9]+$' then
    v_backup_max_age_hours := least(
      greatest((p_request#>>'{payload,backup_max_age_hours}')::integer, 1),
      720
    );
  end if;
  if coalesce(p_request#>>'{payload,retention_workflow_days}','') ~ '^[0-9]+$' then
    v_retention_workflow_days := least(
      greatest((p_request#>>'{payload,retention_workflow_days}')::integer, 30),
      3650
    );
  end if;
  if coalesce(p_request#>>'{payload,retention_incident_days}','') ~ '^[0-9]+$' then
    v_retention_incident_days := least(
      greatest((p_request#>>'{payload,retention_incident_days}')::integer, 30),
      3650
    );
  end if;
  if coalesce(p_request#>>'{payload,retention_delivery_days}','') ~ '^[0-9]+$' then
    v_retention_delivery_days := least(
      greatest((p_request#>>'{payload,retention_delivery_days}')::integer, 30),
      3650
    );
  end if;

  select
    count(*) filter (where wr.started_at >= v_now - interval '24 hours'),
    count(*) filter (
      where wr.started_at >= v_now - interval '24 hours'
        and wr.run_status = 'completed'
    ),
    count(*) filter (
      where wr.started_at >= v_now - interval '24 hours'
        and wr.run_status = 'failed'
    ),
    count(*) filter (
      where wr.run_status = 'started'
        and wr.started_at < v_now - interval '30 minutes'
    )
  into
    v_workflow_started,
    v_workflow_completed,
    v_workflow_failed,
    v_workflow_stale
  from ops.workflow_runs wr
  where v_institution_id is null or wr.institution_id = v_institution_id;

  select
    count(*) filter (where no.job_status = 'pending'),
    count(*) filter (where no.job_status = 'claimed'),
    count(*) filter (where no.job_status = 'dead_letter'),
    round(
      extract(epoch from (
        v_now - (min(no.created_at) filter (
          where no.job_status = 'pending'
        ))
      ))::numeric / 60,
      1
    )
  into
    v_notifications_pending,
    v_notifications_claimed,
    v_notifications_dead,
    v_notifications_oldest_minutes
  from ops.notification_outbox no
  where v_institution_id is null or no.institution_id = v_institution_id;

  select
    count(*) filter (where i.incident_status = 'open'),
    count(*) filter (where i.incident_status = 'acknowledged'),
    count(*) filter (
      where i.incident_status in ('open','acknowledged')
        and i.severity = 'critical'
    )
  into v_incidents_open, v_incidents_ack, v_incidents_critical
  from ops.incidents i
  where v_institution_id is null or i.institution_id = v_institution_id;

  select
    count(*),
    round(extract(epoch from (v_now - min(w.queued_at)))::numeric / 3600, 1)
  into v_waitlist_waiting, v_waitlist_oldest_hours
  from public.waitlist_entries w
  where w.waitlist_status = 'waiting'
    and (v_institution_id is null or w.institution_id = v_institution_id);

  select
    count(*) filter (where mb.batch_status = 'draft'),
    count(*) filter (
      where mb.batch_status = 'draft'
        and mb.created_at < v_now - interval '90 days'
    )
  into v_marks_drafts, v_marks_stale_drafts
  from public.marks_batches mb
  where v_institution_id is null or mb.institution_id = v_institution_id;

  select count(*)
  into v_marks_overdue_sections
  from public.sections s
  join public.course_offerings co
    on co.id = s.offering_id
   and co.institution_id = s.institution_id
  join public.terms t
    on t.id = co.term_id
   and t.institution_id = co.institution_id
  where s.status in ('open','closed','completed')
    and t.ends_on < current_date
    and (v_institution_id is null or s.institution_id = v_institution_id)
    and not exists (
      select 1
      from public.marks_batches mb
      where mb.institution_id = s.institution_id
        and mb.section_id = s.id
        and mb.batch_status in ('finalized','approved')
    );

  select count(*)
  into v_dashboard_pending
  from ops.dashboard_refresh_runs dr
  where dr.job_status in ('pending','claimed','running')
    and (v_institution_id is null or dr.institution_id = v_institution_id);

  select
    mr.job_status::text,
    coalesce(mr.completed_at, mr.started_at)
  into v_backup_job_status, v_backup_verified_at
  from ops.maintenance_runs mr
  where mr.operation = 'backup.verify'
  order by coalesce(mr.completed_at, mr.started_at) desc
  limit 1;

  if v_backup_verified_at is null then
    v_backup_status := 'not_recorded';
    v_backup_age_hours := null;
  else
    v_backup_age_hours := round(
      extract(epoch from (v_now - v_backup_verified_at))::numeric / 3600,
      1
    );
    v_backup_status := case
      when v_backup_job_status <> 'completed' then 'failed'
      when v_backup_age_hours <= v_backup_max_age_hours then 'current'
      else 'stale'
    end;
  end if;

  select count(*)
  into v_old_workflow_runs
  from ops.workflow_runs wr
  where wr.started_at < v_now - make_interval(days => v_retention_workflow_days)
    and (v_institution_id is null or wr.institution_id = v_institution_id);

  select count(*)
  into v_old_incident_events
  from ops.incident_events ie
  join ops.incidents i on i.id = ie.incident_id
  where ie.occurred_at < v_now - make_interval(days => v_retention_incident_days)
    and (v_institution_id is null or i.institution_id = v_institution_id);

  select count(*)
  into v_old_delivery_records
  from ops.notification_deliveries nd
  where nd.created_at < v_now - make_interval(days => v_retention_delivery_days)
    and (v_institution_id is null or nd.institution_id = v_institution_id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'institution_id', i.id,
      'institution_code', i.code,
      'institution_name', i.name,
      'notification_pending', (
        select count(*) from ops.notification_outbox no
        where no.institution_id = i.id and no.job_status = 'pending'
      ),
      'notification_dead_letter', (
        select count(*) from ops.notification_outbox no
        where no.institution_id = i.id and no.job_status = 'dead_letter'
      ),
      'open_incidents', (
        select count(*) from ops.incidents inc
        where inc.institution_id = i.id
          and inc.incident_status in ('open','acknowledged')
      ),
      'waiting_students', (
        select count(*) from public.waitlist_entries w
        where w.institution_id = i.id and w.waitlist_status = 'waiting'
      ),
      'overdue_marks_sections', (
        select count(*)
        from public.sections s
        join public.course_offerings co
          on co.id = s.offering_id
         and co.institution_id = s.institution_id
        join public.terms t
          on t.id = co.term_id
         and t.institution_id = co.institution_id
        where s.institution_id = i.id
          and s.status in ('open','closed','completed')
          and t.ends_on < current_date
          and not exists (
            select 1 from public.marks_batches mb
            where mb.institution_id = s.institution_id
              and mb.section_id = s.id
              and mb.batch_status in ('finalized','approved')
          )
      )
    )
    order by i.code
  ), '[]'::jsonb)
  into v_by_institution
  from public.institutions i
  where i.status = 'active'
    and (v_institution_id is null or i.id = v_institution_id);

  if v_notifications_dead > 0 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code','NOTIFICATION_DEAD_LETTER_PRESENT',
      'message','One or more notifications require manual review.'
    ));
  end if;
  if v_incidents_open + v_incidents_ack > 0 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code','UNRESOLVED_INCIDENTS_PRESENT',
      'message','Unresolved operational incidents are present.'
    ));
  end if;
  if v_marks_overdue_sections > 0 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code','OVERDUE_MARKS_PRESENT',
      'message','One or more completed terms have sections without finalized marks.'
    ));
  end if;
  if v_backup_status in ('not_recorded','stale','failed') then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code','BACKUP_VERIFICATION_' || upper(v_backup_status),
      'message','Host-level backup verification is missing, stale, or failed.'
    ));
  end if;

  v_snapshot := jsonb_build_object(
    'generated_at', v_now,
    'scope', jsonb_build_object(
      'institution_id', v_institution_id,
      'mode', case when v_institution_id is null then 'global' else 'institution' end
    ),
    'health', jsonb_build_object(
      'database', 'ok',
      'monitored_institutions', jsonb_array_length(v_by_institution)
    ),
    'workflow_runs', jsonb_build_object(
      'started_last_24h', v_workflow_started,
      'completed_last_24h', v_workflow_completed,
      'failed_last_24h', v_workflow_failed,
      'failure_rate_percent', case
        when v_workflow_started = 0 then 0
        else round((v_workflow_failed::numeric * 100) / v_workflow_started, 2)
      end,
      'stale_running', v_workflow_stale
    ),
    'notifications', jsonb_build_object(
      'pending', v_notifications_pending,
      'claimed', v_notifications_claimed,
      'dead_letter', v_notifications_dead,
      'oldest_pending_minutes', v_notifications_oldest_minutes
    ),
    'incidents', jsonb_build_object(
      'open', v_incidents_open,
      'acknowledged', v_incidents_ack,
      'critical_open', v_incidents_critical
    ),
    'waitlist', jsonb_build_object(
      'waiting', v_waitlist_waiting,
      'oldest_waiting_hours', v_waitlist_oldest_hours
    ),
    'marks', jsonb_build_object(
      'draft_batches', v_marks_drafts,
      'stale_drafts', v_marks_stale_drafts,
      'overdue_sections', v_marks_overdue_sections
    ),
    'dashboard_refresh', jsonb_build_object(
      'pending_runs', v_dashboard_pending,
      'automatic_google_sheets_refresh_deferred', true
    ),
    'backup', jsonb_build_object(
      'status', v_backup_status,
      'last_verified_at', v_backup_verified_at,
      'age_hours', v_backup_age_hours,
      'required_max_age_hours', v_backup_max_age_hours,
      'host_execution_owned_by_powershell', true
    ),
    'retention', jsonb_build_object(
      'workflow_runs_older_than_days', v_old_workflow_runs,
      'workflow_run_days', v_retention_workflow_days,
      'incident_events_older_than_days', v_old_incident_events,
      'incident_event_days', v_retention_incident_days,
      'delivery_records_older_than_days', v_old_delivery_records,
      'delivery_record_days', v_retention_delivery_days,
      'automatic_deletion_enabled', false
    ),
    'latest_monitoring_run', (
      select jsonb_build_object(
        'workflow_run_id', wr.id,
        'n8n_execution_id', wr.n8n_execution_id,
        'run_status', wr.run_status,
        'started_at', wr.started_at,
        'finished_at', wr.finished_at,
        'correlation_id', wr.correlation_id,
        'output_summary', wr.output_summary
      )
      from ops.workflow_runs wr
      where wr.workflow_code = '09-operations-monitoring'
      order by wr.started_at desc
      limit 1
    ),
    'latest_maintenance_run', (
      select jsonb_build_object(
        'maintenance_run_id', mr.id,
        'job_status', mr.job_status,
        'started_at', mr.started_at,
        'completed_at', mr.completed_at,
        'correlation_id', mr.correlation_id,
        'metrics', mr.metrics
      )
      from ops.maintenance_runs mr
      where mr.operation = 'operations.maintenance.apply'
      order by mr.started_at desc
      limit 1
    ),
    'by_institution', v_by_institution
  );

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    null,
    v_snapshot,
    v_warnings
  );
exception when others then
  return app.exception_rpc_error(
    v_operation,
    coalesce(v_correlation_id, gen_random_uuid()),
    sqlerrm
  );
end;
$function$;

create or replace function public.rpc_apply_scheduled_maintenance(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_operation text := 'operations.maintenance.apply';
  v_correlation_id uuid;
  v_idempotency_key text := nullif(p_request->>'idempotency_key','');
  v_dry_run boolean := lower(coalesce(p_request#>>'{payload,dry_run}','false')) = 'true';

  v_stale_claim_minutes integer := 15;
  v_stale_draft_days integer := 90;
  v_notification_backlog_threshold integer := 10;
  v_waitlist_threshold integer := 5;
  v_overdue_marks_threshold integer := 1;
  v_open_incident_threshold integer := 1;

  v_released_claims integer := 0;
  v_dead_lettered integer := 0;
  v_stale_drafts integer := 0;
  v_alert_candidates integer := 0;
  v_alerts_created integer := 0;
  v_alerts_suppressed integer := 0;
  v_inserted integer := 0;

  v_pending bigint;
  v_dead bigint;
  v_open bigint;
  v_waiting bigint;
  v_overdue bigint;
  v_recipient_email text;
  v_recipient_name text;

  v_run_id uuid;
  v_existing_metrics jsonb;
  v_metrics jsonb;
  v_now timestamptz := now();
  v_institution record;
begin
  perform app.require_service();

  if coalesce(p_request->>'correlation_id','') !~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return app.rpc_error(
      v_operation,
      gen_random_uuid(),
      'VALIDATION_CORRELATION_UUID_INVALID',
      'The maintenance correlation identifier is invalid.',
      false
    );
  end if;
  v_correlation_id := (p_request->>'correlation_id')::uuid;

  if coalesce(p_request#>>'{payload,stale_claim_minutes}','') ~ '^[0-9]+$' then
    v_stale_claim_minutes := least(
      greatest((p_request#>>'{payload,stale_claim_minutes}')::integer, 5),
      1440
    );
  end if;
  if coalesce(p_request#>>'{payload,stale_draft_days}','') ~ '^[0-9]+$' then
    v_stale_draft_days := least(
      greatest((p_request#>>'{payload,stale_draft_days}')::integer, 30),
      3650
    );
  end if;
  if coalesce(p_request#>>'{payload,notification_backlog_threshold}','') ~ '^[0-9]+$' then
    v_notification_backlog_threshold := least(
      greatest((p_request#>>'{payload,notification_backlog_threshold}')::integer, 1),
      100000
    );
  end if;
  if coalesce(p_request#>>'{payload,waitlist_threshold}','') ~ '^[0-9]+$' then
    v_waitlist_threshold := least(
      greatest((p_request#>>'{payload,waitlist_threshold}')::integer, 1),
      100000
    );
  end if;
  if coalesce(p_request#>>'{payload,overdue_marks_threshold}','') ~ '^[0-9]+$' then
    v_overdue_marks_threshold := least(
      greatest((p_request#>>'{payload,overdue_marks_threshold}')::integer, 1),
      100000
    );
  end if;
  if coalesce(p_request#>>'{payload,open_incident_threshold}','') ~ '^[0-9]+$' then
    v_open_incident_threshold := least(
      greatest((p_request#>>'{payload,open_incident_threshold}')::integer, 1),
      100000
    );
  end if;

  select mr.id, mr.metrics
  into v_run_id, v_existing_metrics
  from ops.maintenance_runs mr
  where mr.operation = v_operation
    and mr.correlation_id = v_correlation_id
  limit 1;

  if found then
    return app.rpc_success(
      v_operation,
      v_correlation_id,
      v_idempotency_key,
      jsonb_build_object(
        'maintenance_run_id', v_run_id,
        'replayed', true,
        'dry_run', false,
        'metrics', coalesce(v_existing_metrics, '{}'::jsonb)
      )
    );
  end if;

  if v_dry_run then
    select count(*) into v_released_claims
    from ops.notification_outbox no
    where no.job_status = 'claimed'
      and no.claimed_at < v_now - make_interval(mins => v_stale_claim_minutes)
      and no.attempt_count < no.max_attempts;

    select count(*) into v_dead_lettered
    from ops.notification_outbox no
    where no.job_status in ('pending','claimed','failed')
      and no.attempt_count >= no.max_attempts;

    select count(*) into v_stale_drafts
    from public.marks_batches mb
    where mb.batch_status = 'draft'
      and mb.created_at < v_now - make_interval(days => v_stale_draft_days);
  else
    update ops.notification_outbox
    set job_status = 'pending',
        claimed_at = null,
        claimed_by = null,
        available_at = v_now
    where job_status = 'claimed'
      and claimed_at < v_now - make_interval(mins => v_stale_claim_minutes)
      and attempt_count < max_attempts;
    get diagnostics v_released_claims = row_count;

    update ops.notification_outbox
    set job_status = 'dead_letter',
        completed_at = coalesce(completed_at, v_now)
    where job_status in ('pending','claimed','failed')
      and attempt_count >= max_attempts;
    get diagnostics v_dead_lettered = row_count;

    update public.marks_batches
    set batch_status = 'superseded',
        finalized_at = coalesce(finalized_at, v_now)
    where batch_status = 'draft'
      and created_at < v_now - make_interval(days => v_stale_draft_days);
    get diagnostics v_stale_drafts = row_count;
  end if;

  for v_institution in
    select i.id, i.code, i.name
    from public.institutions i
    where i.status = 'active'
    order by i.code
  loop
    select count(*) into v_pending
    from ops.notification_outbox no
    where no.institution_id = v_institution.id
      and no.job_status = 'pending';

    select count(*) into v_dead
    from ops.notification_outbox no
    where no.institution_id = v_institution.id
      and no.job_status = 'dead_letter';

    select count(*) into v_open
    from ops.incidents inc
    where inc.institution_id = v_institution.id
      and inc.incident_status in ('open','acknowledged');

    select count(*) into v_waiting
    from public.waitlist_entries w
    where w.institution_id = v_institution.id
      and w.waitlist_status = 'waiting';

    select count(*) into v_overdue
    from public.sections s
    join public.course_offerings co
      on co.id = s.offering_id
     and co.institution_id = s.institution_id
    join public.terms t
      on t.id = co.term_id
     and t.institution_id = co.institution_id
    where s.institution_id = v_institution.id
      and s.status in ('open','closed','completed')
      and t.ends_on < current_date
      and not exists (
        select 1 from public.marks_batches mb
        where mb.institution_id = s.institution_id
          and mb.section_id = s.id
          and mb.batch_status in ('finalized','approved')
      );

    if v_pending >= v_notification_backlog_threshold
       or v_dead > 0
       or v_open >= v_open_incident_threshold
       or v_waiting >= v_waitlist_threshold
       or v_overdue >= v_overdue_marks_threshold then

      v_alert_candidates := v_alert_candidates + 1;
      v_recipient_email := null;
      v_recipient_name := null;

      select sp.email, sp.full_name
      into v_recipient_email, v_recipient_name
      from public.role_assignments ra
      join public.staff_profiles sp on sp.id = ra.staff_profile_id
      where ra.institution_id = v_institution.id
        and ra.role in ('registrar','administrator','campus_administrator')
        and ra.status = 'active'
        and ra.valid_from <= v_now
        and (ra.valid_to is null or ra.valid_to > v_now)
        and sp.status = 'active'
      order by
        case ra.role
          when 'registrar' then 1
          when 'administrator' then 2
          else 3
        end,
        lower(sp.email)
      limit 1;

      if v_recipient_email is null then
        select sp.email, sp.full_name
        into v_recipient_email, v_recipient_name
        from public.role_assignments ra
        join public.staff_profiles sp on sp.id = ra.staff_profile_id
        where ra.institution_id is null
          and ra.role = 'super_administrator'
          and ra.status = 'active'
          and ra.valid_from <= v_now
          and (ra.valid_to is null or ra.valid_to > v_now)
          and sp.status = 'active'
        order by lower(sp.email)
        limit 1;
      end if;

      if v_recipient_email is null then
        v_alerts_suppressed := v_alerts_suppressed + 1;
      elsif not v_dry_run then
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
          idempotency_key,
          job_status,
          priority,
          available_at
        )
        values (
          v_institution.id,
          null,
          'email',
          'operations.monitoring.alert',
          v_recipient_email,
          v_recipient_name,
          'SIS operations alert — ' || v_institution.code,
          'operations-monitoring-alert',
          jsonb_build_object(
            'institution_code', v_institution.code,
            'institution_name', v_institution.name,
            'notification_pending', v_pending,
            'notification_dead_letter', v_dead,
            'unresolved_incidents', v_open,
            'waiting_students', v_waiting,
            'overdue_marks_sections', v_overdue,
            'generated_at', v_now,
            'message', 'Review the SIS operations dashboard and resolve actionable backlogs.'
          ),
          v_correlation_id,
          'operations-monitoring:' || v_institution.id::text || ':' ||
            to_char((v_now at time zone 'UTC')::date, 'YYYYMMDD'),
          'pending',
          25,
          v_now
        )
        on conflict (
          institution_id,
          channel,
          notification_type,
          idempotency_key
        ) do nothing;
        get diagnostics v_inserted = row_count;
        v_alerts_created := v_alerts_created + v_inserted;
      end if;
    end if;
  end loop;

  v_metrics := jsonb_build_object(
    'released_notification_claims', v_released_claims,
    'dead_lettered_notifications', v_dead_lettered,
    'superseded_stale_marks_drafts', v_stale_drafts,
    'alert_candidates', v_alert_candidates,
    'alerts_created', v_alerts_created,
    'alerts_suppressed_no_recipient', v_alerts_suppressed,
    'thresholds', jsonb_build_object(
      'stale_claim_minutes', v_stale_claim_minutes,
      'stale_draft_days', v_stale_draft_days,
      'notification_backlog', v_notification_backlog_threshold,
      'waitlist', v_waitlist_threshold,
      'overdue_marks', v_overdue_marks_threshold,
      'open_incidents', v_open_incident_threshold
    )
  );

  if not v_dry_run then
    insert into ops.maintenance_runs (
      operation,
      correlation_id,
      job_status,
      metrics,
      completed_at
    )
    values (
      v_operation,
      v_correlation_id,
      'completed',
      v_metrics,
      v_now
    )
    returning id into v_run_id;
  end if;

  return app.rpc_success(
    v_operation,
    v_correlation_id,
    v_idempotency_key,
    jsonb_build_object(
      'maintenance_run_id', v_run_id,
      'replayed', false,
      'dry_run', v_dry_run,
      'metrics', v_metrics
    )
  );
exception when others then
  return app.exception_rpc_error(
    v_operation,
    coalesce(v_correlation_id, gen_random_uuid()),
    sqlerrm
  );
end;
$function$;

revoke all on function public.rpc_get_operations_snapshot(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.rpc_apply_scheduled_maintenance(jsonb)
  from public, anon, authenticated, service_role;

grant execute on function public.rpc_get_operations_snapshot(jsonb)
  to authenticated, service_role;
grant execute on function public.rpc_apply_scheduled_maintenance(jsonb)
  to service_role;

comment on function public.rpc_get_operations_snapshot(jsonb) is
  'Returns a zero-safe global or institution-scoped operational monitoring snapshot. Global authenticated access requires super administrator authorization.';

comment on function public.rpc_apply_scheduled_maintenance(jsonb) is
  'Service-role-only bounded maintenance, operational alert creation and durable maintenance-run recording. Host commands and record deletion are excluded.';

commit;
