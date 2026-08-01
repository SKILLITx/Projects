import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const modeArg = process.argv.find((item) => item.startsWith('--mode='));
const mode = (modeArg?.split('=')[1] || 'all').toLowerCase();
if (!['positive', 'negative', 'all'].includes(mode)) throw new Error('Use --mode=positive, --mode=negative, or --mode=all.');

const email = process.env.S07_STAFF_EMAIL || 'zaidrizwan.278@gmail.com';
const password = process.env.S07_STAFF_PASSWORD || '';
if (!password) throw new Error('S07_STAFF_PASSWORD is required. Use scripts/Run-Workflow07Acceptance.ps1 so the password is prompted securely.');

function loadPortalConfig() {
  const localPath = path.join(root, 'portal', 'config.local.js');
  if (!fs.existsSync(localPath)) throw new Error('portal/config.local.js was not found in the installed repository.');
  const sandbox = { window: {} };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(localPath, 'utf8'), sandbox, { filename: localPath });
  return sandbox.window.SIS_PORTAL_CONFIG || null;
}

const config = loadPortalConfig();
if (!config?.supabaseUrl || !config?.supabaseAnonKey || !config?.n8nBaseUrl) {
  throw new Error('config.local.js must define supabaseUrl, supabaseAnonKey, and the current n8nBaseUrl.');
}
if (String(config.supabaseAnonKey).toLowerCase().includes('service_role')) throw new Error('A service-role key must never be used by this acceptance test.');

const workflowBase = String(config.n8nBaseUrl).replace(/\/$/, '');
const supabaseBase = String(config.supabaseUrl).replace(/\/$/, '');
const evidence = {
  generated_at: new Date().toISOString(),
  mode,
  actor_email: email,
  workflow_base_origin: new URL(workflowBase).origin,
  tests: [],
  coverage_notes: []
};
let failureCount = 0;

function record(name, passed, details = {}) {
  const safe = {
    name,
    passed,
    http_status: details.http_status ?? null,
    correlation_id: details.correlation_id ?? null,
    n8n_execution_id: details.n8n_execution_id ?? null,
    result_count: details.result_count ?? null,
    error_code: details.error_code ?? null,
    note: details.note ?? null
  };
  evidence.tests.push(safe);
  console.log(`${passed ? 'PASS' : 'FAIL'}: ${name}${safe.note ? ` — ${safe.note}` : ''}`);
  if (!passed) failureCount += 1;
}

function base64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
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
  if (result.status !== 200 || !result.body?.access_token) throw new Error(`Supabase sign-in failed with HTTP ${result.status}.`);
  return result.body.access_token;
}

async function restRows(table, query, token) {
  const result = await fetchJson(`${supabaseBase}/rest/v1/${table}?${query}`, {
    headers: { apikey: config.supabaseAnonKey, authorization: `Bearer ${token}`, accept: 'application/json' }
  });
  if (result.status !== 200 || !Array.isArray(result.body)) throw new Error(`Fixture lookup failed for ${table} with HTTP ${result.status}.`);
  return result.body;
}

function requestEnvelope(operation, institutionId, campusId, payload) {
  const correlationId = crypto.randomUUID();
  return {
    operation,
    correlation_id: correlationId,
    idempotency_key: `acceptance:${operation}:${correlationId}`,
    source: { channel: 'acceptance_test' },
    context: { institution_id: institutionId, campus_id: campusId || null },
    submitted_at: new Date().toISOString(),
    payload
  };
}

async function callWorkflow(route, request, authorization) {
  const headers = { 'content-type': 'application/json' };
  if (authorization !== undefined) headers.authorization = authorization;
  const result = await fetchJson(`${workflowBase}/webhook/staff/${route}`, {
    method: 'POST', headers, body: JSON.stringify(request)
  });
  return result;
}

function details(result) {
  return {
    http_status: result.status,
    correlation_id: result.body?.correlation_id || null,
    n8n_execution_id: result.body?.meta?.n8n_execution_id || null,
    result_count: result.body?.data?.count ?? null,
    error_code: result.body?.error?.code || null
  };
}

const token = await signIn();
const institutions = await restRows('institutions', 'select=id,code,name&code=eq.DMU&limit=1', token);
if (!institutions[0]) throw new Error('The DMU pilot institution fixture was not found.');
const institution = institutions[0];
const campuses = await restRows('campuses', `select=id,code,name&institution_id=eq.${encodeURIComponent(institution.id)}&code=eq.ISB&limit=1`, token);
if (!campuses[0]) throw new Error('The ISB pilot campus fixture was not found.');
const campus = campuses[0];
const students = await restRows('students', `select=student_number,full_name,primary_email&institution_id=eq.${encodeURIComponent(institution.id)}&student_number=eq.DMU-0001&limit=1`, token);
const pilotStudent = students[0] || { student_number: 'DMU-0001', full_name: 'Demo University Student 01', primary_email: 'dmu.student01@example.test' };
const auth = `Bearer ${token}`;

