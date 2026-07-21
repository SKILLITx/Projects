# Workflow 03 — complete marks intake

This workflow contains both required intake paths inside one business-domain
workflow:

1. manual teacher marks submission;
2. CSV/XLS/XLSX file submission through a Google Drive URL.

## File contract

The first spreadsheet row must contain these headers:

- `student_number`
- `marks`
- `absent`
- `missing`
- `remarks`

Accepted aliases include `student id`, `marks_obtained`, `score`,
`is_absent`, `is_missing`, `comments` and `notes`.

For a present student, `marks` is required. For an absent or explicitly
missing student, the marks cell must be empty.

## Pilot file test

Use the included FIN assessment template. Upload it to the designated
Uploaded Marks Google Drive folder and paste its Drive URL into:

`SIS — Marks CSV or Excel Upload`

The complete workflow should be imported separately and configured before
the earlier manual-only stabilized Workflow 03 is unpublished.
