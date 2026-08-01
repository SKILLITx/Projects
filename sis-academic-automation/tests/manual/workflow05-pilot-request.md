# Workflow 05 Pilot Request

Use the signed-in staff portal or an authenticated API client. Do not paste the
access token into chat.

Endpoint:

```text
POST <current-ngrok-url>/webhook/staff/rpc_create_transcript_request
```

Headers:

```text
Authorization: Bearer <current Supabase Auth access token>
Content-Type: application/json
```

Pilot body:

```json
{
  "correlation_id": "<new UUID>",
  "idempotency_key": "portal:transcript.request:workflow05-pilot-01",
  "institution_id": "c4bc6568-8032-ff36-a44f-6d9f26262caf",
  "campus_id": "f851ff16-b5c8-2e5c-abce-82b36041e747",
  "student_id": "d06c1815-f21c-be53-de05-816378779268",
  "recipient_email": "zaidrizwan.278@gmail.com",
  "purpose": "Workflow 05 controlled pilot transcript generation and delivery acceptance."
}
```

Expected positive outcome:

- one transcript request;
- one Google Doc;
- one PDF in Google Drive;
- one transcript document row;
- one transcript delivery row;
- one `transcript.ready` outbox item;
- Workflow 08 sends the approved-recipient email;
- a repeated request with the same idempotency key reuses the same document.

Bundled negative cases:

1. Change `recipient_email` while keeping the same idempotency key:
   `IDEMPOTENCY_PAYLOAD_CONFLICT`.
2. Use a student with no published course result:
   `TRANSCRIPT_ACADEMIC_RECORD_MISSING`.
3. Use an institution/campus outside the signed-in user's scope:
   `AUTH_SCOPE_DENIED`.
4. Remove the bearer token:
   `AUTH_LOGIN_REQUIRED`.
5. Use malformed UUIDs or email:
   `VALIDATION_REQUEST_ENVELOPE_REQUIRED`.