async function runPositive() {
  const cases = [
    ['exact student number', { query: 'DMU-0001', search_type: 'student_number', limit: 25, offset: 0 }, (body) => body?.data?.students?.[0]?.student_number === 'DMU-0001'],
    ['partial student name', { query: 'Demo University Student', search_type: 'name', limit: 25, offset: 0 }, (body) => Number(body?.data?.count || 0) >= 1],
    ['student email', { query: pilotStudent.primary_email || 'dmu.student01@example.test', search_type: 'email', limit: 25, offset: 0 }, (body) => Number(body?.data?.count || 0) >= 1],
    ['exact identity reference returns only a mask', { query: 'DEMO-ID-DMU-0001', search_type: 'identity_reference', limit: 25, offset: 0 }, (body) => {
      const serialized = JSON.stringify(body);
      const masked = body?.data?.students?.[0]?.identity_reference_masked;
      return Number(body?.data?.count || 0) === 1 && typeof masked === 'string' && masked.endsWith('0001') && !serialized.includes('DEMO-ID-DMU-0001');
    }],
    ['zero-result search is successful', { query: 'NO-SUCH-STUDENT-999999', search_type: 'student_number', limit: 25, offset: 0 }, (body) => body?.success === true && body?.data?.count === 0 && Array.isArray(body?.data?.students) && body.data.students.length === 0]
  ];

  for (const [name, payload, validate] of cases) {
    const result = await callWorkflow('rpc_search_students', requestEnvelope('student.search', institution.id, campus.id, payload), auth);
    record(name, result.status === 200 && result.body?.success === true && validate(result.body), details(result));
  }

  const dashboard = await callWorkflow(
    'rpc_get_dashboard_snapshot',
    requestEnvelope('dashboard.snapshot', institution.id, campus.id, { term_id: null }),
    auth
  );
  const metrics = dashboard.body?.data?.metrics || {};
  const dashboardPassed = dashboard.status === 200 && dashboard.body?.success === true &&
    typeof metrics.students_total === 'number' && typeof metrics.average_gpa === 'number' && typeof metrics.average_cgpa === 'number' &&
    Array.isArray(dashboard.body?.data?.grade_distribution) && Array.isArray(dashboard.body?.data?.course_capacity);
  record('authorized DMU/ISB dashboard snapshot', dashboardPassed, {
    ...details(dashboard),
    note: dashboardPassed ? `students=${metrics.students_total}; average GPA=${metrics.average_gpa}; average CGPA=${metrics.average_cgpa}` : null
  });

  const hasPublishedB = (dashboard.body?.data?.grade_distribution || []).some((row) => row.letter_grade === 'B' && Number(row.count) >= 1);
  record('dashboard grade distribution includes the published B result', hasPublishedB, details(dashboard));
}

