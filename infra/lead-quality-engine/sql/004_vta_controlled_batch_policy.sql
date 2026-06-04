-- Digiteekaart.ee / controlled VTA batch policy
-- PostgreSQL / Supabase compatible, idempotent.
--
-- Purpose:
-- - let the CRM user push one company to the front of the VTA queue;
-- - let the CRM user prepare a small visible batch;
-- - let the AMOS n8n worker add the next strongest companies before each
--   controlled cycle, without browser auth and without mass querying.

create or replace function public.crm_queue_vta_check_now(p_registry_code text)
returns uuid
language plpgsql
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
declare
  v_registry_code text;
  v_company sales_crm.company_lead_universe%rowtype;
  v_queue_id uuid;
begin
  if not sales_crm.current_crm_user_allowed() then
    raise exception 'CRM access denied';
  end if;

  v_registry_code = regexp_replace(coalesce(p_registry_code, ''), '\D', '', 'g');

  if v_registry_code !~ '^[0-9]{8}$' then
    raise exception 'Invalid registry code';
  end if;

  select *
  into v_company
  from sales_crm.company_lead_universe
  where registry_code = v_registry_code
  limit 1;

  if not found then
    raise exception 'Company not found in warehouse';
  end if;

  insert into sales_crm.vta_check_queue (
    prospect_company_id,
    registry_code,
    company_name,
    priority_score,
    check_method,
    queue_status,
    scheduled_for
  ) values (
    v_company.prospect_id,
    v_company.registry_code,
    v_company.company_name,
    greatest(coalesce(v_company.priority_score, 0), 100),
    'xtee_rar_api',
    'queued',
    current_date
  )
  on conflict on constraint vta_check_queue_registry_code_scheduled_for_check_method_key do update
  set
    prospect_company_id = excluded.prospect_company_id,
    company_name = excluded.company_name,
    priority_score = greatest(excluded.priority_score, sales_crm.vta_check_queue.priority_score),
    queue_status = case
      when sales_crm.vta_check_queue.queue_status in ('checked', 'manual_review') then sales_crm.vta_check_queue.queue_status
      when sales_crm.vta_check_queue.queue_status = 'checking' then 'checking'
      else 'queued'
    end,
    error_summary = null,
    updated_at = now()
  returning id into v_queue_id;

  if v_company.prospect_id is not null then
    insert into sales_crm.prospect_activities (
      prospect_company_id,
      activity_type,
      activity_note,
      created_by
    ) values (
      v_company.prospect_id,
      'qualification',
      'Lisatud kiire VTA kontrolli järjekorda.',
      lower(coalesce(auth.jwt() ->> 'email', 'unknown'))
    );
  end if;

  return v_queue_id;
end;
$$;

create or replace function public.crm_queue_next_vta_checks_now(
  p_limit integer default 5,
  p_min_score integer default 75
)
returns table (
  queue_id uuid,
  registry_code text,
  company_name text,
  priority_score integer,
  company_age_years integer,
  latest_employee_count integer
)
language plpgsql
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
declare
  v_limit integer := greatest(1, least(10, coalesce(p_limit, 5)));
  v_min_score integer := greatest(0, least(100, coalesce(p_min_score, 75)));
begin
  if not sales_crm.current_crm_user_allowed() then
    raise exception 'CRM access denied';
  end if;

  return query
  with candidates as (
    select u.*
    from sales_crm.company_lead_universe u
    where u.vta_signal = 'not_checked'
      and u.priority_score >= v_min_score
      and coalesce(u.vta_queue_status, '') not in ('queued', 'checking', 'checked')
    order by
      u.priority_score desc,
      u.company_age_years desc nulls last,
      u.latest_employee_count desc nulls last,
      u.average_revenue_last_two desc nulls last,
      u.company_name asc
    limit v_limit
  ),
  inserted as (
    insert into sales_crm.vta_check_queue as q (
      prospect_company_id,
      registry_code,
      company_name,
      priority_score,
      check_method,
      queue_status,
      scheduled_for
    )
    select
      c.prospect_id,
      c.registry_code,
      c.company_name,
      c.priority_score,
      'xtee_rar_api',
      'queued',
      current_date
    from candidates c
    on conflict on constraint vta_check_queue_registry_code_scheduled_for_check_method_key do update
    set
      prospect_company_id = excluded.prospect_company_id,
      company_name = excluded.company_name,
      priority_score = greatest(excluded.priority_score, q.priority_score),
      queue_status = case
        when q.queue_status in ('checked', 'manual_review') then q.queue_status
        when q.queue_status = 'checking' then 'checking'
        else 'queued'
      end,
      error_summary = null,
      updated_at = now()
    returning
      q.id,
      q.registry_code,
      q.company_name,
      q.priority_score
  )
  select
    i.id,
    i.registry_code,
    i.company_name,
    i.priority_score,
    c.company_age_years,
    c.latest_employee_count
  from inserted i
  join candidates c on c.registry_code = i.registry_code
  order by
    i.priority_score desc,
    c.company_age_years desc nulls last,
    c.latest_employee_count desc nulls last;
