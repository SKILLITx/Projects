import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const failures = [];
const passes = [];
const check = (condition, message) => (condition ? passes : failures).push(message);
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

const packageJson = JSON.parse(read('package.json'));
check(packageJson.dependencies?.n8n === '2.4.0', 'package.json pins n8n exactly to 2.4.0');

const workflow = JSON.parse(read('workflows/07-admin-dashboard.json'));
check(workflow.name === 'SIS 07 — Administrative Search and Basic Dashboard — Complete', 'workflow name is exact');
check(workflow.active === false, 'portable workflow is inactive before import');

const nodes = workflow.nodes || [];
const nodeNames = new Set(nodes.map((node) => node.name));
check(nodeNames.size === nodes.length, 'node names are unique');

const supported = new Map([
  ['n8n-nodes-base.webhook', new Set([2])],
  ['n8n-nodes-base.respondToWebhook', new Set([1.1])],
  ['n8n-nodes-base.httpRequest', new Set([4.3])],
  ['n8n-nodes-base.code', new Set([2])],
  ['n8n-nodes-base.if', new Set([2.3])]
]);
for (const node of nodes) {
  check(supported.has(node.type), `supported node type: ${node.name} (${node.type})`);
  if (supported.has(node.type)) check(supported.get(node.type).has(node.typeVersion), `supported typeVersion: ${node.name} (${node.typeVersion})`);
  check(typeof node.notes === 'string' && /Purpose:/.test(node.notes) && /Input:/.test(node.notes) && /Output:/.test(node.notes) && /Error(?: behaviour)?:/.test(node.notes), `node documentation is complete: ${node.name}`);
}
check(!nodes.some((node) => /crypto/i.test(node.type) || /crypto/i.test(node.name)), 'no Crypto node');
check(!nodes.some((node) => /executeCommand/i.test(node.type) || /Execute Command/i.test(node.name)), 'no Execute Command node');

const webhookNodes = nodes.filter((node) => node.type === 'n8n-nodes-base.webhook');
const routes = webhookNodes.map((node) => `${node.parameters?.httpMethod}:${node.parameters?.path}`);
check(routes.length === 2, 'exactly two webhook triggers');
check(new Set(routes).size === routes.length, 'webhook method/path pairs are unique');
check(routes.includes('POST:staff/rpc_search_students'), 'student search route is exact');
check(routes.includes('POST:staff/rpc_get_dashboard_snapshot'), 'dashboard route is exact');
for (const node of webhookNodes) check(node.parameters?.responseMode === 'responseNode', `webhook uses explicit response node: ${node.name}`);

for (const [source, groups] of Object.entries(workflow.connections || {})) {
  check(nodeNames.has(source), `connection source exists: ${source}`);
  for (const outputs of groups.main || []) {
    for (const edge of outputs || []) check(nodeNames.has(edge.node), `connection target exists: ${source} -> ${edge.node}`);
  }
}

const adjacency = new Map();
for (const node of nodes) adjacency.set(node.name, []);
for (const [source, groups] of Object.entries(workflow.connections || {})) {
  for (const outputs of groups.main || []) for (const edge of outputs || []) adjacency.get(source).push(edge.node);
}
function terminalPaths(start) {
  const terminals = [];
  const stack = [[start, new Set()]];
  while (stack.length) {
    const [name, seen] = stack.pop();
    if (seen.has(name)) { failures.push(`cycle detected from ${start} at ${name}`); continue; }
    const nextSeen = new Set(seen); nextSeen.add(name);
    const next = adjacency.get(name) || [];
    if (!next.length) { terminals.push(name); continue; }
    for (const target of next) stack.push([target, nextSeen]);
  }
  return terminals;
}
for (const webhook of webhookNodes) {
  const terminals = terminalPaths(webhook.name);
  check(terminals.length > 0, `branch has terminal paths: ${webhook.name}`);
  for (const terminal of terminals) {
    const node = nodes.find((item) => item.name === terminal);
    check(node?.type === 'n8n-nodes-base.respondToWebhook', `branch terminal is Respond to Webhook: ${webhook.name} -> ${terminal}`);
  }
}

