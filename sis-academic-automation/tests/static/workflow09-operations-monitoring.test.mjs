import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const file = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(file), '..', '..');
const failures = [];
let passed = 0;
const check = (condition, message) => {
  if (condition) passed += 1;
  else failures.push(message);
};
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');
const exists = (relative) => fs.existsSync(path.join(root, relative));

const required = [
  'workflows/09-operations-monitoring.json',
  'database/migrations/20260721000300_phase4_workflow09_operations_monitoring.sql',
  'database/queries/workflow09-contract-snapshot.sql',
  'database/queries/workflow09-verification.sql',
  'database/tests/workflow09-operations-monitoring.sql',
  'scripts/Install-Workflow09OperationsMonitoring.ps1',
  'scripts/Test-Workflow09Static.ps1',
  'scripts/Copy-Workflow09ContractSnapshot.ps1',
  'scripts/Copy-Workflow09Migration.ps1',
  'scripts/Copy-Workflow09Verification.ps1',
  'scripts/Run-Workflow09Acceptance.ps1',
  'tests/static/workflow09-operations-monitoring.test.mjs',
  'tests/acceptance/workflow09-operations-monitoring.acceptance.mjs',
  'docs/workflows/09-operations-monitoring.md',
  'docs/testing/workflow09-acceptance.md',
  'PROJECT_STATE.md',
  'CHANGELOG.md',
  'PACKAGE_MANIFEST.sha256'
];
for (const relative of required) check(exists(relative), `required file exists: ${relative}`);

const packageJson = JSON.parse(read('package.json'));
check(packageJson?.dependencies?.n8n === '2.4.0', 'package pins n8n 2.4.0');

let workflow;
try {
  workflow = JSON.parse(read('workflows/09-operations-monitoring.json'));
  check(true, 'workflow JSON parses');
} catch (error) {
  check(false, `workflow JSON parses (${error.message})`);
  workflow = { nodes: [], connections: {} };
}

check(workflow.name === 'SIS 09 — Scheduled Operations and Monitoring — Complete', 'workflow exact name');
check(workflow.active === false, 'portable workflow is inactive');
check(Array.isArray(workflow.nodes) && workflow.nodes.length >= 12, 'workflow contains complete monitoring nodes');

const nodes = workflow.nodes || [];
const byName = new Map(nodes.map((node) => [node.name, node]));
check(byName.size === nodes.length, 'node names are unique');
check(new Set(nodes.map((node) => node.id)).size === nodes.length, 'node IDs are unique');

const allowed = new Map([
  ['n8n-nodes-base.scheduleTrigger', new Set([1.3])],
  ['n8n-nodes-base.code', new Set([2])],
  ['n8n-nodes-base.httpRequest', new Set([4.3])],
  ['n8n-nodes-base.if', new Set([2.3])]
]);
for (const node of nodes) {
  check(allowed.has(node.type), `supported node type: ${node.name} (${node.type})`);
  check(allowed.get(node.type)?.has(node.typeVersion) === true, `supported typeVersion: ${node.name} (${node.typeVersion})`);
  check(typeof node.notes === 'string' && node.notes.includes('Purpose:') && node.notes.includes('Input:') && node.notes.includes('Output:') && node.notes.includes('Error behaviour:'), `complete node notes: ${node.name}`);
}
check(!nodes.some((node) => /crypto/i.test(node.type) || /executeCommand/i.test(node.type)), 'no Crypto or Execute Command nodes');
check(!nodes.some((node) => !node.type.startsWith('n8n-nodes-base.')), 'no custom or community nodes');
check(nodes.filter((node) => node.type === 'n8n-nodes-base.scheduleTrigger').length === 1, 'one schedule trigger');
const schedule = nodes.find((node) => node.type === 'n8n-nodes-base.scheduleTrigger');
check(schedule?.parameters?.rule?.interval?.[0]?.field === 'minutes' && schedule?.parameters?.rule?.interval?.[0]?.minutesInterval === 15, 'schedule interval is fifteen minutes');
check(nodes.filter((node) => node.type === 'n8n-nodes-base.webhook').length === 0, 'no public monitoring webhook');
check(nodes.filter((node) => node.type === 'n8n-nodes-base.respondToWebhook').length === 0, 'no unused response nodes');

