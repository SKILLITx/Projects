# Repository Plan

## 1. Planned final structure

```text
sis-academic-automation/
├── README.md
├── PROJECT_STATE.md
├── CHANGELOG.md
├── .env.example
├── .gitignore
├── package.json
├── database/
│   ├── migrations/
│   ├── seeds/
│   ├── tests/
│   └── schema/
├── workflows/
│   ├── 01-student-intake.json
│   ├── 02-enrollment-lifecycle.json
│   ├── 03-marks-intake.json
│   ├── 04-results-publication.json
│   ├── 05-transcript-delivery.json
│   ├── 06-hec-reporting.json
│   ├── 07-admin-search-dashboard.json
│   ├── 08-notification-dispatcher.json
│   ├── 09-operations-monitoring.json
│   └── 10-global-error-handler.json
├── portal/
│   ├── index.html
│   ├── app.js
│   ├── styles.css
│   └── config.example.js
├── google/
│   ├── forms/
│   ├── templates/
│   └── setup/
├── emails/
├── scripts/
├── tests/
│   ├── static/
│   ├── integration/
│   ├── acceptance/
│   └── load/
├── docs/
│   ├── architecture/
│   ├── setup/
│   ├── workflows/
│   ├── database/
│   ├── testing/
│   ├── troubleshooting/
│   └── handover/
└── evidence/
```

## 2. Naming conventions

- SQL migrations: `YYYYMMDDHHMM_description.sql`
- Database tests: `NN_domain_test.sql`
- Workflows: zero-padded business number and kebab-case name
- PowerShell scripts: approved Verb-Noun format
- Documentation: numbered where reading order matters
- Environment variables: uppercase snake case
- RPCs: `rpc_<verb>_<business_object>`
- Internal functions: `<schema>.<verb>_<object>`

## 3. Portability rules

- No real credential IDs in workflow exports.
- No hardcoded Supabase URL, Google file ID, email address, institution ID, campus ID, ngrok URL or grading rule.
- `.env.example` contains placeholders only.
- User-specific values are bound during setup.
- Generated evidence excludes secrets and tokens.
- Workflow exports are validated against the installed n8n 2.4.0 instance.

## 4. Immutable artifacts

- Applied migrations are never edited silently.
- Migration checksums are recorded.
- Seed revisions are versioned.
- Test evidence is timestamped.
- Changes are recorded in `CHANGELOG.md`.
- Current status is recorded in `PROJECT_STATE.md`.

## 5. Phase 0 repository contents

Only documentation, catalogs, manifest and checksums are created in Phase 0. Empty implementation folders are not created merely to simulate progress.
