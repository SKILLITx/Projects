'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');

function loadWorkflow(relative) {
  return JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
}

function executeCodeNode(workflow, nodeName, input) {
  const node = workflow.nodes.find((candidate) => candidate.name === nodeName);
  if (!node) throw new Error(`Missing Code node: ${nodeName}`);
  const execute = new Function('$json', node.parameters.jsCode);
  const result = execute(input);
  if (!Array.isArray(result) || result.length !== 1 || !result[0].json) {
    throw new Error(`${nodeName} returned an invalid n8n item array.`);
  }
  return result[0].json;
}

const studentWorkflow = loadWorkflow('workflows/01-student-intake.json');
const enrollmentWorkflow = loadWorkflow('workflows/02-enrollment-lifecycle.json');
const studentFixture = JSON.parse(
  fs.readFileSync(path.join(root, 'tests/fixtures/student-profile-queue-row.json'), 'utf8'),
);
const enrollmentFixture = JSON.parse(
  fs.readFileSync(path.join(root, 'tests/fixtures/enrollment-queue-row.json'), 'utf8'),
);

const student = executeCodeNode(studentWorkflow, 'Normalize Student Queue Row', studentFixture);
if (!student.processable || student.request.operation !== 'student.profile.submit') {
  throw new Error('Student queue fixture did not normalize to a processable request.');
}
if (!student.request.idempotency_key || !student.request.correlation_id) {
  throw new Error('Student request is missing correlation or idempotency data.');
}

const enrollment = executeCodeNode(
  enrollmentWorkflow,
  'Normalize Enrollment Queue Row',
  enrollmentFixture,
);
if (!enrollment.processable || enrollment.request.operation !== 'enrollment.submit') {
  throw new Error('Enrollment queue fixture did not normalize to a processable request.');
}
if (!Array.isArray(enrollment.request.payload.course_codes)) {
  throw new Error('Enrollment course codes were not normalized to an array.');
}

const alignedFixture = JSON.parse(JSON.stringify(enrollmentFixture));
const alignedRaw = JSON.parse(alignedFixture['Raw Response JSON']);
alignedRaw['Requested course or subject codes (comma-separated)'] = 'BA101, SQL201';
alignedRaw['Preferred section codes in the same order (optional, comma-separated)'] = ', A';
alignedFixture['Raw Response JSON'] = JSON.stringify(alignedRaw);
alignedFixture['Form Response ID'] = 'normalizer-alignment-test';
alignedFixture['Idempotency Key'] = 'normalizer-alignment-test';

const aligned = executeCodeNode(
  enrollmentWorkflow,
  'Normalize Enrollment Queue Row',
  alignedFixture,
);
const preferred = aligned.request.payload.preferred_section_codes;
if (preferred.length !== 2 || preferred[0] !== '' || preferred[1] !== 'A') {
  throw new Error('Blank preferred-section positions were not preserved.');
}

const completedFixture = JSON.parse(JSON.stringify(enrollmentFixture));
completedFixture['Processing Status'] = 'completed';
const completed = executeCodeNode(
  enrollmentWorkflow,
  'Normalize Enrollment Queue Row',
  completedFixture,
);
if (completed.processable !== false || completed.skipReason !== 'QUEUE_ROW_NOT_PENDING') {
  throw new Error('Completed queue rows are not being skipped safely.');
}

console.log('PHASE 4 WAVE 1 NORMALIZER TEST: PASS');
console.log('Verified request envelopes, correlation/idempotency data, aligned section preferences and completed-row skipping.');
