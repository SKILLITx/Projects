# Response-Sheet Structures

Each Google Form has one linked Google Sheets file.

## Tabs

1. **Form Responses 1** — Google-managed raw responses.
2. **Automation Queue** — normalized append-only event queue used by n8n.
3. **Setup Metadata** — form ID, spreadsheet ID, operation, provisioning version and timestamps.

## Automation Queue

| Column | Purpose |
|---|---|
| `Form Response ID` | Immutable Google Forms response identifier. |
| `Submitted At UTC` | Submission timestamp normalized to UTC. |
| `Respondent Email` | Collected Google account email where enabled. |
| `Operation` | Stable business operation code. |
| `Source Form ID` | Google Form identifier. |
| `Source Spreadsheet ID` | Linked response spreadsheet identifier. |
| `Raw Response JSON` | Question-title/value object serialized as JSON. |
| `Processing Status` | `pending`, `processing`, `completed`, `failed`, `dead_letter` or `ignored`. |
| `Processed At UTC` | Successful or terminal completion timestamp. |
| `Correlation ID` | Cross-system request identifier assigned by n8n. |
| `Idempotency Key` | `google-form:<form_id>:<response_id>`. |
| `Error Code` | Sanitized stable failure code. |
| `Error Message` | Sanitized user-safe failure summary. |
| `Retry Count` | Bounded processing-attempt count. |
| `Last Attempt At UTC` | Most recent workflow attempt. |
| `n8n Execution ID` | Associated n8n execution identifier. |

The normalized queue prevents workflow breakage when Google changes the raw response column order.
