# Workflow 04 acceptance sequence

The package is tested in five grouped stages:

1. Apply the migration and run hosted verification.
2. Import and configure the single Workflow 04 n8n workflow.
3. Approve one finalized pilot marks batch through the authenticated staff
   portal.
4. Publish the pilot course offering, verify course results, GPA, CGPA,
   standing, notifications and idempotent repeated publication.
5. Submit one mark-correction request, approve/apply it, republish the offering,
   and run the bundled durable-outcome SQL.

Negative checks are grouped rather than run as separate manual cycles:

- expired or missing portal token;
- teacher attempting administrative approval;
- unknown batch or correction request;
- proposed marks outside the assessment maximum;
- correction reference mismatch;
- repeated decision/publication;
- publication without approved marks.

The workflow is not considered passed merely because a webhook returns HTTP
success. The final SQL must show durable batch history, correction history,
course results, semester results, cumulative results and notification jobs.
