import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const email = process.env.S09_STAFF_EMAIL || 'zaidrizwan.278@gmail.com';
const password = process.env.S09_STAFF_PASSWORD || '';
const requireLive = String(process.env.S09_REQUIRE_LIVE || 'true').toLowerCase() !== 'false';
if (!password) throw new Error('S09_STAFF_PASSWORD is required. Use scripts/Run-Workflow09Acceptance.ps1 so the password is prompted securely.');

function loadPortalConfig() {
  const localPath = path.join(root, 'portal', 'config.local.js');
  if (!fs.existsSync(localPath)) throw new Error('portal/config.local.js was not found in the installed repository.');
  const sandbox = { window: {} };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(localPath, 'utf8'), sandbox, { filename: localPath });
  return sandbox.window.SIS_PORTAL_CONFIG || null;
}
const config = loadPortalConfig();
if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
  throw new Error('config.local.js must define supabaseUrl and supabaseAnonKey.');
}
if (String(config.supabaseAnonKey).toLowerCase().includes('service_role')) {
  throw new Error('A service-role key must never be used by this acceptance test.');
}
const supabaseBase = String(config.supabaseUrl).replace(/\/$/, '');
const evidence = {
  generated_at: new Date().toISOString(),
  actor_email: email,
  require_live_monitoring_run: requireLive,
  tests: [],
  coverage_notes: []
};
let failures = 0;
function record(name, passed, details = {}) {
  evidence.tests.push({
    name,
    passed,
    http_status: details.http_status ?? null,
    correlation_id: details.correlation_id ?? null,
    n8n_execution_id: details.n8n_execution_id ?? null,
    note: details.note ?? null
  });
  console.log(`${passed ? 'PASS' : 'FAIL'}: ${name}${details.note ? ` — ${details.note}` : ''}`);
  if (!passed) failures += 1;
}
async function fetchJson(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Number(config.requestTimeoutMs || 30000));
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    const text = await response.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = { invalid_json: true }; }
    return { status: response.status, body };
  } finally {
    clearTimeout(timer);
  }
}
async function signIn() {
  const result = await fetchJson(`${supabaseBase}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: config.supabaseAnonKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  if (result.status !== 200 || !result.body?.access_token) {
    throw new Error(`Supabase sign-in failed with HTTP ${result.status}.`);
  }
  return result.body.access_token;
}
function envelope(operation, institutionId, payload = {}) {
  const correlationId = crypto.randomUUID();
  return {
    operation,
    correlation_id: correlationId,
    idempotency_key: `acceptance:${operation}:${correlationId}`,
    source: { channel: 'acceptance_test' },
    context: { institution_id: institutionId || null, campus_id: null },
    submitted_at: new Date().toISOString(),
    payload
  };
}
async function callRpc(name, request, token) {
  return fetchJson(`${supabaseBase}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: config.supabaseAnonKey,
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      prefer: 'return=representation'
    },
    body: JSON.stringify({ p_request: request })
  });
}
async function restRows(table, query, token) {
  const result = await fetchJson(`${supabaseBase}/rest/v1/${table}?${query}`, {
    headers: { apikey: config.supabaseAnonKey, authorization: `Bearer ${token}`, accept: 'application/json' }
  });
  if (result.status !== 200 || !Array.isArray(result.body)) {
    throw new Error(`Fixture lookup failed for ${table} with HTTP ${result.status}.`);
  }
  return result.body;
}

const token = await signIn();
const institutions = await restRows('institutions', 'select=id,code,name&code=eq.DMU&limit=1', token);
if (!institutions[0]) throw new Error('The DMU pilot institution fixture was not found.');
const dmu = institutions[0];

const scoped = await callRpc(
  'rpc_get_operations_snapshot',
  envelope('operations.snapshot', dmu.id, {
    backup_max_age_hours: 48,
    retention_workflow_days: 90,
    retention_incident_days: 180,
    retention_delivery_days: 180
  }),
  token
);
const data = scoped.body?.data || {};
const shapeOk =
  scoped.status === 200 &&
  scoped.body?.success === true &&
  data?.scope?.institution_id === dmu.id &&
  typeof data?.workflow_runs === 'object' &&
  typeof data?.notifications === 'object' &&
  typeof data?.incidents === 'object' &&
  typeof data?.waitlist === 'object' &&
  typeof data?.marks === 'object' &&
  typeof data?.backup === 'object' &&
  typeof data?.retention === 'object' &&
  Array.isArray(data?.by_institution);
