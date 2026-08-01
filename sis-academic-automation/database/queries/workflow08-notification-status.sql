select
  no.id as outbox_id,
  no.created_at,
  no.notification_type,
  no.channel,
  no.recipient_address,
  no.subject,
  no.job_status,
  no.attempt_count,
  no.max_attempts,
  no.last_error_code,
  no.last_error_message,
  nd.attempt_number,
  nd.delivery_status,
  nd.provider,
  nd.provider_message_id,
  nd.finished_at
from ops.notification_outbox no
left join ops.notification_deliveries nd
  on nd.outbox_id = no.id
where lower(no.recipient_address) like 'zaidrizwan.278%'
order by no.created_at desc, nd.attempt_number desc
limit 25;
