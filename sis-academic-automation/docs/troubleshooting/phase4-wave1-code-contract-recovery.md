# Phase 4 Wave 1 Code-contract recovery

The first recovery run successfully repaired and imported Workflows 01 and
02. Workflow 08 stopped before import because its live
`Render Notification Batch` node omitted the optional `mode` property.
PowerShell cannot assign a property that does not yet exist on a
`PSCustomObject`.

This recovery uses `Add-Member` when `mode` or `jsCode` is absent and updates
the property normally when it already exists. It repairs only Workflow 08,
then exports it again and verifies:

- all five Code-node modes;
- all five JavaScript bodies;
- unchanged credential bindings;
- inactive workflow state.

The `Active version not found` webhook-cleanup warning during inactive
workflow replacement is non-fatal when the CLI subsequently reports
`Successfully imported 1 workflow`.