const requiredNodeNames = [
  'Every 15 Minutes',
  'Build Monitoring Request',
  'Log Monitoring Start',
  'Apply Scheduled Maintenance',
  'Normalize Maintenance Response',
  'Maintenance Succeeded?',
  'Get Operations Snapshot',
  'Normalize Operations Snapshot',
  'Snapshot Succeeded?',
  'Log Monitoring Completion',
  'Record Snapshot Failure Incident',
  'Log Snapshot Failure',
  'Record Maintenance Failure Incident',
  'Log Maintenance Failure'
];
for (const name of requiredNodeNames) check(byName.has(name), `required node exists: ${name}`);

const allNodeNames = new Set(nodes.map((node) => node.name));
for (const [source, groups] of Object.entries(workflow.connections || {})) {
  check(allNodeNames.has(source), `connection source exists: ${source}`);
  for (const group of groups.main || []) {
    for (const edge of group || []) check(allNodeNames.has(edge.node), `connection target exists: ${edge.node}`);
  }
}

const workflowText = JSON.stringify(workflow);
check(!/gemma-unfossilised|ngrok-free\.dev/i.test(workflowText), 'no live ngrok URL');
check(!/(service[_-]?role[^A-Za-z0-9]{0,8}[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.)/.test(workflowText), 'no embedded token or service-role material');
check(!/\/rest\/v1\/(app|private|reporting|audit|ops)\//i.test(workflowText), 'no direct private-schema REST URL');
check(!/SIS_SUPABASE_ANON_KEY|SUPABASE_ANON_KEY/.test(workflowText), 'scheduled workflow does not use anon credentials');
check(!/Authorization/.test(workflowText), 'scheduled workflow does not construct bearer headers');
check(workflowText.includes('SIS Supabase Service Role'), 'exact service-role credential name is referenced');
check(!/"id"\s*:\s*"[^"]+"\s*,\s*"name"\s*:\s*"SIS Supabase Service Role"/.test(workflowText), 'no credential ID embedded');

const httpNodes = nodes.filter((node) => node.type === 'n8n-nodes-base.httpRequest');
for (const node of httpNodes) {
  check(node.parameters?.authentication === 'predefinedCredentialType', `HTTP node uses predefined credential: ${node.name}`);
  check(node.parameters?.nodeCredentialType === 'supabaseApi', `HTTP node uses Supabase credential type: ${node.name}`);
  check(node.credentials?.supabaseApi?.name === 'SIS Supabase Service Role', `HTTP node binds exact credential name: ${node.name}`);
  check(String(node.parameters?.url || '').includes('/rest/v1/rpc/rpc_'), `HTTP node calls public RPC: ${node.name}`);
  check(node.parameters?.options?.response?.response?.neverError === true, `HTTP response is normalized: ${node.name}`);
}
for (const rpc of ['rpc_apply_scheduled_maintenance','rpc_get_operations_snapshot','rpc_record_incident','rpc_log_workflow_run']) {
  check(workflowText.includes(`/rest/v1/rpc/${rpc}`), `workflow calls ${rpc}`);
}

for (const node of nodes.filter((node) => node.type === 'n8n-nodes-base.code')) {
  try {
    new Function(node.parameters.jsCode);
    check(true, `Code node JavaScript parses: ${node.name}`);
  } catch (error) {
    check(false, `Code node JavaScript parses: ${node.name} (${error.message})`);
  }
}
check(workflowText.includes('stale_claim_minutes'), 'maintenance threshold includes stale claim age');
check(workflowText.includes('stale_draft_days'), 'maintenance threshold includes stale draft age');
check(workflowText.includes('backup_max_age_hours'), 'snapshot threshold includes backup age');
check(workflowText.includes('retention_workflow_days'), 'snapshot threshold includes retention review');
check(workflowText.includes("workflow_code: '09-operations-monitoring'"), 'workflow code is stable');
check(workflowText.includes('n8n_execution_id: $execution.id'), 'n8n execution ID is preserved');
check(workflowText.includes('correlation_id'), 'correlation ID is preserved');

const migration = read('database/migrations/20260721000300_phase4_workflow09_operations_monitoring.sql');
check(/create or replace function public\.rpc_get_operations_snapshot\(p_request jsonb\)/i.test(migration), 'snapshot RPC migration exists');
check(/create or replace function public\.rpc_apply_scheduled_maintenance\(p_request jsonb\)/i.test(migration), 'maintenance RPC migration exists');
check(/grant execute on function public\.rpc_apply_scheduled_maintenance\(jsonb\)\s+to service_role/i.test(migration), 'maintenance is service-role only');
check(/grant execute on function public\.rpc_get_operations_snapshot\(jsonb\)\s+to authenticated, service_role/i.test(migration), 'snapshot is available to authorized staff and service');
check(/perform app\.require_service\(\)/i.test(migration), 'maintenance enforces service request');
check(!/\bdelete\s+from\b/i.test(migration), 'migration contains no record deletion');
check(!/execute\s+command/i.test(migration), 'migration contains no host command');
check(/operations\.monitoring\.alert/i.test(migration), 'maintenance creates operational alert outbox records');
check(/on conflict\s*\(/i.test(migration), 'monitoring alerts are deduplicated');
check(/dry_run/i.test(migration), 'maintenance supports dry-run verification');
check(/latest_monitoring_run/i.test(migration), 'snapshot exposes latest monitoring evidence');
check(/automatic_deletion_enabled', false/i.test(migration), 'retention is review-only');
check(/automatic_google_sheets_refresh_deferred', true/i.test(migration), 'deferred dashboard refresh is explicit');
check(/host_execution_owned_by_powershell', true/i.test(migration), 'backup execution boundary is explicit');

const contract = read('database/queries/workflow09-contract-snapshot.sql');
check(!/format\s*\([^)]*identity_arguments/i.test(contract), 'contract snapshot does not reparse named identity arguments');
check(/has_function_privilege\('authenticated', p\.oid, 'EXECUTE'\)/i.test(contract), 'contract privilege check uses pg_proc OID');
check(!/\b(create|alter|drop|insert|update|delete)\s+(table|into|from)\b/i.test(contract.replace(/--.*$/gm, '')), 'contract snapshot is read-only');

const verification = read('database/queries/workflow09-verification.sql');
check(verification.includes("'status'"), 'verification returns status');
check(verification.includes("'failed'"), 'verification returns failure count');
check(verification.includes('maintenance_no_delete'), 'verification checks non-destructive maintenance');
check(verification.includes('maintenance_authenticated_blocked'), 'verification checks maintenance privilege boundary');

const databaseTest = read('database/tests/workflow09-operations-monitoring.sql');
check(/begin;/i.test(databaseTest) && /rollback;/i.test(databaseTest), 'database tests are rollback-only');
check(databaseTest.includes('dry_run'), 'database tests cover dry run');
check(databaseTest.includes('MAINTENANCE_IDEMPOTENCY'), 'database tests cover replay');
check(databaseTest.includes('AUTHENTICATED_MAINTENANCE_DENIAL'), 'database tests cover service-only maintenance');

const state = read('PROJECT_STATE.md');
check(state.includes('Workflow 07') && state.includes('frozen'), 'project state records Workflow 07 freeze');
check(state.includes('Workflow 09'), 'project state records Workflow 09');
const changelog = read('CHANGELOG.md');
check(changelog.includes('Workflow 09'), 'changelog records Workflow 09');

const manifest = read('PACKAGE_MANIFEST.sha256');
check(!/(^|[\\/])\.env($|\s)/mi.test(manifest), 'package manifest excludes .env');
check(!/portal[\\/]config\.local\.js/mi.test(manifest), 'package manifest excludes config.local.js');
check(!/(^|[\\/])\.runtime([\\/]|$)/mi.test(manifest), 'package manifest excludes runtime files');

if (failures.length) {
  console.error('Workflow 09 static validation: FAIL');
  console.error(`Checks passed: ${passed}`);
  console.error(`Checks failed: ${failures.length}`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log('Workflow 09 static validation: PASS');
console.log(`Checks passed: ${passed}`);
