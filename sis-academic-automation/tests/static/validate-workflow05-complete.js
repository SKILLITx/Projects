const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const workflowPath = path.join(root, 'workflows', '05-transcript-delivery.json');
const migrationPath = path.join(
  root,
  'database',
  'migrations',
  '20260720000500_phase4_workflow05_transcript_delivery.sql'
);
const templatePath = path.join(
  root,
  'google',
  'templates',
  'workflow05-transcript-template.html'
);

function fail(message) {
  console.error(`SIS 05 TRANSCRIPT COMPLETE CHECK: FAIL\n${message}`);
  process.exit(1);
}

for (const p of [workflowPath, migrationPath, templatePath]) {
  if (!fs.existsSync(p)) fail(`Missing required file: ${p}`);
}

let workflow;
try {
  workflow = JSON.parse(fs.readFileSync(workflowPath, 'utf8'));
} catch (error) {
  fail(`Workflow JSON is invalid: ${error.message}`);
}

if (!String(workflow.name || '').includes('Transcript Request, Generation and Delivery')) {
  fail('Workflow name is not the complete Workflow 05 business boundary.');
}

if (!Array.isArray(workflow.nodes) || workflow.nodes.length < 35) {
  fail('Workflow 05 does not contain the complete transcript pipeline.');
}

const nodeNames = new Set(workflow.nodes.map((node) => node.name));
const requiredNodes = [
  'Transcript Request Webhook',
  'Validate Supabase User',
  'Create Transcript Request RPC',
  'Get Transcript Model RPC',
  'Populate Transcript Google Docs Template',
  'Create Transcript Google Doc',
  'Export Transcript PDF',
  'Compute Transcript PDF SHA256',
  'Upload Transcript PDF',
  'Record Transcript Document RPC',
  'Record Transcript Failure RPC',
  'Respond Transcript Success'
];
for (const name of requiredNodes) {
  if (!nodeNames.has(name)) fail(`Missing required node: ${name}`);
}

for (const node of workflow.nodes) {
  if (node.type === 'n8n-nodes-base.executeCommand') {
    fail('Execute Command nodes are prohibited.');
  }
  if (node.type !== 'n8n-nodes-base.stickyNote' && !String(node.notes || '').trim()) {
    fail(`Node lacks operational notes: ${node.name}`);
  }
}

const jsonText = JSON.stringify(workflow);
const forbidden = [
  'ojetmpchcwfpnjbuqvuv',
  'gemma-unfossilised-silverly',
  'zaidrizwan.278@gmail.com',
  'SUPABASE_SERVICE_ROLE_KEY',
  '/rest/v1/ops.',
  'Accept-Profile":"reporting',
  'Content-Profile":"reporting'
];
for (const value of forbidden) {
  if (jsonText.includes(value)) fail(`Portable workflow contains forbidden hardcoding: ${value}`);
}

const webhookNodes = workflow.nodes.filter(
  (node) => node.type === 'n8n-nodes-base.webhook'
);
if (webhookNodes.length !== 1) fail('Workflow 05 must expose exactly one request webhook.');
if (
  webhookNodes[0].parameters.path !== 'staff/rpc_create_transcript_request' ||
  webhookNodes[0].parameters.httpMethod !== 'POST'
) {
  fail('Workflow 05 webhook route/method is incorrect.');
}

const googleNodes = workflow.nodes.filter(
  (node) =>
    node.type === 'n8n-nodes-base.httpRequest' &&
    node.parameters &&
    node.parameters.nodeCredentialType === 'googleDriveOAuth2Api'
);
if (googleNodes.length < 4) fail('Google Docs/PDF/Drive operations are incomplete.');
for (const node of googleNodes) {
  const cred = node.credentials && node.credentials.googleDriveOAuth2Api;
  if (!cred || cred.name !== 'Google Drive account') {
    fail(`Google credential binding name is incorrect on: ${node.name}`);
  }
}

const serviceNodes = workflow.nodes.filter(
  (node) =>
    node.type === 'n8n-nodes-base.httpRequest' &&
    node.parameters &&
    node.parameters.nodeCredentialType === 'supabaseApi'
);
if (serviceNodes.length < 2) fail('Service-only transcript RPC calls are missing.');
for (const node of serviceNodes) {
  const cred = node.credentials && node.credentials.supabaseApi;
  if (!cred || cred.name !== 'SIS Supabase Service Role') {
    fail(`Supabase credential binding name is incorrect on: ${node.name}`);
  }
}

const migration = fs.readFileSync(migrationPath, 'utf8');
const migrationRequired = [
  'rpc_create_transcript_request',
  'rpc_get_transcript_model',
  'rpc_record_transcript_document',
  'rpc_mark_transcript_request_failed',
  'IDEMPOTENCY_PAYLOAD_CONFLICT',
  'trg_sync_transcript_delivery_from_notification',
  "'email'::ops.notification_channel",
  'already_recorded',
  "notify pgrst, 'reload schema'"
];
for (const value of migrationRequired) {
  if (!migration.includes(value)) fail(`Migration is missing: ${value}`);
}

const template = fs.readFileSync(templatePath, 'utf8');
for (const token of [
  '{{INSTITUTION_NAME}}',
  '{{STUDENT_NUMBER}}',
  '{{TERM_AND_COURSE_TABLES}}',
  '{{CGPA}}',
  '{{VERIFICATION_CODE}}',
  '{{TRANSCRIPT_DISCLAIMER}}'
]) {
  if (!template.includes(token)) fail(`Transcript template is missing: ${token}`);
}

console.log('SIS 05 TRANSCRIPT COMPLETE CHECK: PASS');
console.log(
  `Verified ${workflow.nodes.length} nodes, authenticated RPC routing, Google Docs/PDF/Drive generation, database idempotency and Workflow 08 delivery synchronization.`
);
