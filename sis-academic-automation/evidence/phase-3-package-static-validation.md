# Phase 3 Package Static Validation

Validated before packaging:

- six form definitions parse as JSON;
- response queue and Drive plan parse as JSON;
- Apps Script and portal JavaScript pass JavaScript syntax checks;
- 12 required Drive folders are defined;
- transcript, HEC and dashboard template builders exist;
- staff portal contains no service-role credential;
- first-staff and authorization SQL are generated locally through PowerShell;
- required Phase 3 documents and test matrix are present.

- rerun safety verified: provisioning does not clear existing Automation Queue rows;
- campus-administrator portal scope requires an assigned campus;
- simulated authenticated SQL can read its temporary test context after `SET ROLE`.
