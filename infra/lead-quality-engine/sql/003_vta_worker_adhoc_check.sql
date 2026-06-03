-- Digiteekaart.ee / AMOS VTA ad hoc worker check
-- PostgreSQL / Supabase compatible, idempotent.
--
-- Purpose:
-- - let AMOS n8n-ops run one owner-requested VTA check by registry code;
-- - keep the same queue, snapshot and CRM update path as scheduled batches;
-- - avoid browser-session auth inside the worker path.

create or replace function public.crm_worker_claim_vta_check_for_registry(
  p_worker_id text default 'amos-n8n-vta',
  p_registry_code text default null,
  p_company_name text default null,
  p_priority_score integer default 50
)
returns table (
  queue_id uuid,
  registry_code text,
  company_name text,
  priority_score integer,
  check_method text,
  attempt_count integer,
  scheduled_for date
)
language plpgsql
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
declare
  v_worker_id text := coalesce(nullif(trim(p_worker_id), ''), 'amos-n8n-vta');
  v_registry_code text;
  v_prospect_id uuid;
  v_company_name text;
  v_priority_score integer := greatest(0, least(100, coalesce(p_priority_score, 50)));
begin
  v_registry_code = regexp_replace(coalesce(p_registry_code, ''), '\D', '', 'g');

  if v_registry_code !~ '^[0-9]{8}$' then
    raise exception 'Invalid registry code';
  end if;

  select
    u.prospect_id,
    u.company_name,
    u.priority_score
  into
    v_prospect_id,
    v_company_name,
    v_priority_score
  from sales_crm.company_lead_universe u
  where u.registry_code = v_registry_code
  limit 1;

  if v_company_name is null then
    select
      p.id,
      p.company_name,
      p.priority_score
    into
      v_prospect_id,
      v_company_name,
      v_priority_score
    from sales_crm.prospect_companies p
    where p.registry_code = v_registry_code
      and p.crm_status not in ('do_not_contact', 'won', 'lost')
    order by p.created_at desc
    limit 1;
  end if;

  v_company_name = coalesce(nullif(trim(v_company_name), ''), nullif(trim(p_company_name), ''), 'Ettevõte ' || v_registry_code);
  v_priority_score = greatest(0, least(100, coalesce(v_priority_score, p_priority_score, 50)));

  insert into sales_crm.vta_check_queue (
    prospect_company_id,
    registry_code,
    company_name,
    priority_score,
    check_method,
    queue_status,
    scheduled_for
  ) values (
    v_prospect_id,
    v_registry_code,
    v_company_name,
    v_priority_score,
    'xtee_rar_api',
    'queued',
    current_date
  )
  on conflict (registry_code, scheduled_for, check_method) do update
  set
    prospect_company_id = coalesce(excluded.prospect_company_id, sales_crm.vta_check_queue.prospect_company_id),
    company_name = excluded.company_name,
    priority_score = greatest(excluded.priority_score, sales_crm.vta_check_queue.priority_score),
    queue_status = case
      when sales_crm.vta_check_queue.queue_status = 'checking' then 'checking'
      else 'queued'
    end,
    error_summary = null,
    updated_at = now();

  return query
  with target as (
    select q.id
    from sales_crm.vta_check_queue q
    where q.registry_code = v_registry_code
      and q.check_method = 'xtee_rar_api'
      and q.scheduled_for = current_date
      and q.queue_status = 'queued'
    order by q.priority_score desc, q.created_at desc
    for update skip locked
    limit 1
  ),
  claimed as (
    update sales_crm.vta_check_queue q
    set
      queue_status = 'checking',
      claimed_at = now(),
      claimed_by = v_worker_id,
      attempt_count = q.attempt_count + 1,
      error_summary = null,
      updated_at = now()
    from target t
    where q.id = t.id
    returning
      q.id,
      q.registry_code,
      q.company_name,
      q.priority_score,
      q.check_method,
      q.attempt_count,
      q.scheduled_for
  )
  select
    c.id,
    c.registry_code,
    c.company_name,
    c.priority_score,
    c.check_method,
    c.attempt_count,
    c.scheduled_for
  from claimed c;

  if v_prospect_id is not null then
    insert into sales_crm.prospect_activities (
      prospect_company_id,
      activity_type,
      activity_note,
      created_by
    ) values (
      v_prospect_id,
      'qualification',
      'AMOS ad hoc VTA kontroll käivitatud.',
      v_worker_id
    );
  end if;
end;
$$;

grant execute on function public.crm_worker_claim_vta_check_for_registry(text, text, text, integer) to service_role;
