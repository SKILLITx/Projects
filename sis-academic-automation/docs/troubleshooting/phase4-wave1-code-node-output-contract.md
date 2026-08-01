# Phase 4 Wave 1 — n8n Code-node output-contract repair

## Failure

n8n 2.4.0 reported:

```text
A 'json' property isn't an object
```

The affected nodes were configured as **Run Once for Each Item**, but their
scripts returned an array:

```javascript
return [{ json: { ... } }];
```

Per-item mode must return one output object:

```javascript
return { json: { ... } };
```

A separate dispatcher node intentionally expands one claimed batch into
multiple output items. That node is now configured as **Run Once for All
Items**, where returning an array is valid.

## Scope

The repair updates all affected Wave 1 Code nodes, not only the first node
that failed:

- two Student Intake Code nodes;
- two Enrollment Lifecycle Code nodes;
- four per-item Notification Dispatcher Code nodes;
- the dispatcher batch-expansion mode.

It also retains the earlier `A1:P` Google Sheets trigger-range correction.

## Live workflow safety

`Repair-LivePhase4Wave1CodeContracts.ps1`:

1. reads the current ngrok URL;
2. stops only n8n;
3. exports each live workflow from n8n;
4. changes only Code-node mode and JavaScript;
5. preserves credential IDs, selected spreadsheets, selected tabs,
   ownership and all other live settings;
6. imports the repaired inactive workflows;
7. restarts n8n using the existing ngrok hostname.

No password, OAuth secret or Supabase key is read or printed.
