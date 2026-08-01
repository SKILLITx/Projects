# Workflow 03 pilot teacher assignment

## Why this patch exists

The marks form captures the submitter's signed-in Google email. The current
pilot account has an active staff profile but no teacher assignment. Workflow
03 must reject a marks submission from an unassigned account.

This migration adds only the scope required for the controlled test:

- Institution: DMU
- Campus: ISB
- Offering: FALL-BA101-ISB
- Section: A
- Staff email: zaidrizwan.278@gmail.com

The existing demo teacher remains assigned. No marks or enrollment data is
changed.
