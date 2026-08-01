# Workflow 02 — Course and Subject Enrollment Lifecycle

## Trigger

A Google Sheets Trigger consumes new rows from the Enrollment Form `Automation Queue`.

## Durable boundary

`rpc_submit_enrollment_from_form` resolves human-readable codes and calls the existing transactional enrollment engine.

The database validates:

- active student and single active program registration;
- open enrollment period;
- offering and program restrictions;
- required verified documents;
- prerequisites;
- duplicate enrollment;
- maximum load;
- timetable conflict;
- preferred section;
- capacity;
- configured fallback, waitlist, rejection or manual review.

When the form says fallback is not allowed, the wrapper verifies that any successful allocation used the requested section. A fallback allocation causes the wrapper transaction to roll back.

## Ordered preferences

Preferred-section positions remain aligned with their corresponding course codes. An empty first preference such as `, A` is preserved as `["", "A"]` rather than shifted to the wrong course. Duplicate course codes are rejected by the database wrapper.
