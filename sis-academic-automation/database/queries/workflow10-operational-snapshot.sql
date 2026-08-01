-- Workflow 10 read-only operational snapshot.
-- Returns counts and safe key names only; no request bodies, email bodies, tokens or error values.
with workflow_status as (
  select run_status::text as status, count(*)::bigint as count
  from ops.workflow_runs
  where started_at >= timezone('utc', now()) - interval '24 hours'
  group by run_status
), incident_status as (
  select incident_status::text as status, severity::text as severity, count(*)::bigint as count
  from ops.incidents
  group by incident_status, severity
), outbox_status as (
  select job_status::text as status, count(*)::bigint as count
  from ops.notification_outbox
  group by job_status
), recent_workflows as (
  select workflow_code, max(started_at) as last_started_at
  from ops.workflow_runs
  where workflow_code is not null
  group by workflow_code
  order by workflow_code
), incident_detail_keys as (
  select distinct key
  from ops.incident_events ie
  cross join lateral jsonb_object_keys(coalesce(ie.sanitized_details, '{}'::jsonb)) as k(key)
  where ie.occurred_at >= timezone('utc', now()) - interval '30 days'
    and k.key !~* '(token|authorization|apikey|api_key|password|secret|cookie|header|body)'
  order by k.key
)
select jsonb_build_object(
  'snapshot', 'workflow10.operational',
  'checked_at_utc', timezone('utc', now()),
  'workflow_runs_last_24h', coalesce((select jsonb_object_agg(ws.status, ws.count) from workflow_status ws), '{}'::jsonb),
  'incidents', coalesce((select jsonb_agg(to_jsonb(i) order by i.status, i.severity) from incident_status i), '[]'::jsonb),
  'notification_outbox', coalesce((select jsonb_object_agg(os.status, os.count) from outbox_status os), '{}'::jsonb),
  'recent_workflow_codes', coalesce((select jsonb_agg(to_jsonb(rw) order by rw.workflow_code) from recent_workflows rw), '[]'::jsonb),
  'safe_incident_detail_keys', coalesce((select jsonb_agg(k.key order by k.key) from incident_detail_keys k), '[]'::jsonb)
) as workflow10_operational_snapshot;