record('authorized DMU operations snapshot', shapeOk, {
  http_status: scoped.status,
  correlation_id: scoped.body?.correlation_id || null,
  note: shapeOk ? `pending=${Number(data.notifications.pending || 0)}; incidents=${Number(data.incidents.open || 0) + Number(data.incidents.acknowledged || 0)}; backup=${String(data.backup.status || 'unknown')}` : null
});

const numericValues = [
  data?.workflow_runs?.started_last_24h,
  data?.workflow_runs?.completed_last_24h,
  data?.workflow_runs?.failed_last_24h,
  data?.notifications?.pending,
  data?.notifications?.claimed,
  data?.notifications?.dead_letter,
  data?.incidents?.open,
  data?.incidents?.acknowledged,
  data?.waitlist?.waiting,
  data?.marks?.draft_batches,
  data?.marks?.stale_drafts,
  data?.marks?.overdue_sections
];
record('snapshot metrics are zero-safe numbers', numericValues.every((value) => typeof value === 'number'), {
  http_status: scoped.status,
  correlation_id: scoped.body?.correlation_id || null
});

const globalResult = await callRpc(
  'rpc_get_operations_snapshot',
  envelope('operations.snapshot', null, {
    backup_max_age_hours: 48,
    retention_workflow_days: 90,
    retention_incident_days: 180,
    retention_delivery_days: 180
  }),
  token
);
record('super administrator global snapshot', globalResult.status === 200 && globalResult.body?.success === true && globalResult.body?.data?.scope?.mode === 'global', {
  http_status: globalResult.status,
  correlation_id: globalResult.body?.correlation_id || null
});

const latestRun = globalResult.body?.data?.latest_monitoring_run || null;
const latestMaintenance = globalResult.body?.data?.latest_maintenance_run || null;
if (requireLive) {
  record('latest n8n monitoring run completed', latestRun?.run_status === 'completed' && Boolean(latestRun?.n8n_execution_id), {
    http_status: globalResult.status,
    correlation_id: latestRun?.correlation_id || null,
    n8n_execution_id: latestRun?.n8n_execution_id || null,
    note: latestRun ? `status=${latestRun.run_status}` : 'No Workflow 09 run was found.'
  });
  record('latest maintenance run completed', latestMaintenance?.job_status === 'completed' && Boolean(latestMaintenance?.maintenance_run_id), {
    http_status: globalResult.status,
    correlation_id: latestMaintenance?.correlation_id || null,
    note: latestMaintenance ? `status=${latestMaintenance.job_status}` : 'No maintenance run was found.'
  });
} else {
  evidence.coverage_notes.push('Live n8n execution verification was skipped by S09_REQUIRE_LIVE=false.');
}

const invalid = await callRpc(
  'rpc_get_operations_snapshot',
  {
    ...envelope('operations.snapshot', null, {}),
    context: { institution_id: 'not-a-uuid', campus_id: null }
  },
  token
);
record('invalid institution UUID is sanitized', invalid.status === 200 && invalid.body?.success === false && invalid.body?.error?.code === 'VALIDATION_INSTITUTION_UUID_INVALID', {
  http_status: invalid.status,
  correlation_id: invalid.body?.correlation_id || null
});

const deniedMaintenance = await callRpc(
  'rpc_apply_scheduled_maintenance',
  envelope('operations.maintenance.apply', null, { dry_run: true }),
  token
);
record('authenticated browser actor cannot run maintenance', [401, 403, 404].includes(deniedMaintenance.status) || deniedMaintenance.body?.error?.code === 'AUTH_SERVICE_ROLE_REQUIRED', {
  http_status: deniedMaintenance.status,
  correlation_id: deniedMaintenance.body?.correlation_id || null
});

evidence.coverage_notes.push('Host backup execution remains outside n8n. Workflow 09 reports the latest backup.verify maintenance record but does not run backup commands.');
evidence.coverage_notes.push('Automatic Google Sheets dashboard refresh and retention deletion remain deferred and are reported explicitly in the snapshot.');

const evidenceDirectory = path.join(root, 'evidence');
fs.mkdirSync(evidenceDirectory, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const evidencePath = path.join(evidenceDirectory, `workflow09-acceptance-${stamp}.json`);
fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2) + '\n', 'utf8');
console.log(`Evidence written: ${path.relative(root, evidencePath)}`);
if (evidence.coverage_notes.length) {
  console.log('Coverage notes:');
  for (const note of evidence.coverage_notes) console.log(`- ${note}`);
}
if (failures) process.exit(1);
