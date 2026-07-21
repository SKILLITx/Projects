# Known Limitations

## Hosting

The pilot currently depends on Windows 11, npm-installed n8n 2.4.0, local SQLite metadata, local portal hosting, ngrok, and manually maintained credentials.

## Deferred scope

Workflow 06 - HEC Enrollment Reporting and Workflow 10 - Global Error Handler are deferred. Failures that escape workflow-specific branches may require review through n8n execution history and Workflow 09 monitoring.

## Backup operations

Workflow 09 observes backup-verification state but does not execute host-level backup commands. Backup and restore verification remain operator-controlled procedures.

## Portal

The portal is a lightweight controlled-pilot interface, not a complete production frontend. Further mobile, accessibility, and responsive-layout work may be required.

## Workflow catalogue

Five obsolete workflow variants were archived and left inactive. They must remain unpublished. One inactive Workflow 05 variant contains a legacy Crypto-node reference unsupported by the current pilot runtime.

## Scalability and operations

The pilot has not been load-tested for enterprise-scale concurrent usage. Production rollout requires permanent hosting, formal secret management, credential rotation, monitoring, incident response, backup policies, restore drills, support ownership, and capacity planning.
