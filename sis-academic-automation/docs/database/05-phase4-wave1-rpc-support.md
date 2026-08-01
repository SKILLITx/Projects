# Phase 4 Wave 1 RPC Support

Migration 009 adds three public service-role RPCs and safely replaces two existing notification RPC implementations.

## New

- `rpc_submit_student_profile_from_form`
- `rpc_submit_enrollment_from_form`
- `rpc_begin_notification_attempt`

## Replaced without signature changes

- `rpc_claim_notifications`
- `rpc_record_notification_attempt`

All functions return one JSON object, validate service-role context, use stable error codes and expose no private schema through PostgREST.
