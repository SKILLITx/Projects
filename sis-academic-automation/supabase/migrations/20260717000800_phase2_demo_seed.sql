-- Phase 2 accelerated completion, migration 8:
-- deterministic fictional demonstration data for a university and Cambridge school.
-- All names, identifiers and contact details are synthetic.

begin;

create or replace function app.demo_uuid(p_key text)
returns uuid
language sql
immutable
security invoker
set search_path = pg_catalog
as $function$
  select (
    substr(md5(p_key),1,8) || '-' ||
    substr(md5(p_key),9,4) || '-' ||
    substr(md5(p_key),13,4) || '-' ||
    substr(md5(p_key),17,4) || '-' ||
    substr(md5(p_key),21,12)
  )::uuid;
$function$;
revoke all on function app.demo_uuid(text) from public, anon, authenticated;
grant execute on function app.demo_uuid(text) to service_role;

insert into public.institutions (
  id, code, name, institution_type, academic_model, timezone, status
)
values
  (app.demo_uuid('institution:university'), 'DMU', 'Demo Metropolitan University', 'university', 'credit_hour', 'Asia/Karachi', 'active'),
  (app.demo_uuid('institution:school'), 'DCS', 'Demo Cambridge School', 'cambridge_school', 'cambridge', 'Asia/Karachi', 'active');

insert into public.campuses (
  id, institution_id, code, name, city, country_code, status
)
values
  (app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('institution:university'), 'ISB', 'Islamabad Campus', 'Islamabad', 'PK', 'active'),
  (app.demo_uuid('campus:dmu:faisalabad'), app.demo_uuid('institution:university'), 'FSD', 'Faisalabad Campus', 'Faisalabad', 'PK', 'active'),
  (app.demo_uuid('campus:dcs:north'), app.demo_uuid('institution:school'), 'NORTH', 'North Campus', 'Islamabad', 'PK', 'active'),
  (app.demo_uuid('campus:dcs:south'), app.demo_uuid('institution:school'), 'SOUTH', 'South Campus', 'Rawalpindi', 'PK', 'active');

insert into public.institution_settings (
  id, institution_id, version, effective_from, enrollment_policy,
  waitlist_behavior, maximum_credit_load, transcript_disclaimer,
  transcript_settings, hec_report_settings, notification_settings, status
)
values
  (
    app.demo_uuid('institution-settings:dmu:1'),
    app.demo_uuid('institution:university'),
    1, current_date - 365,
    '{"allow_section_fallback":true,"requires_verified_documents":true}'::jsonb,
    'waitlist', 18,
    'This demonstration transcript is generated for pilot testing.',
    '{"verification_enabled":true}'::jsonb,
    '{"template_type":"demonstration"}'::jsonb,
    '{"default_channel":"email"}'::jsonb,
    'active'
  ),
  (
    app.demo_uuid('institution-settings:dcs:1'),
    app.demo_uuid('institution:school'),
    1, current_date - 365,
    '{"allow_section_fallback":true,"requires_verified_documents":true}'::jsonb,
    'waitlist', 8,
    'This demonstration school record is generated for pilot testing.',
    '{"verification_enabled":true}'::jsonb,
    '{"template_type":"demonstration"}'::jsonb,
    '{"default_channel":"email"}'::jsonb,
    'active'
  );

insert into public.academic_years (
  id, institution_id, code, name, starts_on, ends_on, status
)
values
  (
    app.demo_uuid('academic-year:dmu:current'),
    app.demo_uuid('institution:university'),
    'AY' || to_char(current_date, 'YYYY'),
    'Academic Year ' || to_char(current_date, 'YYYY'),
    current_date - 60, current_date + 305, 'active'
  ),
  (
    app.demo_uuid('academic-year:dcs:current'),
    app.demo_uuid('institution:school'),
    'SY' || to_char(current_date, 'YYYY'),
    'School Year ' || to_char(current_date, 'YYYY'),
    current_date - 60, current_date + 305, 'active'
  );

