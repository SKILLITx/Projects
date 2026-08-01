# Phase 4 Wave 1 — optional credential-property repair

The recovery script runs with PowerShell `Set-StrictMode`. Most n8n nodes do
not have a `credentials` property, so direct access such as:

```powershell
$Node.credentials
```

throws `PropertyNotFoundStrict`.

The repair reads optional properties through:

```powershell
$Node.PSObject.Properties['credentials']
```

It snapshots only nodes that actually contain credential bindings and checks
that those same bindings remain present after Workflow 08 is re-imported.

No credential value is printed or added to the patch.
