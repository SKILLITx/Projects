-- Phase 4 Wave 1 hosted verification. Read/write test is fully rolled back.
begin;

select set_config('request.jwt.claim.role', 'service_role', true);

create temporary table phase4_wave1_results (
  test_name text primary key,
  passed boolean not null,
  details jsonb not null default '{}'::jsonb
) on commit drop;

insert into phase4_wave1_results
select 'rpc_catalog',
       count(*) = 27,
       jsonb_build_object('public_rpc_count', count(*))
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'rpc_%';

create temporary table phase4_student_request on commit drop as
select jsonb_build_object(
  'operation', 'student.profile.submit',
  'correlation_id', gen_random_uuid(),
  'idempotency_key', 'phase4-wave1-verification-student',
  'submitted_at', timezone('utc', now()),
  'requester', jsonb_build_object('email','phase4.verification@example.test'),
  'source', jsonb_build_object('channel','verification','source_submission_id','phase4-student-1'),
  'payload', jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'submission_type','New admission/profile',
    'full_name','Phase Four Verification Student',
    'date_of_birth','2005-01-15',
    'primary_email','phase4.verification@example.test',
    'mobile_phone','03000000000',
    'program_code','BSBA',
    'academic_year_code','AY' || to_char(current_date,'YYYY'),
    'admission_term_code','FALL',
    'documents','[]'::jsonb
  )
) as request;

create temporary table phase4_student_first on commit drop as
select public.rpc_submit_student_profile_from_form(request) as response
from phase4_student_request;

create temporary table phase4_student_second on commit drop as
select public.rpc_submit_student_profile_from_form(request) as response
from phase4_student_request;

insert into phase4_wave1_results
select 'student_form_rpc',
       (f.response->>'success')::boolean
       and f.response = s.response
       and f.response#>>'{data,student_number}' like 'PENDING-%',
       jsonb_build_object(
         'success', f.response->'success',
         'idempotent_replay_equal', f.response = s.response,
         'student_number', f.response#>>'{data,student_number}'
       )
from phase4_student_first f cross join phase4_student_second s;

create temporary table phase4_school_guardian_missing on commit drop as
select public.rpc_submit_student_profile_from_form(jsonb_build_object(
  'operation','student.profile.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-school-guardian-missing',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.school@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-school-missing'),
  'payload',jsonb_build_object(
    'institution_code','DCS',
    'campus_code','NORTH',
    'submission_type','New admission/profile',
    'full_name','Phase Four School Guardian Test',
    'date_of_birth','2010-01-01',
    'primary_email','phase4.school@example.test',
    'mobile_phone','03000000002',
    'program_code','OLEVEL',
    'academic_year_code','SY2026',
    'admission_term_code','TERM1',
    'documents','[]'::jsonb
  )
)) as response;

create temporary table phase4_school_guardian_complete on commit drop as
select public.rpc_submit_student_profile_from_form(jsonb_build_object(
  'operation','student.profile.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-school-guardian-complete',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.school.complete@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-school-complete'),
  'payload',jsonb_build_object(
    'institution_code','DCS',
    'campus_code','NORTH',
    'submission_type','New admission/profile',
    'full_name','Phase Four School Complete Student',
    'date_of_birth','2010-02-01',
    'primary_email','phase4.school.complete@example.test',
    'mobile_phone','03000000003',
    'guardian_name','Phase Four Guardian',
    'guardian_phone','03000000004',
    'program_code','OLEVEL',
    'academic_year_code','SY2026',
    'admission_term_code','TERM1',
    'documents','[]'::jsonb
  )
)) as response;

insert into phase4_wave1_results
select 'school_guardian_validation',
       not (m.response->>'success')::boolean
       and m.response#>>'{error,code}' = 'VALIDATION_GUARDIAN_REQUIRED'
       and (c.response->>'success')::boolean,
       jsonb_build_object(
         'missing_guardian_error',m.response#>>'{error,code}',
         'complete_submission_success',c.response->'success',
         'student_number',c.response#>>'{data,student_number}'
       )
