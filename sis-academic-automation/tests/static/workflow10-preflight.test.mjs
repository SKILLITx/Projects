import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const required = [
  'database/queries/workflow10-schema-inspection.sql',
  'database/queries/workflow10-rpc-inspection.sql',
  'database/queries/workflow10-operational-snapshot.sql',
  'scripts/Test-Workflow10LocalPreflight.ps1',
  'scripts/Inspect-N8nRuntimeCatalogue.mjs',
  'scripts/Copy-Workflow10PreflightSql.ps1',
  'docs/workflows/10-global-error-handler-preflight.md',
  'docs/testing/workflow10-preflight.md',
];
for (const rel of required) {
  if (!fs.existsSync(path.join(root, rel))) throw new Error(`Missing Workflow 10 preflight file: ${rel}`);
}
if (fs.existsSync(path.join(root, 'workflows/10-global-error-handler.json'))) {
  throw new Error('Preflight must not include the final Workflow 10 JSON.');
}
const migrationDir = path.join(root, 'database/migrations');
if (fs.existsSync(migrationDir)) {
  const unexpected = fs.readdirSync(migrationDir).filter((name) => /workflow10|global_error/i.test(name));
  if (unexpected.length) throw new Error(`Preflight must not include a Workflow 10 migration: ${unexpected.join(', ')}`);
}
console.log('SIS 10 PREFLIGHT PACKAGE STATIC: PASS');
