# Google Workspace Provisioning

From the project directory:

```powershell
& ".\scripts\Copy-Phase3Provisioner.ps1"
```

Create a standalone Apps Script project, paste the clipboard into `Code.gs`, save, and run `provisionPhase3Workspace`.

After authorization completes, run `verifyPhase3Assets`.

Expected JSON:

```json
{
  "success": true,
  "suite": "phase3-google-workspace-verification",
  "forms": 6,
  "response_spreadsheets": 6,
  "form_submit_triggers": 6,
  "folders": 12,
  "transcript_templates": 1,
  "hec_templates": 1,
  "dashboard_templates": 1,
  "missing": []
}
```

The asset registry URL in the result is the authoritative list of Google IDs and URLs. Do not hardcode those IDs into portable n8n workflow exports.