end;
$$;

create or replace function public.crm_worker_queue_top_vta_checks(
  p_worker_id text default 'amos-n8n-vta',
  p_limit integer default 1,
  p_min_score integer default 75,
  p_min_company_age_years integer default 20,
  p_min_employees integer default 1
)
returns table (
  queue_id uuid,
  registry_code text,
  company_name text,
  priority_score integer,
  company_age_years integer,
  latest_employee_count integer
)
language plpgsql
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
declare
  v_worker_id text := coalesce(nullif(trim(p_worker_id), ''), 'amos-n8n-vta');
  v_limit integer := greatest(1, least(5, coalesce(p_limit, 1)));
  v_min_score integer := greatest(0, least(100, coalesce(p_min_score, 75)));
  v_min_age integer := greatest(0, least(100, coalesce(p_min_company_age_years, 20)));
  v_min_employees integer := greatest(0, least(10000, coalesce(p_min_employees, 1)));
begin
  return query
  with candidates as (
    select u.*
    from sales_crm.company_lead_universe u
    where u.vta_signal = 'not_checked'
      and u.priority_score >= v_min_score
      and coalesce(u.company_age_years, 0) >= v_min_age
      and coalesce(u.latest_employee_count, 0) >= v_min_employees
      and coalesce(u.vta_queue_status, '') not in ('queued', 'checking', 'checked')
      and coalesce(u.crm_status, 'new') not in ('do_not_contact', 'won', 'lost', 'not_relevant')
    order by
      u.priority_score desc,
      u.company_age_years desc nulls last,
      u.latest_employee_count desc nulls last,
      u.average_revenue_last_two desc nulls last,
      u.company_name asc
    limit v_limit
  ),
  inserted as (
    insert into sales_crm.vta_check_queue as q (
      prospect_company_id,
      registry_code,
      company_name,
      priority_score,
      check_method,
      queue_status,
      scheduled_for
    )
    select
      c.prospect_id,
      c.registry_code,
      c.company_name,
      c.priority_score,
      'xtee_rar_api',
      'queued',
      current_date
    from candidates c
    on conflict on constraint vta_check_queue_registry_code_scheduled_for_check_method_key do update
    set
      prospect_company_id = excluded.prospect_company_id,
      company_name = excluded.company_name,
      priority_score = greatest(excluded.priority_score, q.priority_score),
      queue_status = case
        when q.queue_status in ('checked', 'manual_review') then q.queue_status
        when q.queue_status = 'checking' then 'checking'
        else 'queued'
      end,
      error_summary = null,
      updated_at = now()
    returning
      q.id,
      q.registry_code,
      q.company_name,
      q.priority_score
  )
  select
    i.id,
    i.registry_code,
    i.company_name,
    i.priority_score,
    c.company_age_years,
    c.latest_employee_count
  from inserted i
  join candidates c on c.registry_code = i.registry_code
  order by
    i.priority_score desc,
    c.company_age_years desc nulls last,
    c.latest_employee_count desc nulls last;

end;
$$;

grant execute on function public.crm_queue_vta_check_now(text) to authenticated;
grant execute on function public.crm_queue_next_vta_checks_now(integer, integer) to authenticated;
grant execute on function public.crm_worker_queue_top_vta_checks(text, integer, integer, integer, integer) to service_role;
