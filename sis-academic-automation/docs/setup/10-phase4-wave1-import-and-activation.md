# Phase 4 Wave 1 Import and Activation

## Order

1. Apply migration 009 and run the hosted database verification.
2. Stop n8n and ngrok.
3. Configure the four Google IDs in `.env`.
4. Run `scripts/Import-Phase4Wave1.ps1`.
5. Start SIS.
6. Open each imported workflow and bind credentials.
7. Test each workflow manually.
8. Activate workflows 01, 02 and 08 only after the focused tests pass.

## Important Google trigger behavior

On activation, a Google Sheets `Row Added` trigger records the current queue position. It processes rows added after activation; it is not a historical backfill mechanism.

## Document line format

The Student Profile form accepts one Drive link per line. To attach a link to a document requirement, use:

```text
DOCUMENT_CODE|https://drive.google.com/...
```

A URL without a document code is retained as an unclassified link and does not satisfy an enrollment document requirement.