async function runNegative() {
  const validSearch = requestEnvelope('student.search', institution.id, campus.id, { query: 'DMU-0001', search_type: 'student_number', limit: 25, offset: 0 });

  const missing = await callWorkflow('rpc_search_students', validSearch, undefined);
  record('missing Authorization header is sanitized', missing.status === 401 && missing.body?.success === false && missing.body?.error?.code === 'AUTH_HEADER_REQUIRED', details(missing));

  const invalid = await callWorkflow('rpc_search_students', validSearch, 'Bearer invalid.invalid.invalid');
  record('invalid token is sanitized', invalid.status === 401 && invalid.body?.success === false && !JSON.stringify(invalid.body).includes('invalid.invalid.invalid'), details(invalid));

  const expiredJwt = `${base64Url({ alg: 'none', typ: 'JWT' })}.${base64Url({ sub: crypto.randomUUID(), exp: 1 })}.expired`;
  const expired = await callWorkflow('rpc_search_students', validSearch, `Bearer ${expiredJwt}`);
  record('expired token is sanitized', expired.status === 401 && expired.body?.success === false && expired.body?.error?.code === 'AUTH_SESSION_INVALID', details(expired));

  const validationCases = [
    ['invalid institution UUID', { ...validSearch, context: { ...validSearch.context, institution_id: 'not-a-uuid' } }, 'VALIDATION_INSTITUTION_UUID_INVALID'],
    ['invalid campus UUID', { ...validSearch, context: { ...validSearch.context, campus_id: 'not-a-uuid' } }, 'VALIDATION_CAMPUS_UUID_INVALID'],
    ['empty search query', requestEnvelope('student.search', institution.id, campus.id, { query: '', search_type: 'auto', limit: 25, offset: 0 }), 'VALIDATION_SEARCH_QUERY_REQUIRED'],
    ['one-character name search', requestEnvelope('student.search', institution.id, campus.id, { query: 'D', search_type: 'name', limit: 25, offset: 0 }), 'VALIDATION_NAME_QUERY_TOO_SHORT'],
    ['unsupported search type', requestEnvelope('student.search', institution.id, campus.id, { query: 'DMU-0001', search_type: 'unknown', limit: 25, offset: 0 }), 'VALIDATION_SEARCH_TYPE_UNSUPPORTED']
  ];
  for (const [name, request, expectedCode] of validationCases) {
    const result = await callWorkflow('rpc_search_students', request, auth);
    record(name, result.status === 400 && result.body?.success === false && result.body?.error?.code === expectedCode, details(result));
  }

  const identity = await callWorkflow(
    'rpc_search_students',
    requestEnvelope('student.search', institution.id, campus.id, { query: 'DEMO-ID-DMU-0001', search_type: 'identity_reference', limit: 25, offset: 0 }),
    auth
  );
  const identitySerialized = JSON.stringify(identity.body);
  record('identity search never returns the full value', identity.status === 200 && !identitySerialized.includes('DEMO-ID-DMU-0001') && /\*+0001/.test(identitySerialized), details(identity));

  const zero = await callWorkflow(
    'rpc_search_students',
    requestEnvelope('student.search', institution.id, campus.id, { query: 'NO-SUCH-STUDENT-999999', search_type: 'student_number', limit: 25, offset: 0 }),
    auth
  );
  record('zero matches return HTTP 200 and an empty array', zero.status === 200 && zero.body?.success === true && zero.body?.data?.count === 0 && zero.body?.data?.students?.length === 0, details(zero));

  const otherInstitutions = await restRows('institutions', `select=id,code,name&id=neq.${encodeURIComponent(institution.id)}&status=eq.active&limit=10`, token).catch(() => []);
  let emptyScopeCovered = false;
  for (const candidate of otherInstitutions) {
    const candidateCampuses = await restRows('campuses', `select=id,code,name&institution_id=eq.${encodeURIComponent(candidate.id)}&status=eq.active&limit=10`, token).catch(() => []);
    for (const candidateCampus of candidateCampuses) {
      const result = await callWorkflow('rpc_get_dashboard_snapshot', requestEnvelope('dashboard.snapshot', candidate.id, candidateCampus.id, { term_id: null }), auth);
      if (result.status === 200 && result.body?.success && Number(result.body?.data?.metrics?.students_total) === 0) {
        const metrics = result.body.data.metrics;
        const numericValues = Object.values(metrics);
        emptyScopeCovered = numericValues.every((value) => typeof value === 'number') && Array.isArray(result.body.data.grade_distribution) && Array.isArray(result.body.data.course_capacity);
        record('empty dashboard scope returns zero metrics and arrays', emptyScopeCovered, details(result));
        break;
      }
    }
    if (emptyScopeCovered) break;
  }
  if (!emptyScopeCovered) evidence.coverage_notes.push('No authorized empty institution/campus fixture was available; zero-dashboard shape remains covered by database/tests/workflow07-admin-dashboard.sql.');

  evidence.coverage_notes.push('Teacher-only denial is transactionally covered by database/tests/workflow07-admin-dashboard.sql; a second live teacher-only Auth account was not supplied to this script.');
  evidence.coverage_notes.push('Out-of-scope role denial requires a deliberately limited live actor; server-side scope is also verified by the database test and verification SQL.');
  evidence.coverage_notes.push('Temporary Supabase outage mapping is not induced against the live pilot. It requires a controlled fault-injection window.');
  evidence.coverage_notes.push('Business tables are read-only in the RPC definitions; durable workflow-run logging is an intentional operational side effect.');
}

if (mode === 'positive' || mode === 'all') await runPositive();
if (mode === 'negative' || mode === 'all') await runNegative();

const evidenceDirectory = path.join(root, 'evidence');
fs.mkdirSync(evidenceDirectory, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const evidencePath = path.join(evidenceDirectory, `workflow07-${mode}-${stamp}.json`);
fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2) + '\n', 'utf8');
console.log(`Evidence written: ${path.relative(root, evidencePath)}`);
if (evidence.coverage_notes.length) {
  console.log('Coverage notes:');
  evidence.coverage_notes.forEach((note) => console.log(`- ${note}`));
}
if (failureCount) process.exit(1);
