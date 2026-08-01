-- Returns the exact IDs needed for the first Workflow 04 live acceptance run.
with latest_finalized as (
  select mb.*
  from public.marks_batches mb
  where mb.batch_status = 'finalized'
  order by mb.created_at desc
  limit 1
)
select jsonb_build_object(
  'marks_batch_id', mb.id,
  'institution_id', mb.institution_id,
  'campus_id', mb.campus_id,
  'course_offering_id', mb.offering_id,
  'section_id', mb.section_id,
  'version_number', mb.version_number,
  'validation_summary', mb.validation_summary,
  'portal_marks_decision_path', '/webhook/staff/rpc_decide_marks_batch',
  'portal_correction_decision_path', '/webhook/staff/rpc_decide_mark_correction',
  'portal_results_publication_path', '/webhook/staff/rpc_publish_results'
) as workflow04_pilot_inputs
from latest_finalized mb;
