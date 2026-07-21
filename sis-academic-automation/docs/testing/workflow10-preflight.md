# Workflow 10 Preflight Testing

## Local inspection

Run:

```powershell
& ".\scripts\Test-Workflow10LocalPreflight.ps1"
```

It verifies:

- n8n is pinned to exactly 2.4.0;
- installed Error Trigger, Code, HTTP Request, IF, Merge and Switch node implementations are present;
- existing workflow files parse;
- active workflow names are captured without parameters or credentials;
- existing Error Trigger variants are detected;
- Crypto-node references are reported with active/connected classification;
- no final Workflow 10 workflow already exists as an active duplicate.

The evidence file contains names, node types and file paths only. It does not serialize node parameters, credentials, headers, payloads or tokens.

## Hosted read-only inspection

Run the SQL copied by:

```powershell
& ".\scripts\Copy-Workflow10PreflightSql.ps1"
```

The combined SQL returns three compact JSON rows:

1. schema/RLS/index/enum metadata;
2. RPC signatures, grants and bounded definition excerpts;
3. sanitized operational counts.

No SQL file performs INSERT, UPDATE, DELETE, DDL, grants or function replacement.

## Preflight decision

After both outputs are reviewed, produce:

- confirmed Workflow 10 design;
- immutable migration list, only where gaps exist;
- exact n8n 2.4.0 workflow JSON;
- static, database, positive and bundled negative test assets.
