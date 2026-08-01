'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..', '..');
const workflows = [
  'workflows/01-student-intake.json',
  'workflows/02-enrollment-lifecycle.json',
  'workflows/08-notification-dispatcher.json',
];
const allowed = new Map([
  ['n8n-nodes-base.googleSheetsTrigger', new Set([1])],
  ['n8n-nodes-base.code', new Set([2])],
  ['n8n-nodes-base.if', new Set([1])],
  ['n8n-nodes-base.httpRequest', new Set([4.3])],
  ['n8n-nodes-base.googleSheets', new Set([3])],
  ['n8n-nodes-base.scheduleTrigger', new Set([1.3])],
  ['n8n-nodes-base.gmail', new Set([2.2])],
]);
const requiredRpcs = [
  'rpc_submit_student_profile_from_form',
  'rpc_submit_enrollment_from_form',
  'rpc_claim_notifications',
  'rpc_begin_notification_attempt',
  'rpc_record_notification_attempt',
  'rpc_log_workflow_run',
];
const errors = [];
for (const relative of workflows) {
  const full = path.join(root, relative);
  if (!fs.existsSync(full)) { errors.push(`Missing ${relative}`); continue; }
  let wf;
  try { wf = JSON.parse(fs.readFileSync(full, 'utf8')); }
  catch (error) { errors.push(`${relative}: invalid JSON: ${error.message}`); continue; }
  if (wf.active !== false) errors.push(`${relative}: workflow must import inactive`);
  if (!Array.isArray(wf.nodes) || wf.nodes.length < 5) errors.push(`${relative}: insufficient nodes`);
  const names = new Set();
  for (const node of wf.nodes || []) {
    if (names.has(node.name)) errors.push(`${relative}: duplicate node name ${node.name}`);
    names.add(node.name);
    if (!allowed.has(node.type)) errors.push(`${relative}: unsupported node type ${node.type}`);
    else if (!allowed.get(node.type).has(node.typeVersion)) errors.push(`${relative}: unsupported ${node.type} version ${node.typeVersion}`);
    if (!node.notes || node.notes.trim().length < 20) errors.push(`${relative}: node lacks meaningful notes: ${node.name}`);
    if (node.type === 'n8n-nodes-base.executeCommand') errors.push(`${relative}: Execute Command is prohibited`);
    if (node.credentials && Object.values(node.credentials).some((v) => v && v.id)) errors.push(`${relative}: portable JSON contains credential IDs`);
    if (node.type === 'n8n-nodes-base.code') {
      const code = node.parameters?.jsCode || '';
      if (code.length > 9000) errors.push(`${relative}: Code node is too large: ${node.name}`);
      try { new Function(code); }
      catch (error) { errors.push(`${relative}: invalid Code-node JavaScript in ${node.name}: ${error.message}`); }
    }
  }
  const expressionStrings = [];
  const collectExpressions = (value, pointer = '') => {
    if (Array.isArray(value)) value.forEach((entry, index) => collectExpressions(entry, `${pointer}/${index}`));
    else if (value && typeof value === 'object') Object.entries(value).forEach(([key, entry]) => collectExpressions(entry, `${pointer}/${key}`));
    else if (typeof value === 'string' && value.startsWith('=')) expressionStrings.push([pointer, value]);
  };
  collectExpressions(wf);
  for (const [pointer, expression] of expressionStrings) {
    if (!expression.startsWith('={{') || !expression.endsWith('}}')) {
      errors.push(`${relative}: malformed expression at ${pointer}`);
      continue;
    }
    try { new Function(`return (${expression.slice(3, -2)})`); }
    catch (error) { errors.push(`${relative}: invalid expression syntax at ${pointer}: ${error.message}`); }
  }
  const serialized = JSON.stringify(wf);
  if (/https:\/\/[a-z0-9-]+\.supabase\.co/i.test(serialized)) errors.push(`${relative}: hardcoded Supabase URL`);
  if (/sb_secret_|service_role\s*[:=]\s*[A-Za-z0-9_.-]{12,}/i.test(serialized)) errors.push(`${relative}: possible secret`);
  if (/reporting\.|audit\.|ops\./i.test(serialized)) errors.push(`${relative}: direct private-schema access`);
  if (/Execute Command/i.test(serialized)) errors.push(`${relative}: prohibited Execute Command text`);
}
const combined = workflows.map((f) => fs.readFileSync(path.join(root,f),'utf8')).join('\n');
for (const rpc of requiredRpcs) if (!combined.includes(rpc)) errors.push(`Required RPC not referenced: ${rpc}`);
if (errors.length) {
  console.error('PHASE 4 WAVE 1 WORKFLOW STATIC CHECK: FAIL');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}
console.log('PHASE 4 WAVE 1 WORKFLOW STATIC CHECK: PASS');
console.log('Verified three n8n 2.4.0 workflow exports, supported node versions, descriptions, portable credentials and public-RPC boundaries.');
