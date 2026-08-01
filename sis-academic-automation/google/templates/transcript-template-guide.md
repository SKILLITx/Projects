# Google Docs Transcript Template

The provisioner creates a realistic master document named `SIS — Official Transcript Template`.

## Required placeholders

### Institution

- `{{INSTITUTION_NAME}}`
- `{{INSTITUTION_CODE}}`
- `{{INSTITUTION_ADDRESS}}`
- `{{INSTITUTION_PHONE}}`
- `{{INSTITUTION_EMAIL}}`
- `{{INSTITUTION_LOGO}}`

### Student

- `{{STUDENT_NAME}}`
- `{{STUDENT_NUMBER}}`
- `{{DATE_OF_BIRTH}}`
- `{{CAMPUS_NAME}}`
- `{{PROGRAM_NAME}}`
- `{{PROGRAM_CODE}}`
- `{{ADMISSION_DATE}}`
- `{{COMPLETION_DATE}}`

### Academic record

- `{{RESULT_ROWS_START}}`
- `{{RESULT_ROWS_END}}`
- `{{TOTAL_CREDITS_ATTEMPTED}}`
- `{{TOTAL_CREDITS_EARNED}}`
- `{{CGPA}}`
- `{{ACADEMIC_STANDING}}`

### Issuance

- `{{ISSUE_DATE}}`
- `{{TRANSCRIPT_REFERENCE}}`
- `{{VERIFICATION_CODE}}`
- `{{VERIFICATION_URL}}`
- `{{OFFICIAL_DISCLAIMER}}`

The Phase 4 transcript workflow will duplicate this master, replace scalar placeholders, populate the result table, export a PDF, save it in Drive, record its file identifiers and enqueue delivery.
