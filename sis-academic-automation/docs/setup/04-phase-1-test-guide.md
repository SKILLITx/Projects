# Phase 1 Test Guide

## Static repository test

```powershell
npm run test:static
```

Expected result:

```text
Phase 1 static validation passed.
```

This verifies:

- required directories and files;
- valid `package.json`;
- exact n8n dependency pin;
- no Docker artifacts;
- no workflow JSON or SQL migrations created prematurely;
- no obvious committed secret values in repository-authored source files;
- required PowerShell scripts and documentation.

The scanner intentionally excludes third-party dependencies and local/generated state, including `node_modules`, `.runtime`, `.n8n`, `.git`, backups, exports and generated output. Those paths are not committed project source and can contain dependency examples or encrypted/local credential metadata that would otherwise produce false positives.

## Environment test

```powershell
npm run environment:test
```

Expected result: PASS for PowerShell, `.env`, Node.js, npm, exact n8n version, ngrok, port, encryption key and n8n user folder.

## Runtime test

Start:

```powershell
npm run sis:start
```

Test:

```powershell
npm run sis:test
```

Expected result:

- local probe passes;
- public probe passes;
- n8n editor opens locally;
- public ngrok URL uses HTTPS;
- `.runtime\active-webhook-url.txt` contains the current URL;
- logs contain no printed `.env` values.

Stop:

```powershell
npm run sis:stop
```

## Dependency audit rule

An npm vulnerability report is not repaired automatically with `npm audit fix --force`. Forced resolution may upgrade or replace packages in the pinned n8n 2.4.0 dependency tree. Capture and classify the audit separately before pilot readiness.

## Failure triage

| Failure | First place to inspect |
|---|---|
| Node version rejected | `node --version` |
| n8n missing or wrong version | `npm install` and `node_modules\.bin\n8n.cmd --version` |
| ngrok missing | `ngrok help` |
| ngrok authentication failure | `.runtime\logs\ngrok.stderr.log` and local ngrok config |
| port 5678 in use | identify the existing listener or stop the previous SIS runtime |
| local health failure | n8n stdout/stderr logs |
| public health failure | ngrok logs, active URL and local n8n health |
| static secret false positive | confirm the file is repository-authored; generated/runtime/dependency paths should be excluded |
| dynamic URL changed | restart both processes and update external registrations |

Do not paste complete logs if they contain personal data or tokens. Redact values before sharing a focused error excerpt.
