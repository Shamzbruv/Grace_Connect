-- Removes the audit rows left by verifying the Fygaro webhook end to end
-- against the deployed function. They carry a 'verify-' transaction id, were
-- never matched to a church, and changed no subscription -- but they are test
-- traffic sitting in a production billing table, so they go.
delete from public.church_billing_events
where provider = 'fygaro'
  and provider_event_id like 'verify-%'
  and church_id is null;
