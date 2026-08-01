# Operational Dashboard Google Sheets Template

The provisioner creates `SIS — Operational Dashboard` with:

- `Dashboard`
- `Metrics`
- `Section_Capacity`
- `Refresh_Log`
- `Instructions`

The `Metrics` tab uses stable keys matching `rpc_get_dashboard_snapshot`. Dashboard cells use lookups rather than fixed cell references to raw workflow output. The Phase 4 dashboard workflow will refresh the metrics and section-capacity rows idempotently.
