# Workflow 02 stabilization

This version applies every relevant Workflow 01 correction before testing:

- `Automation Queue` remains the trigger source;
- trigger range is `A1:P`;
- only exact `pending` enrollment rows are processable;
- Code nodes return one object in per-item mode;
- previous-node mappings are item-aware;
- HTTP, PostgREST, business, and network errors are parsed separately;
- start and completion logs use different idempotency keys;
- HTTP requests have finite timeouts and retries;
- skipped rows have an explicit terminal;
- the critical queue update retries and runs before completion logging;
- execution evidence is retained during the pilot;
- the workflow imports inactive and does not overwrite the original.

The shared Apps Script `handleFormSubmit` correction already applies to the
enrollment form because all six form triggers call the same function.
