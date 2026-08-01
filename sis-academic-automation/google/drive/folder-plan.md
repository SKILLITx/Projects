# Google Drive Folder Plan

The provisioner creates the following hierarchy under `SIS Automation Pilot`:

```text
SIS Automation Pilot/
├── 01 Forms/
├── 02 Response Sheets/
├── 03 Student Documents/
├── 04 Uploaded Marks/
├── 05 Transcript Google Docs/
├── 06 Transcript PDFs/
├── 07 HEC Reports/
├── 08 Dashboard/
├── 09 Failed Files/
├── 10 Archive/
├── 11 Templates/
└── 12 Asset Registry/
```

## Access boundaries

- The root folder must not be public.
- Teachers should receive only the minimum upload/form access they require.
- Transcript, HEC, dashboard and failed-file folders remain staff restricted.
- The n8n Google OAuth identity should have explicit access to only the folders used by its workflows.
- Institution-specific deployments should create separate root folders or enforce institution-specific subfolder permissions.
