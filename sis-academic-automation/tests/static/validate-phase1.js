'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const errors = [];

function exists(relativePath) {
  return fs.existsSync(path.join(root, relativePath));
}

function requireFile(relativePath) {
  if (!exists(relativePath) || !fs.statSync(path.join(root, relativePath)).isFile()) {
    errors.push(`Missing required file: ${relativePath}`);
  }
}

function requireDirectory(relativePath) {
  if (!exists(relativePath) || !fs.statSync(path.join(root, relativePath)).isDirectory()) {
    errors.push(`Missing required directory: ${relativePath}`);
  }
}

const requiredFiles = [
  'README.md', 'PROJECT_STATE.md', 'CHANGELOG.md', '.env.example', '.gitignore', 'package.json',
  'scripts/Initialize-Environment.ps1', 'scripts/Start-N8n.ps1', 'scripts/Start-Ngrok.ps1',
  'scripts/Start-SIS.ps1', 'scripts/Test-Environment.ps1', 'scripts/Test-SIS.ps1',
  'scripts/Stop-SIS.ps1', 'scripts/lib/Sis.Runtime.ps1',
  'docs/setup/01-local-runtime-setup.md', 'docs/setup/02-ngrok-setup.md',
  'docs/setup/03-n8n-2.4.0-compatibility.md', 'docs/setup/04-phase-1-test-guide.md'
];
requiredFiles.forEach(requireFile);

const requiredDirectories = [
  'database/migrations', 'database/seeds', 'database/tests', 'database/schema', 'workflows', 'portal',
  'google/forms', 'google/templates', 'google/setup', 'emails', 'scripts', 'tests/static',
  'tests/integration', 'tests/acceptance', 'tests/load', 'docs/architecture', 'docs/setup',
  'docs/workflows', 'docs/database', 'docs/testing', 'docs/troubleshooting', 'docs/handover', 'evidence'
];
requiredDirectories.forEach(requireDirectory);

let pkg;
try {
  pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
} catch (error) {
  errors.push(`package.json is invalid JSON: ${error.message}`);
}

if (pkg) {
  if (!pkg.dependencies || pkg.dependencies.n8n !== '2.4.0') {
    errors.push('package.json must pin dependencies.n8n to exactly 2.4.0');
  }
  if (!pkg.engines || pkg.engines.node !== '>=20.19.0 <=24.x') {
    errors.push('package.json must declare the approved Node.js engine range');
  }
}

// These locations contain dependencies, local runtime state, generated data or VCS metadata.
// They are intentionally excluded because the test checks repository-authored source files,
// not third-party package contents or local secret-bearing runtime files.
const excludedDirectoryNames = new Set([
  '.git',
  '.runtime',
  '.n8n',
  'node_modules',
  'backups',
  'exports',
  'generated'
]);

const excludedRelativeDirectories = new Set([
  'evidence/runtime',
  'google/generated'
]);

function shouldSkipDirectory(absolutePath, entryName) {
  if (excludedDirectoryNames.has(entryName)) return true;
  const relative = path.relative(root, absolutePath).replace(/\\/g, '/').toLowerCase();
  return excludedRelativeDirectories.has(relative);
}

function walk(directory) {
  const collected = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (!shouldSkipDirectory(absolute, entry.name)) collected.push(...walk(absolute));
    } else if (entry.isFile()) {
      collected.push(absolute);
    }
  }
  return collected;
}

const files = walk(root);
const relativeFiles = files.map((file) => path.relative(root, file).replace(/\\/g, '/'));

for (const file of relativeFiles) {
  const lower = file.toLowerCase();
  if (lower === 'dockerfile' || lower.includes('docker-compose') || lower.endsWith('.dockerfile')) {
    errors.push(`Docker artifact is prohibited: ${file}`);
  }
  if (lower.startsWith('workflows/') && lower.endsWith('.json')) {
    errors.push(`Workflow JSON created before Phase 4: ${file}`);
  }
  if (lower.startsWith('database/migrations/') && lower.endsWith('.sql')) {
    errors.push(`SQL migration created before Phase 2: ${file}`);
  }
}

const textExtensions = new Set(['.md', '.json', '.js', '.ps1', '.example', '.gitignore', '.csv', '.txt']);
const suspicious = [
  /SUPABASE_SERVICE_ROLE_KEY\s*=\s*(?!REPLACE_)[A-Za-z0-9._-]{20,}/i,
  /N8N_ENCRYPTION_KEY\s*=\s*(?!GENERATED_)[A-Za-z0-9+/=]{32,}/i,
  /ngrok config add-authtoken\s+(?!YOUR_TOKEN)[A-Za-z0-9_-]{20,}/i,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/
];

for (const absolute of files) {
  const relative = path.relative(root, absolute).replace(/\\/g, '/');
  const extension = path.extname(absolute).toLowerCase();
  if (!textExtensions.has(extension) && path.basename(absolute) !== '.gitignore') continue;
  const content = fs.readFileSync(absolute, 'utf8');
  for (const pattern of suspicious) {
    if (pattern.test(content)) errors.push(`Possible committed secret in ${relative}`);
  }
}

if (errors.length > 0) {
  console.error('Phase 1 static validation failed:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log('Phase 1 static validation passed.');
