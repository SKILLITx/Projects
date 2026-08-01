const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const files = [
  'workflows/01-student-intake.json',
  'workflows/02-enrollment-lifecycle.json',
  'workflows/08-notification-dispatcher.json',
];

let checkedCodeNodes = 0;
for (const relativePath of files) {
  const fullPath = path.join(projectRoot, relativePath);
  const workflow = JSON.parse(fs.readFileSync(fullPath, 'utf8'));

  for (const node of workflow.nodes || []) {
    if (node.type === 'n8n-nodes-base.googleSheetsTrigger') {
      const range =
        node.parameters?.options?.dataLocationOnSheet?.values?.range;
      if (range !== 'A1:P') {
        throw new Error(
          `${relativePath}: Google Sheets trigger range must be A1:P, found ${range}`,
        );
      }
    }

    if (node.type !== 'n8n-nodes-base.code') continue;
    checkedCodeNodes += 1;

    const mode = node.parameters?.mode;
    const code = node.parameters?.jsCode || '';

    // Compile as a function body because n8n Code-node scripts may use
    // top-level return statements.
    new Function(code);

    if (
      mode === 'runOnceForEachItem' &&
      /return\s*\[\s*\{\s*json\s*:/.test(code)
    ) {
      throw new Error(
        `${relativePath} / ${node.name}: per-item mode returns an array`,
      );
    }

    if (
      node.name === 'Render Notification Batch' &&
      mode !== 'runOnceForAllItems'
    ) {
      throw new Error(
        `${relativePath} / Render Notification Batch must run once for all items`,
      );
    }
  }
}

if (checkedCodeNodes !== 9) {
  throw new Error(`Expected 9 Code nodes, checked ${checkedCodeNodes}`);
}

console.log('PHASE 4 WAVE 1 CODE CONTRACT TEST: PASS');
console.log(
  'Verified nine Code nodes, per-item object returns, batch-output mode, JavaScript syntax and A1:P trigger ranges.',
);
