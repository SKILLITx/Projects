-- Find the successfully created Workflow 01 student number for Workflow 02.
select
  s.student_number,
  s.full_name,
  s.primary_email,
  s.identity_reference,
  s.student_status
from public.students s
where lower(s.primary_email) = lower('zaidrizwan.278+finalservicerole@gmail.com')
   or s.identity_reference = 'FINAL-SERVICE-ROLE-001'
order by s.created_at desc
limit 5;
