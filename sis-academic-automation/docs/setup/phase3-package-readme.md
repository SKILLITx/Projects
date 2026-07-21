# Phase 3 Package Quick Start

From the project directory:

```powershell
& ".\scripts\Test-Phase3Package.ps1"; if ($?) { & ".\scripts\Copy-Phase3Provisioner.ps1" }
```

Expected:

```text
PHASE 3 PACKAGE STATIC CHECK: PASS
Verified 6 form specifications, Google asset provisioner, staff portal and authorization test package.
Phase 3 Google Workspace provisioner copied to the clipboard.
```

Then create a standalone Apps Script project, paste into `Code.gs`, run `provisionPhase3Workspace`, and finally run `verifyPhase3Assets`.