insert into public.terms (
  id, institution_id, academic_year_id, code, name, term_type,
  sequence_number, starts_on, ends_on, status
)
values
  (
    app.demo_uuid('term:dmu:fall'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('academic-year:dmu:current'),
    'FALL', 'Fall Semester', 'semester', 1,
    current_date - 30, current_date + 120, 'active'
  ),
  (
    app.demo_uuid('term:dmu:spring'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('academic-year:dmu:current'),
    'SPRING', 'Spring Semester', 'semester', 2,
    current_date + 130, current_date + 280, 'draft'
  ),
  (
    app.demo_uuid('term:dcs:term1'),
    app.demo_uuid('institution:school'),
    app.demo_uuid('academic-year:dcs:current'),
    'TERM1', 'Term 1', 'term', 1,
    current_date - 30, current_date + 90, 'active'
  ),
  (
    app.demo_uuid('term:dcs:term2'),
    app.demo_uuid('institution:school'),
    app.demo_uuid('academic-year:dcs:current'),
    'TERM2', 'Term 2', 'term', 2,
    current_date + 100, current_date + 220, 'draft'
  );

insert into public.enrollment_periods (
  id, institution_id, campus_id, term_id, name, opens_at, closes_at,
  settings_version, status
)
values
  (
    app.demo_uuid('enrollment-period:dmu:islamabad'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('campus:dmu:islamabad'),
    app.demo_uuid('term:dmu:fall'),
    'Fall Enrollment — Islamabad',
    timezone('utc', now()) - interval '30 days',
    timezone('utc', now()) + interval '30 days',
    1, 'active'
  ),
  (
    app.demo_uuid('enrollment-period:dmu:faisalabad'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('campus:dmu:faisalabad'),
    app.demo_uuid('term:dmu:fall'),
    'Fall Enrollment — Faisalabad',
    timezone('utc', now()) - interval '30 days',
    timezone('utc', now()) + interval '30 days',
    1, 'active'
  ),
  (
    app.demo_uuid('enrollment-period:dcs:north'),
    app.demo_uuid('institution:school'),
    app.demo_uuid('campus:dcs:north'),
    app.demo_uuid('term:dcs:term1'),
    'Term 1 Subject Selection — North',
    timezone('utc', now()) - interval '30 days',
    timezone('utc', now()) + interval '30 days',
    1, 'active'
  ),
  (
    app.demo_uuid('enrollment-period:dcs:south'),
    app.demo_uuid('institution:school'),
    app.demo_uuid('campus:dcs:south'),
    app.demo_uuid('term:dcs:term1'),
    'Term 1 Subject Selection — South',
    timezone('utc', now()) - interval '30 days',
    timezone('utc', now()) + interval '30 days',
    1, 'active'
  );

insert into public.departments (id, institution_id, code, name, status)
values
  (app.demo_uuid('department:dmu:computing'), app.demo_uuid('institution:university'), 'CS', 'Computing', 'active'),
  (app.demo_uuid('department:dmu:business'), app.demo_uuid('institution:university'), 'BUS', 'Business', 'active'),
  (app.demo_uuid('department:dcs:sciences'), app.demo_uuid('institution:school'), 'SCI', 'Sciences', 'active'),
  (app.demo_uuid('department:dcs:humanities'), app.demo_uuid('institution:school'), 'HUM', 'Humanities', 'active');

insert into public.programs (
  id, institution_id, department_id, code, name, academic_model,
  level_name, duration_terms, default_maximum_load, status
)
values
  (
    app.demo_uuid('program:dmu:bsba'), app.demo_uuid('institution:university'),
    app.demo_uuid('department:dmu:business'), 'BSBA',
    'BS Business Analytics', 'credit_hour', 'Undergraduate', 8, 18, 'active'
  ),
  (
    app.demo_uuid('program:dmu:bscs'), app.demo_uuid('institution:university'),
    app.demo_uuid('department:dmu:computing'), 'BSCS',
    'BS Computer Science', 'credit_hour', 'Undergraduate', 8, 18, 'active'
  ),
  (
    app.demo_uuid('program:dcs:olevel'), app.demo_uuid('institution:school'),
    app.demo_uuid('department:dcs:sciences'), 'OLEVEL',
    'Cambridge O Level', 'cambridge', 'O Level', 6, 8, 'active'
  ),
  (
    app.demo_uuid('program:dcs:alevel'), app.demo_uuid('institution:school'),
    app.demo_uuid('department:dcs:sciences'), 'ALEVEL',
    'Cambridge A Level', 'cambridge', 'A Level', 4, 5, 'active'
  );

insert into public.grading_policies (
  id, institution_id, program_id, name, version, effective_from,
  pass_mark, calculation_method, status
)
values
  (
    app.demo_uuid('grading:dmu:1'), app.demo_uuid('institution:university'),
    null, 'University 4.00 Scale', 1, current_date - 365, 50,
    '{"rounding_scale":2,"gpa_scale":4}'::jsonb, 'active'
  ),
  (
    app.demo_uuid('grading:dcs:1'), app.demo_uuid('institution:school'),
    null, 'Cambridge Demonstration Scale', 1, current_date - 365, 50,
    '{"rounding_scale":2,"gpa_scale":4}'::jsonb, 'active'
  );

insert into public.grade_scales (
  id, institution_id, grading_policy_id, minimum_score, maximum_score,
  letter_grade, grade_point, outcome_code, display_order
)
values
  (app.demo_uuid('scale:dmu:a'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 85, 100, 'A', 4.00, 'pass', 1),
  (app.demo_uuid('scale:dmu:a-'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 80, 84.99, 'A-', 3.67, 'pass', 2),
  (app.demo_uuid('scale:dmu:b+'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 75, 79.99, 'B+', 3.33, 'pass', 3),
  (app.demo_uuid('scale:dmu:b'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 70, 74.99, 'B', 3.00, 'pass', 4),
  (app.demo_uuid('scale:dmu:c+'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 65, 69.99, 'C+', 2.67, 'pass', 5),
  (app.demo_uuid('scale:dmu:c'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 60, 64.99, 'C', 2.00, 'pass', 6),
  (app.demo_uuid('scale:dmu:d'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 50, 59.99, 'D', 1.00, 'pass', 7),
  (app.demo_uuid('scale:dmu:f'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 0, 49.99, 'F', 0.00, 'fail', 8),
  (app.demo_uuid('scale:dcs:a*'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 90, 100, 'A*', 4.00, 'pass', 1),
  (app.demo_uuid('scale:dcs:a'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 80, 89.99, 'A', 3.67, 'pass', 2),
  (app.demo_uuid('scale:dcs:b'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 70, 79.99, 'B', 3.00, 'pass', 3),
  (app.demo_uuid('scale:dcs:c'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 60, 69.99, 'C', 2.00, 'pass', 4),
  (app.demo_uuid('scale:dcs:d'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 50, 59.99, 'D', 1.00, 'pass', 5),
  (app.demo_uuid('scale:dcs:u'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 0, 49.99, 'U', 0.00, 'fail', 6);

insert into public.academic_standing_rules (
  id, institution_id, grading_policy_id, minimum_cgpa, maximum_cgpa,
  standing_code, standing_label, at_risk, display_order
)
values
  (app.demo_uuid('standing:dmu:good'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 2.00, 4.00, 'GOOD', 'Good Standing', false, 1),
  (app.demo_uuid('standing:dmu:warning'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 1.50, 1.99, 'WARNING', 'Academic Warning', true, 2),
  (app.demo_uuid('standing:dmu:probation'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 0.00, 1.49, 'PROBATION', 'Academic Probation', true, 3),
  (app.demo_uuid('standing:dcs:good'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 2.00, 4.00, 'GOOD', 'Good Standing', false, 1),
  (app.demo_uuid('standing:dcs:atrisk'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 0.00, 1.99, 'AT_RISK', 'At Risk', true, 2);

insert into public.enrollment_policies (
  id, institution_id, program_id, version, effective_from, maximum_load,
  full_section_behavior, allow_section_fallback, requires_verified_documents,
  allow_waitlist_promotion, policy, status
)
values
  (
    app.demo_uuid('enrollment-policy:dmu:1'), app.demo_uuid('institution:university'),
    null, 1, current_date - 365, 18, 'waitlist', true, true, true,
    '{"default_behavior":"waitlist"}'::jsonb, 'active'
  ),
  (
    app.demo_uuid('enrollment-policy:dcs:1'), app.demo_uuid('institution:school'),
    null, 1, current_date - 365, 8, 'waitlist', true, true, true,
    '{"default_behavior":"waitlist"}'::jsonb, 'active'
  );

insert into public.transcript_settings (
  id, institution_id, version, effective_from, reference_prefix,
  disclaimer, template_configuration, status
)
values
  (
    app.demo_uuid('transcript-settings:dmu:1'), app.demo_uuid('institution:university'),
    1, current_date - 365, 'DMU-TR',
    'Demonstration transcript for controlled pilot testing.',
    '{"template_name":"DMU Transcript Demo"}'::jsonb, 'active'
  ),
  (
    app.demo_uuid('transcript-settings:dcs:1'), app.demo_uuid('institution:school'),
    1, current_date - 365, 'DCS-TR',
    'Demonstration academic record for controlled pilot testing.',
    '{"template_name":"DCS Academic Record Demo"}'::jsonb, 'active'
  );

insert into public.notification_settings (
  id, institution_id, version, effective_from, sender_name, reply_to_email,
  configuration, status
)
values
  (
    app.demo_uuid('notification-settings:dmu:1'), app.demo_uuid('institution:university'),
    1, current_date - 365, 'DMU Academic Office', 'no-reply-dmu@example.test',
    '{"channel":"email"}'::jsonb, 'active'
  ),
  (
    app.demo_uuid('notification-settings:dcs:1'), app.demo_uuid('institution:school'),
    1, current_date - 365, 'DCS Academic Office', 'no-reply-dcs@example.test',
    '{"channel":"email"}'::jsonb, 'active'
  );

insert into public.hec_report_settings (
  id, institution_id, version, effective_from, template_label,
  configuration, status
)
values
  (
    app.demo_uuid('hec-settings:dmu:1'), app.demo_uuid('institution:university'),
    1, current_date - 365, 'Demonstration HEC Enrollment Format',
    '{"columns":["student_number","student_name","program","course","section"]}'::jsonb,
    'active'
  ),
  (
    app.demo_uuid('hec-settings:dcs:1'), app.demo_uuid('institution:school'),
    1, current_date - 365, 'Demonstration School Enrollment Format',
    '{"columns":["student_number","student_name","program","subject","section"]}'::jsonb,
    'active'
  );

insert into public.rooms (id, institution_id, campus_id, code, name, capacity, status)
values
  (app.demo_uuid('room:dmu:islamabad:a101'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), 'A101', 'Lecture Room A101', 30, 'active'),
  (app.demo_uuid('room:dmu:islamabad:lab1'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), 'LAB1', 'Computing Lab 1', 25, 'active'),
  (app.demo_uuid('room:dmu:faisalabad:b201'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:faisalabad'), 'B201', 'Lecture Room B201', 30, 'active'),
  (app.demo_uuid('room:dcs:north:s1'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), 'S1', 'Science Room 1', 25, 'active'),
  (app.demo_uuid('room:dcs:north:m1'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), 'M1', 'Mathematics Room 1', 25, 'active'),
  (app.demo_uuid('room:dcs:south:s2'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), 'S2', 'Science Room 2', 25, 'active');

insert into public.courses (
  id, institution_id, department_id, code, title, course_kind,
  credit_hours, subject_load, level_number, status
)
values
  (app.demo_uuid('course:dmu:ba101'), app.demo_uuid('institution:university'), app.demo_uuid('department:dmu:business'), 'BA101', 'Introduction to Business Analytics', 'course', 3, 1, 1, 'active'),
  (app.demo_uuid('course:dmu:stat101'), app.demo_uuid('institution:university'), app.demo_uuid('department:dmu:business'), 'STAT101', 'Statistics for Business', 'course', 3, 1, 1, 'active'),
  (app.demo_uuid('course:dmu:sql201'), app.demo_uuid('institution:university'), app.demo_uuid('department:dmu:computing'), 'SQL201', 'Database Analytics', 'course', 3, 1, 2, 'active'),
  (app.demo_uuid('course:dmu:ai301'), app.demo_uuid('institution:university'), app.demo_uuid('department:dmu:computing'), 'AI301', 'Applied Artificial Intelligence', 'course', 3, 1, 3, 'active'),
  (app.demo_uuid('course:dmu:fin201'), app.demo_uuid('institution:university'), app.demo_uuid('department:dmu:business'), 'FIN201', 'Business Finance', 'course', 3, 1, 2, 'active'),
  (app.demo_uuid('course:dcs:math'), app.demo_uuid('institution:school'), app.demo_uuid('department:dcs:sciences'), 'MATH', 'Mathematics', 'subject', 0, 1, 10, 'active'),
  (app.demo_uuid('course:dcs:physics'), app.demo_uuid('institution:school'), app.demo_uuid('department:dcs:sciences'), 'PHYSICS', 'Physics', 'subject', 0, 1, 10, 'active'),
  (app.demo_uuid('course:dcs:chemistry'), app.demo_uuid('institution:school'), app.demo_uuid('department:dcs:sciences'), 'CHEM', 'Chemistry', 'subject', 0, 1, 10, 'active'),
  (app.demo_uuid('course:dcs:english'), app.demo_uuid('institution:school'), app.demo_uuid('department:dcs:humanities'), 'ENGLISH', 'English Language', 'subject', 0, 1, 10, 'active'),
  (app.demo_uuid('course:dcs:cs'), app.demo_uuid('institution:school'), app.demo_uuid('department:dcs:sciences'), 'CS', 'Computer Science', 'subject', 0, 1, 10, 'active');

insert into public.course_prerequisites (
  id, institution_id, course_id, prerequisite_course_id,
  minimum_letter_grade, minimum_grade_point, rule_group, status
)
values
  (
    app.demo_uuid('prereq:dmu:sql201:stat101'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('course:dmu:sql201'),
    app.demo_uuid('course:dmu:stat101'),
    'D', 1.00, 1, 'active'
  ),
  (
    app.demo_uuid('prereq:dmu:ai301:sql201'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('course:dmu:ai301'),
    app.demo_uuid('course:dmu:sql201'),
    'C', 2.00, 1, 'active'
  );

insert into public.course_equivalencies (
  id, institution_id, course_id, equivalent_course_id, status
)
values
  (
    app.demo_uuid('equiv:dmu:ba101:stat101'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('course:dmu:ba101'),
    app.demo_uuid('course:dmu:stat101'),
    'inactive'
  );

insert into public.course_offerings (
  id, institution_id, campus_id, term_id, course_id, program_id,
  grading_policy_id, enrollment_policy_id, offering_code, status
)
values
  (app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('term:dmu:fall'), app.demo_uuid('course:dmu:ba101'), app.demo_uuid('program:dmu:bsba'), app.demo_uuid('grading:dmu:1'), app.demo_uuid('enrollment-policy:dmu:1'), 'FALL-BA101-ISB', 'open'),
  (app.demo_uuid('offering:dmu:islamabad:stat101'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('term:dmu:fall'), app.demo_uuid('course:dmu:stat101'), app.demo_uuid('program:dmu:bsba'), app.demo_uuid('grading:dmu:1'), app.demo_uuid('enrollment-policy:dmu:1'), 'FALL-STAT101-ISB', 'open'),
  (app.demo_uuid('offering:dmu:islamabad:sql201'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('term:dmu:fall'), app.demo_uuid('course:dmu:sql201'), app.demo_uuid('program:dmu:bsba'), app.demo_uuid('grading:dmu:1'), app.demo_uuid('enrollment-policy:dmu:1'), 'FALL-SQL201-ISB', 'open'),
  (app.demo_uuid('offering:dmu:faisalabad:ba101'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:faisalabad'), app.demo_uuid('term:dmu:fall'), app.demo_uuid('course:dmu:ba101'), app.demo_uuid('program:dmu:bsba'), app.demo_uuid('grading:dmu:1'), app.demo_uuid('enrollment-policy:dmu:1'), 'FALL-BA101-FSD', 'open'),
  (app.demo_uuid('offering:dcs:north:math'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('term:dcs:term1'), app.demo_uuid('course:dcs:math'), app.demo_uuid('program:dcs:olevel'), app.demo_uuid('grading:dcs:1'), app.demo_uuid('enrollment-policy:dcs:1'), 'TERM1-MATH-NORTH', 'open'),
  (app.demo_uuid('offering:dcs:north:physics'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('term:dcs:term1'), app.demo_uuid('course:dcs:physics'), app.demo_uuid('program:dcs:olevel'), app.demo_uuid('grading:dcs:1'), app.demo_uuid('enrollment-policy:dcs:1'), 'TERM1-PHYSICS-NORTH', 'open'),
  (app.demo_uuid('offering:dcs:south:math'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), app.demo_uuid('term:dcs:term1'), app.demo_uuid('course:dcs:math'), app.demo_uuid('program:dcs:olevel'), app.demo_uuid('grading:dcs:1'), app.demo_uuid('enrollment-policy:dcs:1'), 'TERM1-MATH-SOUTH', 'open'),
  (app.demo_uuid('offering:dcs:south:english'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), app.demo_uuid('term:dcs:term1'), app.demo_uuid('course:dcs:english'), app.demo_uuid('program:dcs:olevel'), app.demo_uuid('grading:dcs:1'), app.demo_uuid('enrollment-policy:dcs:1'), 'TERM1-ENGLISH-SOUTH', 'open');

insert into public.sections (
  id, institution_id, campus_id, offering_id, code, room_id, capacity, status
)
values
  (app.demo_uuid('section:dmu:ba101:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:ba101'), 'A', app.demo_uuid('room:dmu:islamabad:a101'), 12, 'open'),
  (app.demo_uuid('section:dmu:ba101:b'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:ba101'), 'B', app.demo_uuid('room:dmu:islamabad:lab1'), 2, 'open'),
  (app.demo_uuid('section:dmu:stat101:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:stat101'), 'A', app.demo_uuid('room:dmu:islamabad:a101'), 15, 'open'),
  (app.demo_uuid('section:dmu:sql201:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:sql201'), 'A', app.demo_uuid('room:dmu:islamabad:lab1'), 10, 'open'),
  (app.demo_uuid('section:dmu:fsd:ba101:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:faisalabad'), app.demo_uuid('offering:dmu:faisalabad:ba101'), 'A', app.demo_uuid('room:dmu:faisalabad:b201'), 20, 'open'),
  (app.demo_uuid('section:dcs:north:math:a'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('offering:dcs:north:math'), 'A', app.demo_uuid('room:dcs:north:m1'), 12, 'open'),
  (app.demo_uuid('section:dcs:north:physics:a'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('offering:dcs:north:physics'), 'A', app.demo_uuid('room:dcs:north:s1'), 12, 'open'),
  (app.demo_uuid('section:dcs:south:math:a'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), app.demo_uuid('offering:dcs:south:math'), 'A', app.demo_uuid('room:dcs:south:s2'), 12, 'open'),
  (app.demo_uuid('section:dcs:south:english:a'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), app.demo_uuid('offering:dcs:south:english'), 'A', app.demo_uuid('room:dcs:south:s2'), 12, 'open');

insert into public.section_schedules (
  id, institution_id, campus_id, section_id, room_id,
  day_of_week, starts_at, ends_at
)
values
  (app.demo_uuid('schedule:dmu:ba101:a:mon'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('section:dmu:ba101:a'), app.demo_uuid('room:dmu:islamabad:a101'), 1, '09:00', '10:30'),
  (app.demo_uuid('schedule:dmu:ba101:b:mon'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('section:dmu:ba101:b'), app.demo_uuid('room:dmu:islamabad:lab1'), 1, '11:00', '12:30'),
  (app.demo_uuid('schedule:dmu:stat101:a:mon'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('section:dmu:stat101:a'), app.demo_uuid('room:dmu:islamabad:a101'), 1, '09:30', '11:00'),
  (app.demo_uuid('schedule:dmu:sql201:a:tue'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('section:dmu:sql201:a'), app.demo_uuid('room:dmu:islamabad:lab1'), 2, '10:00', '12:00'),
  (app.demo_uuid('schedule:dmu:fsd:ba101:a:mon'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:faisalabad'), app.demo_uuid('section:dmu:fsd:ba101:a'), app.demo_uuid('room:dmu:faisalabad:b201'), 1, '09:00', '10:30'),
  (app.demo_uuid('schedule:dcs:north:math:a:mon'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('section:dcs:north:math:a'), app.demo_uuid('room:dcs:north:m1'), 1, '08:00', '09:00'),
  (app.demo_uuid('schedule:dcs:north:physics:a:tue'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('section:dcs:north:physics:a'), app.demo_uuid('room:dcs:north:s1'), 2, '09:00', '10:00'),
  (app.demo_uuid('schedule:dcs:south:math:a:mon'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), app.demo_uuid('section:dcs:south:math:a'), app.demo_uuid('room:dcs:south:s2'), 1, '08:00', '09:00'),
  (app.demo_uuid('schedule:dcs:south:english:a:wed'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:south'), app.demo_uuid('section:dcs:south:english:a'), app.demo_uuid('room:dcs:south:s2'), 3, '10:00', '11:00');

insert into public.staff_profiles (
  id, email, full_name, employee_code, status
)
values
  (app.demo_uuid('staff:dmu:teacher1'), 'teacher1.dmu@example.test', 'Demo Teacher One', 'DMU-T001', 'active'),
  (app.demo_uuid('staff:dmu:teacher2'), 'teacher2.dmu@example.test', 'Demo Teacher Two', 'DMU-T002', 'active'),
  (app.demo_uuid('staff:dcs:teacher1'), 'teacher1.dcs@example.test', 'Demo School Teacher One', 'DCS-T001', 'active'),
  (app.demo_uuid('staff:dcs:teacher2'), 'teacher2.dcs@example.test', 'Demo School Teacher Two', 'DCS-T002', 'active'),
  (app.demo_uuid('staff:demo:registrar'), 'registrar@example.test', 'Demo Registrar', 'REG-001', 'active'),
  (app.demo_uuid('staff:demo:superadmin'), 'superadmin@example.test', 'Demo Super Administrator', 'SUP-001', 'active');

insert into public.role_assignments (
  id, staff_profile_id, institution_id, role, status
)
values
  (app.demo_uuid('role:dmu:teacher1'), app.demo_uuid('staff:dmu:teacher1'), app.demo_uuid('institution:university'), 'teacher', 'active'),
  (app.demo_uuid('role:dmu:teacher2'), app.demo_uuid('staff:dmu:teacher2'), app.demo_uuid('institution:university'), 'teacher', 'active'),
  (app.demo_uuid('role:dcs:teacher1'), app.demo_uuid('staff:dcs:teacher1'), app.demo_uuid('institution:school'), 'teacher', 'active'),
  (app.demo_uuid('role:dcs:teacher2'), app.demo_uuid('staff:dcs:teacher2'), app.demo_uuid('institution:school'), 'teacher', 'active'),
  (app.demo_uuid('role:dmu:registrar'), app.demo_uuid('staff:demo:registrar'), app.demo_uuid('institution:university'), 'registrar_admin', 'active'),
  (app.demo_uuid('role:superadmin'), app.demo_uuid('staff:demo:superadmin'), null, 'super_administrator', 'active');

insert into public.teacher_assignments (
  id, institution_id, campus_id, staff_profile_id, offering_id,
  section_id, role_label, status
)
values
  (app.demo_uuid('ta:dmu:ba101:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('staff:dmu:teacher1'), app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('section:dmu:ba101:a'), 'teacher', 'active'),
  (app.demo_uuid('ta:dmu:ba101:b'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('staff:dmu:teacher1'), app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('section:dmu:ba101:b'), 'teacher', 'active'),
  (app.demo_uuid('ta:dmu:stat101:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('staff:dmu:teacher2'), app.demo_uuid('offering:dmu:islamabad:stat101'), app.demo_uuid('section:dmu:stat101:a'), 'teacher', 'active'),
  (app.demo_uuid('ta:dmu:sql201:a'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('staff:dmu:teacher2'), app.demo_uuid('offering:dmu:islamabad:sql201'), app.demo_uuid('section:dmu:sql201:a'), 'teacher', 'active'),
  (app.demo_uuid('ta:dcs:math:a'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('staff:dcs:teacher1'), app.demo_uuid('offering:dcs:north:math'), app.demo_uuid('section:dcs:north:math:a'), 'teacher', 'active'),
  (app.demo_uuid('ta:dcs:physics:a'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('staff:dcs:teacher2'), app.demo_uuid('offering:dcs:north:physics'), app.demo_uuid('section:dcs:north:physics:a'), 'teacher', 'active');

insert into public.assessment_components (
  id, institution_id, grading_policy_id, code, name,
  weight_percent, sequence_number, required, status
)
values
  (app.demo_uuid('component:dmu:assignment'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 'ASSIGNMENT', 'Assignments', 20, 1, true, 'active'),
  (app.demo_uuid('component:dmu:midterm'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 'MIDTERM', 'Midterm Examination', 30, 2, true, 'active'),
  (app.demo_uuid('component:dmu:final'), app.demo_uuid('institution:university'), app.demo_uuid('grading:dmu:1'), 'FINAL', 'Final Examination', 50, 3, true, 'active'),
  (app.demo_uuid('component:dcs:coursework'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 'COURSEWORK', 'Coursework', 40, 1, true, 'active'),
  (app.demo_uuid('component:dcs:exam'), app.demo_uuid('institution:school'), app.demo_uuid('grading:dcs:1'), 'EXAM', 'Term Examination', 60, 2, true, 'active');

insert into public.assessments (
  id, institution_id, campus_id, offering_id, section_id,
  component_id, code, title, maximum_marks, sequence_number, status
)
values
  (app.demo_uuid('assessment:dmu:ba101:a:assignment'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('section:dmu:ba101:a'), app.demo_uuid('component:dmu:assignment'), 'A1', 'Analytics Assignment', 20, 1, 'active'),
  (app.demo_uuid('assessment:dmu:ba101:a:midterm'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('section:dmu:ba101:a'), app.demo_uuid('component:dmu:midterm'), 'MID', 'Midterm', 30, 2, 'active'),
  (app.demo_uuid('assessment:dmu:ba101:a:final'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('section:dmu:ba101:a'), app.demo_uuid('component:dmu:final'), 'FIN', 'Final Examination', 50, 3, 'active'),
  (app.demo_uuid('assessment:dmu:ba101:b:assignment'), app.demo_uuid('institution:university'), app.demo_uuid('campus:dmu:islamabad'), app.demo_uuid('offering:dmu:islamabad:ba101'), app.demo_uuid('section:dmu:ba101:b'), app.demo_uuid('component:dmu:assignment'), 'A1', 'Analytics Assignment', 20, 1, 'active'),
  (app.demo_uuid('assessment:dcs:math:coursework'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('offering:dcs:north:math'), app.demo_uuid('section:dcs:north:math:a'), app.demo_uuid('component:dcs:coursework'), 'CW', 'Mathematics Coursework', 40, 1, 'active'),
  (app.demo_uuid('assessment:dcs:math:exam'), app.demo_uuid('institution:school'), app.demo_uuid('campus:dcs:north'), app.demo_uuid('offering:dcs:north:math'), app.demo_uuid('section:dcs:north:math:a'), app.demo_uuid('component:dcs:exam'), 'EXAM', 'Mathematics Term Exam', 60, 2, 'active');

insert into public.document_requirements (
  id, institution_id, program_id, document_code, document_name,
  required_for_enrollment, status
)
values
  (app.demo_uuid('document:dmu:identity'), app.demo_uuid('institution:university'), null, 'IDENTITY', 'Identity Document', true, 'active'),
  (app.demo_uuid('document:dmu:prior-result'), app.demo_uuid('institution:university'), app.demo_uuid('program:dmu:bsba'), 'PRIOR_RESULT', 'Prior Academic Result', true, 'active'),
  (app.demo_uuid('document:dcs:guardian'), app.demo_uuid('institution:school'), null, 'GUARDIAN_ID', 'Guardian Identity Document', true, 'active'),
  (app.demo_uuid('document:dcs:prior-result'), app.demo_uuid('institution:school'), app.demo_uuid('program:dcs:olevel'), 'PRIOR_RESULT', 'Prior School Result', true, 'active');

-- 50 fictional students: 25 university and 25 school.
insert into public.students (
  id, institution_id, campus_id, student_number, full_name,
  date_of_birth, primary_email, status, admitted_on, metadata
)
select
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('institution:university'),
  case when gs <= 18 then app.demo_uuid('campus:dmu:islamabad')
       else app.demo_uuid('campus:dmu:faisalabad') end,
  'DMU-' || lpad(gs::text, 4, '0'),
  'Demo University Student ' || lpad(gs::text, 2, '0'),
  date '2004-01-01' + (gs * interval '15 days'),
  'dmu.student' || lpad(gs::text, 2, '0') || '@example.test',
  'active',
  current_date - 90,
  jsonb_build_object('synthetic', true, 'edge_case',
    case
      when gs = 23 then 'missing_prerequisite'
      when gs = 24 then 'missing_document'
      when gs = 25 then 'waitlist_candidate'
      else null
    end
  )
from generate_series(1,25) gs;

insert into public.students (
  id, institution_id, campus_id, student_number, full_name,
  date_of_birth, primary_email, status, admitted_on, metadata
)
select
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('institution:school'),
  case when gs <= 18 then app.demo_uuid('campus:dcs:north')
       else app.demo_uuid('campus:dcs:south') end,
  'DCS-' || lpad(gs::text, 4, '0'),
  'Demo School Student ' || lpad(gs::text, 2, '0'),
  date '2010-01-01' + (gs * interval '20 days'),
  'dcs.student' || lpad(gs::text, 2, '0') || '@example.test',
  'active',
  current_date - 90,
  jsonb_build_object('synthetic', true)
from generate_series(1,25) gs;

insert into public.student_contacts (
  id, institution_id, student_id, contact_type, email, is_primary, status
)
select
  app.demo_uuid('contact:dmu:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('student:dmu:' || gs::text),
  'student_email',
  'dmu.student' || lpad(gs::text, 2, '0') || '@example.test',
  true, 'active'::public.record_status
from generate_series(1,25) gs
union all
select
  app.demo_uuid('contact:dcs:' || gs::text),
  app.demo_uuid('institution:school'),
  app.demo_uuid('student:dcs:' || gs::text),
  'student_email',
  'dcs.student' || lpad(gs::text, 2, '0') || '@example.test',
  true, 'active'::public.record_status
from generate_series(1,25) gs;

insert into public.student_program_registrations (
  id, institution_id, campus_id, student_id, program_id,
  academic_year_id, start_term_id, cohort_code,
  registration_status, current_term_sequence
)
select
  app.demo_uuid('registration:dmu:' || gs::text),
  app.demo_uuid('institution:university'),
  case when gs <= 18 then app.demo_uuid('campus:dmu:islamabad')
       else app.demo_uuid('campus:dmu:faisalabad') end,
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('program:dmu:bsba'),
  app.demo_uuid('academic-year:dmu:current'),
  app.demo_uuid('term:dmu:fall'),
  'DMU-DEMO-' || to_char(current_date,'YYYY'),
  'active'::public.program_registration_status, 1
from generate_series(1,25) gs
union all
select
  app.demo_uuid('registration:dcs:' || gs::text),
  app.demo_uuid('institution:school'),
  case when gs <= 18 then app.demo_uuid('campus:dcs:north')
       else app.demo_uuid('campus:dcs:south') end,
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('program:dcs:olevel'),
  app.demo_uuid('academic-year:dcs:current'),
  app.demo_uuid('term:dcs:term1'),
  'DCS-DEMO-' || to_char(current_date,'YYYY'),
  'active'::public.program_registration_status, 1
from generate_series(1,25) gs;

-- Verified documents for all except the intentional missing-document edge case.
insert into public.student_documents (
  id, institution_id, student_id, requirement_id, file_name,
  storage_provider, storage_object_id, checksum_sha256,
  document_status, verified_at
)
select
  app.demo_uuid('student-document:dmu:identity:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('document:dmu:identity'),
  'synthetic-identity-' || gs::text || '.pdf',
  'demo',
  'synthetic/dmu/' || gs::text || '/identity',
  encode(extensions.digest(convert_to('synthetic-dmu-identity-' || gs::text, 'utf8'),'sha256'),'hex'),
  'verified',
  timezone('utc', now())
from generate_series(1,25) gs
where gs <> 24;

insert into public.student_documents (
  id, institution_id, student_id, requirement_id, file_name,
  storage_provider, storage_object_id, checksum_sha256,
  document_status, verified_at
)
select
  app.demo_uuid('student-document:dmu:prior:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('document:dmu:prior-result'),
  'synthetic-prior-result-' || gs::text || '.pdf',
  'demo',
  'synthetic/dmu/' || gs::text || '/prior-result',
  encode(extensions.digest(convert_to('synthetic-dmu-prior-' || gs::text, 'utf8'),'sha256'),'hex'),
  'verified',
  timezone('utc', now())
from generate_series(1,25) gs
where gs <> 24;

insert into public.student_documents (
  id, institution_id, student_id, requirement_id, file_name,
  storage_provider, storage_object_id, checksum_sha256,
  document_status, verified_at
)
select
  app.demo_uuid('student-document:dcs:guardian:' || gs::text),
  app.demo_uuid('institution:school'),
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('document:dcs:guardian'),
  'synthetic-guardian-' || gs::text || '.pdf',
  'demo',
  'synthetic/dcs/' || gs::text || '/guardian',
  encode(extensions.digest(convert_to('synthetic-dcs-guardian-' || gs::text, 'utf8'),'sha256'),'hex'),
  'verified',
  timezone('utc', now())
from generate_series(1,25) gs;

insert into public.student_documents (
  id, institution_id, student_id, requirement_id, file_name,
  storage_provider, storage_object_id, checksum_sha256,
  document_status, verified_at
)
select
  app.demo_uuid('student-document:dcs:prior:' || gs::text),
  app.demo_uuid('institution:school'),
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('document:dcs:prior-result'),
  'synthetic-prior-result-' || gs::text || '.pdf',
  'demo',
  'synthetic/dcs/' || gs::text || '/prior-result',
  encode(extensions.digest(convert_to('synthetic-dcs-prior-' || gs::text, 'utf8'),'sha256'),'hex'),
  'verified',
  timezone('utc', now())
from generate_series(1,25) gs;

-- Initial university enrollments, including a deliberately full two-seat section.
insert into public.enrollments (
  id, institution_id, campus_id, student_id, program_registration_id,
  term_id, course_offering_id, section_id, enrollment_status
)
select
  app.demo_uuid('enrollment:dmu:ba101:a:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('campus:dmu:islamabad'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('registration:dmu:' || gs::text),
  app.demo_uuid('term:dmu:fall'),
  app.demo_uuid('offering:dmu:islamabad:ba101'),
  app.demo_uuid('section:dmu:ba101:a'),
  'active'
from generate_series(1,8) gs;

insert into public.enrollments (
  id, institution_id, campus_id, student_id, program_registration_id,
  term_id, course_offering_id, section_id, enrollment_status
)
select
  app.demo_uuid('enrollment:dmu:ba101:b:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('campus:dmu:islamabad'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('registration:dmu:' || gs::text),
  app.demo_uuid('term:dmu:fall'),
  app.demo_uuid('offering:dmu:islamabad:ba101'),
  app.demo_uuid('section:dmu:ba101:b'),
  'active'
from generate_series(9,10) gs;

insert into public.enrollments (
  id, institution_id, campus_id, student_id, program_registration_id,
  term_id, course_offering_id, section_id, enrollment_status
)
select
  app.demo_uuid('enrollment:dcs:math:' || gs::text),
  app.demo_uuid('institution:school'),
  app.demo_uuid('campus:dcs:north'),
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('registration:dcs:' || gs::text),
  app.demo_uuid('term:dcs:term1'),
  app.demo_uuid('offering:dcs:north:math'),
  app.demo_uuid('section:dcs:north:math:a'),
  'active'
from generate_series(1,8) gs;

-- Edge-case request and waitlist entry for the full university section.
insert into public.enrollment_requests (
  id, institution_id, campus_id, student_id, enrollment_period_id,
  term_id, program_registration_id, correlation_id, idempotency_key,
  request_payload, request_hash, request_status, final_outcome
)
values (
  app.demo_uuid('enrollment-request:dmu:waitlist-edge'),
  app.demo_uuid('institution:university'),
  app.demo_uuid('campus:dmu:islamabad'),
  app.demo_uuid('student:dmu:25'),
  app.demo_uuid('enrollment-period:dmu:islamabad'),
  app.demo_uuid('term:dmu:fall'),
  app.demo_uuid('registration:dmu:25'),
  app.demo_uuid('correlation:waitlist-edge'),
  'seed-waitlist-edge',
  '{"synthetic":true,"case":"full_section_waitlist"}'::jsonb,
  encode(extensions.digest(convert_to('seed-waitlist-edge','utf8'),'sha256'),'hex'),
  'completed',
  'waitlisted'
);

insert into public.enrollment_request_items (
  id, institution_id, enrollment_request_id, course_offering_id,
  preferred_section_id, preference_order, requested_load,
  item_outcome, decision_code
)
values (
  app.demo_uuid('enrollment-item:dmu:waitlist-edge'),
  app.demo_uuid('institution:university'),
  app.demo_uuid('enrollment-request:dmu:waitlist-edge'),
  app.demo_uuid('offering:dmu:islamabad:ba101'),
  app.demo_uuid('section:dmu:ba101:b'),
  1, 3, 'waitlisted', 'ENROLLMENT_WAITLISTED'
);

insert into public.waitlist_entries (
  id, institution_id, campus_id, student_id, enrollment_request_item_id,
  course_offering_id, preferred_section_id, position_number, waitlist_status
)
values (
  app.demo_uuid('waitlist:dmu:waitlist-edge'),
  app.demo_uuid('institution:university'),
  app.demo_uuid('campus:dmu:islamabad'),
  app.demo_uuid('student:dmu:25'),
  app.demo_uuid('enrollment-item:dmu:waitlist-edge'),
  app.demo_uuid('offering:dmu:islamabad:ba101'),
  app.demo_uuid('section:dmu:ba101:b'),
  1, 'waiting'
);

insert into public.enrollment_decisions (
  id, institution_id, enrollment_request_id, enrollment_request_item_id,
  decision, decision_code, evidence, correlation_id
)
values (
  app.demo_uuid('enrollment-decision:dmu:waitlist-edge'),
  app.demo_uuid('institution:university'),
  app.demo_uuid('enrollment-request:dmu:waitlist-edge'),
  app.demo_uuid('enrollment-item:dmu:waitlist-edge'),
  'waitlisted', 'ENROLLMENT_WAITLISTED',
  '{"synthetic":true,"section_full":true}'::jsonb,
  app.demo_uuid('correlation:waitlist-edge')
);

-- Approved marks for ten university and eight school students.
insert into public.marks_batches (
  id, institution_id, campus_id, offering_id, section_id,
  submitted_by_staff_profile_id, version_number, source_submission_id,
  correlation_id, idempotency_key, request_hash, batch_status,
  validation_summary, finalized_at, approved_at
)
values
  (
    app.demo_uuid('marks-batch:dmu:ba101:a:1'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('campus:dmu:islamabad'),
    app.demo_uuid('offering:dmu:islamabad:ba101'),
    app.demo_uuid('section:dmu:ba101:a'),
    app.demo_uuid('staff:dmu:teacher1'),
    1, 'seed-dmu-ba101-a',
    app.demo_uuid('correlation:marks:dmu'),
    'seed-marks-dmu-ba101-a',
    encode(extensions.digest(convert_to('seed-marks-dmu-ba101-a','utf8'),'sha256'),'hex'),
    'approved',
    '{"valid_rows":24,"error_count":0,"warning_count":0,"total_rows":24}'::jsonb,
    timezone('utc', now()), timezone('utc', now())
  ),
  (
    app.demo_uuid('marks-batch:dcs:math:a:1'),
    app.demo_uuid('institution:school'),
    app.demo_uuid('campus:dcs:north'),
    app.demo_uuid('offering:dcs:north:math'),
    app.demo_uuid('section:dcs:north:math:a'),
    app.demo_uuid('staff:dcs:teacher1'),
    1, 'seed-dcs-math-a',
    app.demo_uuid('correlation:marks:dcs'),
    'seed-marks-dcs-math-a',
    encode(extensions.digest(convert_to('seed-marks-dcs-math-a','utf8'),'sha256'),'hex'),
    'approved',
    '{"valid_rows":16,"error_count":0,"warning_count":0,"total_rows":16}'::jsonb,
    timezone('utc', now()), timezone('utc', now())
  );

insert into public.student_marks (
  id, institution_id, marks_batch_id, assessment_id, student_id,
  enrollment_id, marks_obtained, is_absent, is_missing
)
select
  app.demo_uuid('mark:dmu:assignment:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('marks-batch:dmu:ba101:a:1'),
  app.demo_uuid('assessment:dmu:ba101:a:assignment'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('enrollment:dmu:ba101:a:' || gs::text),
  12 + (gs % 8), false, false
from generate_series(1,8) gs
union all
select
  app.demo_uuid('mark:dmu:midterm:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('marks-batch:dmu:ba101:a:1'),
  app.demo_uuid('assessment:dmu:ba101:a:midterm'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('enrollment:dmu:ba101:a:' || gs::text),
  16 + (gs % 12), false, false
from generate_series(1,8) gs
union all
select
  app.demo_uuid('mark:dmu:final:' || gs::text),
  app.demo_uuid('institution:university'),
  app.demo_uuid('marks-batch:dmu:ba101:a:1'),
  app.demo_uuid('assessment:dmu:ba101:a:final'),
  app.demo_uuid('student:dmu:' || gs::text),
  app.demo_uuid('enrollment:dmu:ba101:a:' || gs::text),
  24 + (gs % 24), false, false
from generate_series(1,8) gs;

insert into public.student_marks (
  id, institution_id, marks_batch_id, assessment_id, student_id,
  enrollment_id, marks_obtained, is_absent, is_missing
)
select
  app.demo_uuid('mark:dcs:coursework:' || gs::text),
  app.demo_uuid('institution:school'),
  app.demo_uuid('marks-batch:dcs:math:a:1'),
  app.demo_uuid('assessment:dcs:math:coursework'),
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('enrollment:dcs:math:' || gs::text),
  22 + (gs % 17), false, false
from generate_series(1,8) gs
union all
select
  app.demo_uuid('mark:dcs:exam:' || gs::text),
  app.demo_uuid('institution:school'),
  app.demo_uuid('marks-batch:dcs:math:a:1'),
  app.demo_uuid('assessment:dcs:math:exam'),
  app.demo_uuid('student:dcs:' || gs::text),
  app.demo_uuid('enrollment:dcs:math:' || gs::text),
  32 + (gs % 25), false, false
from generate_series(1,8) gs;

do $do$
declare
  v_student_id uuid;
begin
  for v_student_id in
    select app.demo_uuid('student:dmu:' || gs::text) from generate_series(1,8) gs
  loop
    perform app.calculate_course_result(
      v_student_id,
      app.demo_uuid('offering:dmu:islamabad:ba101'),
      app.demo_uuid('correlation:seed-result:dmu')
    );
    update public.course_results
    set result_status = 'published',
        approved_at = timezone('utc', now()),
        published_at = timezone('utc', now())
    where student_id = v_student_id
      and course_offering_id = app.demo_uuid('offering:dmu:islamabad:ba101');
    perform app.recalculate_academic_record(
      v_student_id,
      app.demo_uuid('term:dmu:fall'),
      app.demo_uuid('correlation:seed-result:dmu')
    );
    update public.semester_results
    set result_status = 'published', published_at = timezone('utc', now())
    where student_id = v_student_id and term_id = app.demo_uuid('term:dmu:fall');
  end loop;

  for v_student_id in
    select app.demo_uuid('student:dcs:' || gs::text) from generate_series(1,8) gs
  loop
    perform app.calculate_course_result(
      v_student_id,
      app.demo_uuid('offering:dcs:north:math'),
      app.demo_uuid('correlation:seed-result:dcs')
    );
    update public.course_results
    set result_status = 'published',
        approved_at = timezone('utc', now()),
        published_at = timezone('utc', now())
    where student_id = v_student_id
      and course_offering_id = app.demo_uuid('offering:dcs:north:math');
    perform app.recalculate_academic_record(
      v_student_id,
      app.demo_uuid('term:dcs:term1'),
      app.demo_uuid('correlation:seed-result:dcs')
    );
    update public.semester_results
    set result_status = 'published', published_at = timezone('utc', now())
    where student_id = v_student_id and term_id = app.demo_uuid('term:dcs:term1');
  end loop;
end
$do$;

insert into ops.notification_outbox (
  id, institution_id, campus_id, channel, notification_type,
  recipient_address, recipient_name, subject, template_code,
  payload, correlation_id, idempotency_key, job_status
)
values
  (
    app.demo_uuid('notification:seed:welcome'),
    app.demo_uuid('institution:university'),
    app.demo_uuid('campus:dmu:islamabad'),
    'email', 'student.profile.acknowledged',
    'dmu.student01@example.test', 'Demo University Student 01',
    'Student profile received', 'student-profile-ack',
    '{"synthetic":true}'::jsonb,
    app.demo_uuid('correlation:notification:seed'),
    'seed-notification-welcome',
    'pending'
  );

insert into audit.audit_logs (
  id, institution_id, campus_id, operation, entity_type,
  correlation_id, outcome, details
)
values (
  app.demo_uuid('audit:seed:complete'),
  app.demo_uuid('institution:university'),
  app.demo_uuid('campus:dmu:islamabad'),
  'seed.demo.loaded', 'database',
  app.demo_uuid('correlation:seed'),
  'success',
  jsonb_build_object(
    'institutions', 2,
    'students', 50,
    'courses_or_subjects', 10,
    'synthetic_only', true
  )
);

commit;