from phase4_school_guardian_missing m
cross join phase4_school_guardian_complete c;

create temporary table phase4_duplicate_document on commit drop as
select public.rpc_submit_student_profile_from_form(jsonb_build_object(
  'operation','student.profile.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-duplicate-document',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.duplicate.document@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-duplicate-document'),
  'payload',jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'submission_type','New admission/profile',
    'full_name','Phase Four Duplicate Document Student',
    'date_of_birth','2005-03-15',
    'primary_email','phase4.duplicate.document@example.test',
    'mobile_phone','03000000005',
    'program_code','BSBA',
    'academic_year_code','AY' || to_char(current_date,'YYYY'),
    'admission_term_code','FALL',
    'documents',jsonb_build_array(
      jsonb_build_object('document_code','IDENTITY','url','https://drive.google.com/file/d/phase4-one'),
      jsonb_build_object('document_code','identity','url','https://drive.google.com/file/d/phase4-two')
    )
  )
)) as response;

insert into phase4_wave1_results
select 'student_duplicate_document_rejected',
       not (response->>'success')::boolean
       and response#>>'{error,code}' = 'VALIDATION_DUPLICATE_DOCUMENT_CODE',
       jsonb_build_object(
         'success',response->'success',
         'error_code',response#>>'{error,code}'
       )
from phase4_duplicate_document;

create temporary table phase4_enrollment_response on commit drop as
select public.rpc_submit_enrollment_from_form(jsonb_build_object(
  'operation','enrollment.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-verification-enrollment',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.verification@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-enrollment-1'),
  'payload',jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'student_number',(select response#>>'{data,student_number}' from phase4_student_first),
    'program_code','BSBA',
    'term_code','FALL',
    'course_codes',jsonb_build_array('BA101'),
    'preferred_section_codes',jsonb_build_array('A'),
    'allow_fallback',false
  )
)) as response;

