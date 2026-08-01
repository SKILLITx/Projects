# Google Workspace Structure

## 1. Drive hierarchy

```text
SIS Academic Automation/
├── 00-Administration/
│   ├── Configuration Exports/
│   └── Setup Evidence/
├── 01-Form Responses/
│   ├── Student Intake/
│   ├── Enrollment/
│   ├── Marks/
│   ├── Corrections/
│   └── Transcript Requests/
├── 02-Templates/
│   ├── Transcript/
│   ├── HEC Demonstration/
│   └── Dashboard/
├── 03-Uploaded Marks/
│   ├── Pending/
│   ├── Processed/
│   ├── Failed/
│   └── Archive/
├── 04-Generated Transcripts/
│   └── <institution>/<academic-year>/
├── 05-HEC Reports/
│   └── <institution>/<academic-year>/
├── 06-Dashboards/
└── 99-Archive/
```

Folder IDs are configuration values and are never hardcoded into portable workflow JSON.

## 2. Form catalog

### Form 1 — Student Profile / Admission Information

Core fields:

- institution code;
- campus code;
- student number if existing;
- full legal name;
- CNIC/B-Form/passport placeholder policy;
- date of birth;
- email;
- phone;
- guardian/parent details where required;
- program/grade/pathway;
- academic year/intake;
- document checklist/metadata;
- consent and accuracy confirmation.

### Form 2 — Course or Subject Enrollment

Core fields:

- institution and campus;
- student number;
- academic year and term;
- requested courses/subjects;
- preferred section where applicable;
- request confirmation.

### Form 3 — Teacher Marks Submission

Restricted to approved institutional accounts where possible.

Core fields:

- captured teacher email;
- institution/campus;
- offering and section;
- assessment;
- submission type: draft or final;
- class marks entry or linked upload reference;
- declaration.

### Form 4 — Marks CSV/XLSX Upload

Core fields:

- captured teacher email;
- offering/section;
- assessment or complete-batch type;
- file upload;
- draft/final intent;
- declaration.

Uploaded files are moved or copied into the controlled Drive hierarchy after validation.

### Form 5 — Mark Correction Request

Core fields:

- requester identity;
- batch/result reference;
- affected student and assessment;
- old and requested value;
- reason;
- supporting evidence;
- declaration.

### Form 6 — Transcript Request

Core fields:

- institution/campus;
- student number;
- requester email;
- recipient purpose;
- recipient email if allowed;
- identity confirmation;
- request declaration.

## 3. Response Sheet adapter columns

Each linked response Sheet receives additional system columns:

- `source_submission_id`
- `processing_status`
- `processing_started_at`
- `processed_at`
- `correlation_id`
- `idempotency_key`
- `result_code`
- `result_summary`
- `retry_count`
- `last_error_at`

Google Sheets is not the authoritative academic record. These columns only support reliable ingestion and operator visibility.

## 4. Trigger strategy

Preferred, subject to n8n 2.4.0 verification:

- Google Sheets Trigger for newly appended response rows.

Fallback:

- Schedule Trigger polls rows with blank or retryable processing status.
- A row is atomically or logically claimed before processing.
- The source submission ID and database idempotency constraint prevent duplicate effects.

## 5. Transcript template

The Google Docs template must include stable named placeholders or structural anchors for:

- institution logo and name;
- campus;
- transcript title;
- student identity;
- program/pathway;
- academic status;
- semester-wise result table;
- attempted and earned credits;
- semester GPA;
- cumulative CGPA;
- issue date;
- reference number;
- disclaimer;
- optional verification code/URL.

Complex repeated rows may require Google Docs API batch updates when a native node cannot preserve table structure.

## 6. HEC demonstration template

The Google Sheets template must be labelled:

> Demonstration enrollment reporting format — not an official HEC template unless formally approved by the institution.

It should support institution, campus, academic year, term and program filters and provide CSV/XLSX-compatible output.

## 7. Operational dashboard

The dashboard is a presentation layer refreshed from a database snapshot. It should include:

- enrollment counts by course and section;
- remaining capacity;
- waitlist;
- rejected/manual-review requests;
- marks completion;
- grade distribution;
- at-risk students;
- GPA/CGPA summaries;
- transcript request state;
- unresolved incidents;
- notification backlog.

## 8. Gmail

Use separate credential names for:

- `Google Workspace OAuth`
- `Gmail Official Sender`

Email templates are configuration-driven. Gmail acceptance is recorded as provider acceptance, not guaranteed recipient inbox delivery.
