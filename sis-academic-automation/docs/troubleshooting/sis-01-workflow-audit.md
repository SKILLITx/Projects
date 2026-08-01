# SIS 01 workflow audit and stabilization

## What was happening

The workflow was not behaving randomly. Several behaviors were being combined:

1. **The Google Sheets Trigger can emit more than one newly detected row in one poll.**
   The IF node evaluates each item independently. One batch can therefore show items on both
   the True and False outputs. The same item is not sent to both outputs.

2. **Repeated manual tests can leave multiple waiting trigger executions.**
   A later form submission can be collected by more than one waiting execution, or a poll can
   include older rows together with the newest row. Use one active workflow instead of repeatedly
   starting manual trigger executions.

3. **The False output had no terminal node.**
   Expected skipped rows appeared to make the workflow stop abruptly.

4. **Multi-item mapping was fragile.**
   `Build Student Queue Outcome` and the logging expressions referenced previous nodes through
   `$node["..."].json`. Item-aware references are safer when a trigger emits a batch.

5. **PostgREST business errors were parsed incorrectly.**
   Supabase error responses commonly expose `code` and `message` at the response-body root, while
   the original parser looked only under `body.error`. Valid business failures could therefore be
   reduced to generic `HTTP_400` messages.

6. **Start and completion logs reused one idempotency key.**
   Both used `:workflow-run`, which can cause the completion log to replay the start log instead
   of recording a distinct completion event.

7. **The two completion actions ran in parallel.**
   The canvas could appear to stop at the outcome node while Google Sheets and completion logging
   were still running independently.

8. **Execution evidence was disabled.**
   Successful, failed, and manual execution data were not saved, which made intermittent behavior
   difficult to inspect.

## Stabilized behavior

The stabilized workflow:

- requires queue status to be exactly `pending`;
- adds an explicit skipped-row terminal;
- uses item-aware node references;
- parses network, HTTP, PostgREST, and successful JSON responses separately;
- gives start and completion logs different idempotency keys;
- applies 15-second HTTP timeouts;
- retries the critical Google Sheets status update;
- updates the queue before writing the non-critical completion log;
- saves execution data during pilot testing;
- remains inactive after import.

## Correct operating method

1. Keep the original workflow inactive.
2. Stop every running or waiting manual execution.
3. Import the stabilized workflow.
4. Confirm its existing credentials are selected.
5. Activate the stabilized workflow once.
6. Submit one new Google Form response.
7. Inspect the execution from the Executions page instead of repeatedly clicking
   **Execute workflow**.

## Interpreting the IF node

A batch such as:

- item A: `pending` → True
- item B: `failed` → False

will show activity on both outputs. This is correct batch routing. Compare `Form Response ID`
on each output to see which row followed which path.
