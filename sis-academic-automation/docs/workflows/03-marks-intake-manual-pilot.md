# Workflow 03 — manual marks pilot

This package completes the controlled manual-entry path of Workflow 03.

## Supported in this package

- Teacher Marks Google Form queue processing
- captured teacher-email verification
- active teacher-assignment verification
- code-to-UUID resolution in a service-role-only public RPC
- one line per student marks parsing
- present, absent and explicitly missing states
- unknown and unenrolled student detection
- duplicate student detection
- assessment maximum-range validation
- omitted enrolled-student detection
- draft submission
- finalization after clean validation
- durable queue outcome and workflow-run logging
- idempotent marks-submission confirmation notification

## Pilot test context

- Institution: DMU
- Campus: ISB
- Term: FALL
- Offering: FALL-BA101-ISB
- Section: A
- Assessment: A1
- Maximum marks: 20
- Students: DMU-0001 through DMU-0008

The CSV/XLSX upload branch is not declared complete by this package. It will
be added to the same Workflow 03 after the manual path passes end to end.