const workflowText = JSON.stringify(workflow);
check(!/service[_-]?role\s*[:=]\s*[A-Za-z0-9._-]{20,}/i.test(workflowText), 'no service-role material is embedded');
check(!/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/.test(workflowText), 'no JWT is embedded');
check(!/https?:\/\/[A-Za-z0-9-]+\.ngrok-free\.dev/.test(workflowText), 'no live ngrok URL is hardcoded');
check(!/\/rest\/v1\/(app|private|reporting|audit|ops)\//i.test(workflowText), 'no direct private-schema REST URL');
check(!/={=/.test(workflowText), 'n8n expressions do not contain malformed ={= prefixes');

const businessNodes = nodes.filter((node) => /Supabase RPC — (Search Students|Dashboard Snapshot)/.test(node.name));
check(businessNodes.length === 2, 'two business RPC nodes exist');
for (const node of businessNodes) {
  check(!node.credentials && !node.parameters?.authentication, `business RPC uses staff JWT rather than service credential: ${node.name}`);
  const text = JSON.stringify(node.parameters);
  check(/Authorization/.test(text) && /authHeader/.test(text), `business RPC forwards verified staff bearer token: ${node.name}`);
  check(/\/rest\/v1\/rpc\/rpc_(search_students|get_dashboard_snapshot)/.test(text), `business RPC calls a public wrapper: ${node.name}`);
}
const logNodes = nodes.filter((node) => /^Log /.test(node.name));
check(logNodes.length >= 6, 'durable logging nodes exist for success and failure outcomes');
for (const node of logNodes) check(node.credentials?.supabaseApi?.name === 'SIS Supabase Service Role', `logging credential name is portable and exact: ${node.name}`);

const codeNodes = nodes.filter((node) => node.type === 'n8n-nodes-base.code');
for (const node of codeNodes) {
  try { new vm.Script(`(function(){${node.parameters.jsCode}\n})`); check(true, `Code node parses: ${node.name}`); }
  catch (error) { check(false, `Code node parses: ${node.name} (${error.message})`); }
}
const normalizerSource = codeNodes.filter((node) => /^Normalize .* Request$/.test(node.name)).map((node) => node.parameters.jsCode).join('\n');
check(normalizerSource.includes("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"), 'UUID validation uses PostgreSQL-compatible canonical shape');
check(normalizerSource.includes("Math.min(Math.max(limitInput || 25,1),25)"), 'student search page size is bounded to 25');

const html = read('portal/index.html');
const app = read('portal/app.js');
const css = read('portal/styles.css');
check(/id="student-search-type"/.test(html), 'portal has visible search-type selector');
check(/value="identity_reference"/.test(html), 'portal supports exact CNIC/identity search');
check(/id="student-search-clear"/.test(html), 'portal has a Clear button');
check(/id="dashboard-term-select"/.test(html) && !/Term ID \(optional\)/i.test(html), 'portal uses a visible term selector, not a raw term-ID field');
check(!/id="student-search-limit"|id="student-search-status-filter"/.test(html), 'obsolete Workflow 07 controls are removed');
check(/rpc_search_students/.test(app) && /rpc_get_dashboard_snapshot/.test(app), 'portal calls both Workflow 07 webhooks');
check(/authorization.*Bearer|Bearer.*access_token/is.test(app), 'portal sends the authenticated access token without displaying it');
check(/sanitizeDebugValue/.test(app), 'portal sanitizes support output');
check(!/student\.student_id/.test(app) && !/Internal UUID|Student UUID|Institution UUID|Campus UUID|Program UUID/i.test(html), 'portal does not render internal student/institution/campus/program identifiers');
check(!/service[_-]?role/i.test(html + css), 'portal UI contains no service-role material');
const manifestPath = path.join(root, 'PACKAGE_MANIFEST.sha256');
const manifestText = fs.existsSync(manifestPath) ? fs.readFileSync(manifestPath, 'utf8') : '';
check(fs.existsSync(manifestPath) && !/(?:^|\s)portal[\\/]config\.local\.js(?:\s|$)/mi.test(manifestText), 'config.local.js is excluded from the package manifest while remaining allowed in an installed repository');

const contractSnapshot = read('database/queries/workflow07-contract-snapshot.sql');
const hostedVerification = read('database/queries/workflow07-verification.sql');
for (const [label, sql] of [['contract snapshot', contractSnapshot], ['hosted verification', hostedVerification]]) {
  check(/has_function_privilege\(\s*'authenticated',\s*p\.oid,\s*'EXECUTE'\s*\)/is.test(sql), `${label} uses the pg_proc OID for authenticated privilege checks`);
  check(/has_function_privilege\(\s*'service_role',\s*p\.oid,\s*'EXECUTE'\s*\)/is.test(sql), `${label} uses the pg_proc OID for service-role privilege checks`);
  check(!/has_function_privilege\([\s\S]*?format\('%I\.%I\(%s\)'/i.test(sql), `${label} does not reparse named identity arguments as a regprocedure signature`);
}

const migration = read('database/migrations/20260721000200_phase4_workflow07_admin_search_dashboard_complete.sql');
check(/create or replace function public\.rpc_search_students\(p_request jsonb\)/i.test(migration), 'search RPC migration exists');
check(/create or replace function public\.rpc_get_dashboard_snapshot\(p_request jsonb\)/i.test(migration), 'dashboard RPC migration exists');
check(/revoke all on function public\.rpc_search_students\(jsonb\) from public, anon, service_role/i.test(migration), 'search RPC service-role/public grants are revoked');
check(/grant execute on function public\.rpc_search_students\(jsonb\) to authenticated/i.test(migration), 'search RPC is granted to authenticated');
check(/case when v_search_type = 'identity_reference' then v_identity_masked else v_query end/i.test(migration), 'identity query is masked in the response');
check(!/insert\s+into\s+(public\.)?(enrollments|marks_batches|course_results|transcript_requests)/i.test(migration), 'Workflow 07 migration has no write-side business effects');

const required = [
  'database/queries/workflow07-contract-snapshot.sql',
  'database/queries/workflow07-verification.sql',
  'database/tests/workflow07-admin-dashboard.sql',
  'scripts/Install-Workflow07AdminDashboard.ps1',
  'scripts/Test-Workflow07Static.ps1',
  'scripts/Copy-Workflow07ContractSnapshot.ps1',
  'scripts/Copy-Workflow07Migration.ps1',
  'scripts/Copy-Workflow07Verification.ps1',
  'scripts/Run-Workflow07Acceptance.ps1',
  'tests/acceptance/workflow07-admin-dashboard.acceptance.mjs',
  'docs/workflows/07-admin-dashboard.md',
  'docs/testing/workflow07-acceptance.md'
];
for (const relative of required) check(fs.existsSync(path.join(root, relative)), `required deliverable exists: ${relative}`);

console.log(`Workflow 07 static validation: ${failures.length ? 'FAIL' : 'PASS'}`);
console.log(`Checks passed: ${passes.length}`);
if (failures.length) {
  console.error(`Checks failed: ${failures.length}`);
  failures.forEach((failure) => console.error(`- ${failure}`));
  process.exit(1);
}
