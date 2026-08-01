# Recovery test correction

The previous package test incorrectly assumed that every Workflow 08 Code
node except `Render Notification Batch` should run once per item.

`Build Claim Request` is also intentionally a batch-level node and must use:

```text
runOnceForAllItems
```

Correct Workflow 08 modes:

| Code node | Mode |
|---|---|
| Build Claim Request | Run Once for All Items |
| Render Notification Batch | Run Once for All Items |
| Begin Attempt Decision | Run Once for Each Item |
| Build Gmail Attempt Result | Run Once for Each Item |
| Build Unsupported Channel Result | Run Once for Each Item |

The live recovery script itself was correct. Only its preflight test required
correction.