insert into phase4_wave1_results
select 'enrollment_missing_documents',
       (response->>'success')::boolean
       and jsonb_typeof(response#>'{data,items}') = 'array',
       jsonb_build_object(
         'success', response->'success',
         'overall_outcome', response#>>'{data,overall_outcome}',
         'item_count', jsonb_array_length(response#>'{data,items}')
       )
from phase4_enrollment_response;

-- Complete the required document set and verify a valid section allocation.
insert into public.student_documents (
  institution_id, student_id, requirement_id, file_name,
  storage_provider, storage_object_id, document_status, verified_at
)
select dr.institution_id,
       (select response#>>'{data,student_id}' from phase4_student_first)::uuid,
       dr.id,
       dr.document_code || '.pdf',
       'verification',
       'phase4-valid:' || dr.document_code,
       'verified',
       timezone('utc', now())
from public.document_requirements dr
where dr.institution_id = app.demo_uuid('institution:university')
  and (
    dr.program_id is null
    or dr.program_id = app.demo_uuid('program:dmu:bsba')
  );

create temporary table phase4_valid_enrollment on commit drop as
select public.rpc_submit_enrollment_from_form(jsonb_build_object(
  'operation','enrollment.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-verification-valid-enrollment',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.verification@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-enrollment-valid'),
  'payload',jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'student_number',(select response#>>'{data,student_number}' from phase4_student_first),
    'program_code','BSBA',
    'term_code','FALL',
    'course_codes',jsonb_build_array('BA101'),
    'preferred_section_codes',jsonb_build_array('A'),
    'allow_fallback',false
  )
)) as response;

insert into phase4_wave1_results
select 'enrollment_valid_allocation',
       (response->>'success')::boolean
       and response#>>'{data,overall_outcome}' = 'enrolled'
       and response#>>'{data,items,0,outcome}' = 'enrolled'
       and response#>>'{data,items,0,section_id}' = app.demo_uuid('section:dmu:ba101:a')::text,
       jsonb_build_object(
         'success', response->'success',
         'overall_outcome', response#>>'{data,overall_outcome}',
         'section_id', response#>>'{data,items,0,section_id}'
       )
from phase4_valid_enrollment;

-- Duplicate course codes are rejected before any enrollment request is created.
create temporary table phase4_duplicate_course on commit drop as
select public.rpc_submit_enrollment_from_form(jsonb_build_object(
  'operation','enrollment.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-verification-duplicate-course',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.verification@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-enrollment-duplicate'),
  'payload',jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'student_number',(select response#>>'{data,student_number}' from phase4_student_first),
    'program_code','BSBA',
    'term_code','FALL',
    'course_codes',jsonb_build_array('SQL201','sql201'),
    'preferred_section_codes',jsonb_build_array('A','A'),
    'allow_fallback',true
  )
)) as response;

insert into phase4_wave1_results
select 'enrollment_duplicate_course_rejected',
       not (response->>'success')::boolean
       and response#>>'{error,code}' = 'VALIDATION_DUPLICATE_COURSE_CODE',
       jsonb_build_object(
         'success', response->'success',
         'error_code', response#>>'{error,code}'
       )
from phase4_duplicate_course;

-- A second student proves that a forbidden fallback rolls back the core RPC side effects.
create temporary table phase4_fallback_student on commit drop as
select public.rpc_submit_student_profile_from_form(jsonb_build_object(
  'operation','student.profile.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-verification-fallback-student',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.fallback@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-fallback-student'),
  'payload',jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'submission_type','New admission/profile',
    'full_name','Phase Four Fallback Student',
    'date_of_birth','2005-02-15',
    'primary_email','phase4.fallback@example.test',
    'mobile_phone','03000000001',
    'program_code','BSBA',
    'academic_year_code','AY' || to_char(current_date,'YYYY'),
    'admission_term_code','FALL',
    'documents','[]'::jsonb
  )
)) as response;

insert into public.student_documents (
  institution_id, student_id, requirement_id, file_name,
  storage_provider, storage_object_id, document_status, verified_at
)
select dr.institution_id,
       (select response#>>'{data,student_id}' from phase4_fallback_student)::uuid,
       dr.id,
       dr.document_code || '.pdf',
       'verification',
       'phase4-fallback:' || dr.document_code,
       'verified',
       timezone('utc', now())
from public.document_requirements dr
where dr.institution_id = app.demo_uuid('institution:university')
  and (
    dr.program_id is null
    or dr.program_id = app.demo_uuid('program:dmu:bsba')
  );

update public.sections
set capacity = 0
where id = app.demo_uuid('section:dmu:ba101:b');

create temporary table phase4_forbidden_fallback on commit drop as
select public.rpc_submit_enrollment_from_form(jsonb_build_object(
  'operation','enrollment.submit',
  'correlation_id',gen_random_uuid(),
  'idempotency_key','phase4-wave1-verification-forbidden-fallback',
  'submitted_at',timezone('utc',now()),
  'requester',jsonb_build_object('email','phase4.fallback@example.test'),
  'source',jsonb_build_object('channel','verification','source_submission_id','phase4-forbidden-fallback'),
  'payload',jsonb_build_object(
    'institution_code','DMU',
    'campus_code','ISB',
    'student_number',(select response#>>'{data,student_number}' from phase4_fallback_student),
    'program_code','BSBA',
    'term_code','FALL',
    'course_codes',jsonb_build_array('BA101'),
    'preferred_section_codes',jsonb_build_array('B'),
    'allow_fallback',false
  )
)) as response;

insert into phase4_wave1_results
select 'enrollment_forbidden_fallback_rolled_back',
       not (response->>'success')::boolean
       and response#>>'{error,code}' = 'ENROLLMENT_FALLBACK_NOT_ALLOWED'
       and not exists (
         select 1
         from public.enrollments e
         where e.student_id = (select response#>>'{data,student_id}' from phase4_fallback_student)::uuid
       ),
       jsonb_build_object(
         'success', response->'success',
         'error_code', response#>>'{error,code}',
         'enrollment_rows', (
           select count(*)
           from public.enrollments e
           where e.student_id = (select response#>>'{data,student_id}' from phase4_fallback_student)::uuid
         )
       )
from phase4_forbidden_fallback;

create temporary table phase4_outbox on commit drop as
with inserted as (
  insert into ops.notification_outbox (
    institution_id, campus_id, channel, notification_type, recipient_address,
    subject, template_code, payload, correlation_id, idempotency_key,
    claimed_at, claimed_by, job_status
  )
  select i.id, c.id, 'email', 'verification.notification',
         'phase4.notification@example.test', 'Verification', 'generic',
         '{}'::jsonb, gen_random_uuid(), 'phase4-wave1-notification',
         timezone('utc',now()), 'phase4-test-worker', 'claimed'
  from public.institutions i
  join public.campuses c on c.institution_id=i.id
  where i.code='DMU' and c.code='ISB'
  returning *
)
select * from inserted;

create temporary table phase4_begin_first on commit drop as
select public.rpc_begin_notification_attempt(jsonb_build_object(
  'correlation_id',gen_random_uuid(),
  'payload',jsonb_build_object(
    'outbox_id',id,'attempt_number',1,'worker_id','phase4-test-worker','provider','gmail'
  )
)) as response
from phase4_outbox;

create temporary table phase4_begin_second on commit drop as
select public.rpc_begin_notification_attempt(jsonb_build_object(
  'correlation_id',gen_random_uuid(),
  'payload',jsonb_build_object(
    'outbox_id',id,'attempt_number',1,'worker_id','phase4-test-worker','provider','gmail'
  )
)) as response
from phase4_outbox;

create temporary table phase4_record_first on commit drop as
select public.rpc_record_notification_attempt(jsonb_build_object(
  'correlation_id',gen_random_uuid(),
  'payload',jsonb_build_object(
    'outbox_id',(select id from phase4_outbox),
    'attempt_number',1,
    'delivery_status','delivered',
    'provider','gmail',
    'provider_message_id','phase4-provider-message',
    'retryable',false
  )
)) as response;

create temporary table phase4_record_second on commit drop as
select public.rpc_record_notification_attempt(jsonb_build_object(
  'correlation_id',gen_random_uuid(),
  'payload',jsonb_build_object(
    'outbox_id',(select id from phase4_outbox),
    'attempt_number',1,
    'delivery_status','delivered',
    'provider','gmail',
    'provider_message_id','phase4-provider-message',
    'retryable',false
  )
)) as response;

insert into phase4_wave1_results
select 'notification_attempt_idempotency',
       (b1.response#>>'{data,should_send}')::boolean
       and not (b2.response#>>'{data,should_send}')::boolean
       and (r1.response->>'success')::boolean
       and (r2.response->>'success')::boolean
       and (select count(*) from ops.notification_deliveries where outbox_id=(select id from phase4_outbox)) = 1
       and (select job_status from ops.notification_outbox where id=(select id from phase4_outbox)) = 'completed',
       jsonb_build_object(
         'first_begin_should_send',b1.response#>'{data,should_send}',
         'second_begin_should_send',b2.response#>'{data,should_send}',
         'delivery_rows',(select count(*) from ops.notification_deliveries where outbox_id=(select id from phase4_outbox)),
         'job_status',(select job_status from ops.notification_outbox where id=(select id from phase4_outbox)),
         'record_replay',r2.response#>'{data,idempotent_replay}'
       )
from phase4_begin_first b1
cross join phase4_begin_second b2
cross join phase4_record_first r1
cross join phase4_record_second r2;

select jsonb_build_object(
  'suite','phase4-wave1-hosted-verification',
  'success',bool_and(passed),
  'tests',jsonb_object_agg(test_name,details order by test_name),
  'test_count',count(*),
  'failed_tests',coalesce(jsonb_agg(test_name order by test_name) filter (where not passed),'[]'::jsonb),
  'transaction_rolled_back',true
) as result
from phase4_wave1_results;

rollback;
