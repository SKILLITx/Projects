import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const repository = process.argv[2];
const outputPath = process.argv[3];
if (!repository || !outputPath) throw new Error('Usage: node Inspect-N8nRuntimeCatalogue.mjs <repository> <output>');

const candidates = [];
if (process.env.N8N_USER_FOLDER) candidates.push(path.join(process.env.N8N_USER_FOLDER, 'database.sqlite'));
candidates.push(path.join(repository, '.n8n', 'database.sqlite'));
candidates.push(path.join(os.homedir(), '.n8n', 'database.sqlite'));
const dbPath = [...new Set(candidates)].find((candidate) => fs.existsSync(candidate));

const result = {
  available: false,
  database_location: dbPath ? path.relative(repository, dbPath) || '.n8n/database.sqlite' : null,
  driver: null,
  workflows: [],
  active_workflows: [],
  error_handlers: [],
  unsupported_crypto_references: [],
  warning: null,
};

function summarize(rows) {
  for (const row of rows) {
    let nodes = [];
    let connections = {};
    try { nodes = JSON.parse(row.nodes || '[]'); } catch {}
    try { connections = JSON.parse(row.connections || '{}'); } catch {}
    const connectionText = JSON.stringify(connections);
    const types = [...new Set(nodes.map((node) => String(node?.type || '')).filter(Boolean))].sort();
    const summary = { id: String(row.id || ''), name: String(row.name || ''), active: Boolean(row.active), node_types: types };
    result.workflows.push(summary);
    if (summary.active) result.active_workflows.push({ id: summary.id, name: summary.name });
    if (types.some((type) => /errorTrigger/i.test(type)) || /^SIS 10\b/i.test(summary.name)) {
      result.error_handlers.push({ id: summary.id, name: summary.name, active: summary.active });
    }
    for (const node of nodes.filter((node) => /crypto/i.test(String(node?.type || '')))) {
      result.unsupported_crypto_references.push({
        workflow_id: summary.id,
        workflow: summary.name,
        active: summary.active,
        node: String(node?.name || ''),
        type: String(node?.type || ''),
        connected: connectionText.includes(String(node?.name || '')),
      });
    }
  }
  result.available = true;
}

if (!dbPath) {
  result.warning = 'n8n SQLite database was not found in the configured or standard user folders.';
} else {
  let completed = false;
  try {
    const modulePath = require.resolve('better-sqlite3', { paths: [repository] });
    const Database = require(modulePath);
    const db = new Database(dbPath, { readonly: true, fileMustExist: true });
    const rows = db.prepare('select id, name, active, nodes, connections from workflow_entity order by name').all();
    db.close();
    result.driver = 'better-sqlite3';
    summarize(rows);
    completed = true;
  } catch (error) {
    result.warning = `Runtime catalogue could not use better-sqlite3: ${String(error?.message || error).slice(0, 300)}`;
  }
  if (!completed) {
    try {
      const modulePath = require.resolve('sqlite3', { paths: [repository] });
      const sqlite3 = require(modulePath);
      const rows = await new Promise((resolve, reject) => {
        const db = new sqlite3.Database(dbPath, sqlite3.OPEN_READONLY, (openError) => {
          if (openError) return reject(openError);
          db.all('select id, name, active, nodes, connections from workflow_entity order by name', (queryError, data) => {
            db.close();
            if (queryError) reject(queryError); else resolve(data);
          });
        });
      });
      result.driver = 'sqlite3';
      result.warning = null;
      summarize(rows);
      completed = true;
    } catch (error) {
      const previous = result.warning ? `${result.warning}; ` : '';
      result.warning = `${previous}sqlite3 fallback unavailable: ${String(error?.message || error).slice(0, 300)}`;
    }
  }
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));
