# Phase 4 Wave 1 — Google Sheets Trigger range repair

## Failure

The Google Sheets Trigger returned:

```text
Unable to parse range: Form Responses 1!A0:P0
```

The workflow exports used the rowless A1 range `A:P`. In n8n 2.4.0, the
Google Sheets Trigger parser can treat the missing row number as zero while
constructing the header range, producing the invalid request `A0:P0`.

## Repair

Both queue-trigger workflows now use:

```text
A1:P
```

This gives n8n an explicit header row and lets it construct:

- header range: `A1:P1`
- data range: `A2:P`

## Imported workflow action

Because credentials have already been bound in the n8n database, do not
re-import the workflows. Re-importing could overwrite the saved node
configuration.

Open each imported workflow and change only the trigger range:

- SIS 01 — Student Intake and Profile Management
- SIS 02 — Course and Subject Enrollment Lifecycle

In `Google Sheets Queue Trigger`:

```text
Options → Data Location on Sheet → Range = A1:P
```

Save both workflows and keep them inactive while testing.
