# Phase 4 Wave 1 Credential and Variable Binding

## Required n8n credentials

Create or reuse these exact names after importing the workflows:

| Name | n8n credential type | Used by |
|---|---|---|
| `SIS Supabase Service Role` | Supabase API | all HTTP Request RPC nodes |
| `SIS Google Sheets Trigger OAuth` | Google Sheets Trigger OAuth2 API | workflows 01 and 02 trigger nodes |
| `SIS Google Sheets OAuth` | Google Sheets OAuth2 API | workflows 01 and 02 queue-update nodes |
| `SIS Gmail Official Sender` | Gmail OAuth2 API | workflow 08 Gmail node |

The portable JSON intentionally contains no credential IDs. Bind the credentials in the editor after import.

## Environment variables

Run the Google helper to obtain the four non-secret IDs, then run `scripts/Set-Phase4Wave1Config.ps1`.

Required variables:

- `SIS_STUDENT_PROFILE_RESPONSE_SHEET_ID`
- `SIS_STUDENT_PROFILE_QUEUE_TAB_ID`
- `SIS_ENROLLMENT_RESPONSE_SHEET_ID`
- `SIS_ENROLLMENT_QUEUE_TAB_ID`
- `SIS_NOTIFICATION_BATCH_SIZE`

`SUPABASE_URL` must already contain the SIS Automation project API URL.

## Credentials and browser boundaries

The Supabase service-role key belongs only in the n8n Supabase credential. It must not appear in workflow JSON, `.env.example`, portal code or screenshots.
