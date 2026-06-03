-- Digiteekaart.ee / 02Signal VTA worker cycle
-- PostgreSQL / Supabase compatible, idempotent.
--
-- Purpose:
-- - let AMOS n8n-ops claim a small bounded batch from sales_crm.vta_check_queue;
-- - store a dated VTA/RAR snapshot after an approved lookup adapter has a result;
-- - update the CRM work-sheet with the latest VTA signal;
-- - avoid raw payloads, secrets, signed URLs, prompts, or personal data.

alter table sales_crm.vta_check_queue
  add column if not exists claimed_at timestamptz,
  add column if not exists claimed_by text,
  add column if not exists attempt_count integer not null default 0,
  add column if not exists result_summary jsonb not null default '{}'::jsonb;

create index if not exists vta_check_queue_claim_idx
  on sales_crm.vta_check_queue (queue_status, scheduled_for, priority_score desc, created_at asc);

create or replace function public.crm_worker_claim_vta_checks(
  p_worker_id text default 'amos-n8n-vta',
  p_limit integer default 5
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
  v_limit integer := greatest(1, least(25, coalesce(p_limit, 5)));
begin
  return query
  with next_items as (
    select q.id
    from sales_crm.vta_check_queue q
    where q.queue_status = 'queued'
      and q.scheduled_for <= current_date
    order by
      q.priority_score desc,
      q.created_at asc
    for update skip locked
    limit v_limit
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
    from next_items n
    where q.id = n.id
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
  from claimed c
  order by c.priority_score desc, c.company_name asc;
end;
$$;

create or replace function public.crm_worker_record_vta_result(
  p_queue_id uuid,
  p_registry_code text,
  p_company_name text default null,
  p_de_minimis_used numeric default null,
  p_de_minimis_limit numeric default 300000,
  p_de_minimis_left numeric default null,
  p_check_status text default 'checked',
  p_source_system text default 'RAR',
  p_note text default null
)
returns table (
  queue_id uuid,
  registry_code text,
  rar_snapshot_id uuid,
  queue_status text,
  vta_signal text,
  de_minimis_left numeric
)
language plpgsql
security definer
set search_path = sales_crm, public_registry, support_assessment, source_archive, public
as $$
declare
  v_queue sales_crm.vta_check_queue%rowtype;
  v_registry_code text;
  v_company_name text;
  v_limit numeric := coalesce(p_de_minimis_limit, 300000);
  v_left numeric;
  v_used numeric;
  v_check_status text := coalesce(p_check_status, 'checked');
  v_source_record_id uuid;
  v_snapshot_id uuid;
  v_queue_status text;
  v_vta_signal text;
  v_note text := nullif(left(coalesce(p_note, ''), 500), '');
begin
  v_registry_code = regexp_replace(coalesce(p_registry_code, ''), '\D', '', 'g');

  if v_registry_code !~ '^[0-9]{8}$' then
    raise exception 'Invalid registry code';
  end if;

  if v_check_status not in ('checked', 'not_found', 'source_unavailable', 'manual_review') then
    raise exception 'Invalid VTA check status: %', v_check_status;
  end if;

  select *
  into v_queue
  from sales_crm.vta_check_queue q
  where q.id = p_queue_id
    and q.registry_code = v_registry_code
  for update;

  if not found then
    raise exception 'VTA queue item not found';
  end if;

  v_company_name = coalesce(nullif(trim(p_company_name), ''), v_queue.company_name);
  v_left = case
    when p_de_minimis_left is not null then greatest(0, p_de_minimis_left)
    when p_de_minimis_used is not null then greatest(0, v_limit - p_de_minimis_used)
    else null
  end;
  v_used = case
    when p_de_minimis_used is not null then greatest(0, p_de_minimis_used)
    when v_left is not null then greatest(0, v_limit - v_left)
    else null
  end;

  insert into source_archive.public_source_records (
    source_system,
    source_kind,
    record_key,
    registry_code,
    source_date,
    payload_classification,
    retention_policy,
    payload
  ) values (
    'rar',
    'vta_de_minimis_summary',
    v_registry_code || ':' || to_char(now(), 'YYYYMMDDHH24MISS') || ':' || left(p_queue_id::text, 8),
    v_registry_code,
    current_date,
    'public_business_data',
    'business_analysis',
    jsonb_strip_nulls(jsonb_build_object(
      'registry_code', v_registry_code,
      'company_name', v_company_name,
      'de_minimis_used', v_used,
      'de_minimis_limit', v_limit,
      'de_minimis_left', v_left,
      'check_status', v_check_status,
      'source_system', left(coalesce(p_source_system, 'RAR'), 40),
      'note_present', v_note is not null,
      'observed_at', now()
    ))
  )
  returning id into v_source_record_id;

  insert into support_assessment.rar_de_minimis_snapshots (
    registry_code,
    company_name,
    de_minimis_used,
    de_minimis_limit,
    de_minimis_left,
    check_status,
    checked_at,
    source_system,
    source_record_id,
    note
  ) values (
    v_registry_code,
    v_company_name,
    v_used,
    v_limit,
    v_left,
    v_check_status,
    now(),
    left(coalesce(p_source_system, 'RAR'), 40),
    v_source_record_id,
    v_note
  )
  returning id into v_snapshot_id;

  v_queue_status = case
    when v_check_status = 'checked' then 'checked'
    when v_check_status = 'source_unavailable' then 'failed'
    else 'manual_review'
  end;

  v_vta_signal = case
    when v_check_status = 'source_unavailable' then 'source_unavailable'
    when v_check_status in ('not_found', 'manual_review') then 'manual_review'
    when v_left is null then 'manual_review'
    when v_left >= 50000 then 'high_left'
    when v_left >= 10000 then 'some_left'
    when v_left > 0 then 'low_left'
    else 'used_up'
  end;

  update sales_crm.vta_check_queue q
  set
    queue_status = v_queue_status,
    checked_at = now(),
    rar_snapshot_id = v_snapshot_id,
    error_summary = null,
    result_summary = jsonb_strip_nulls(jsonb_build_object(
      'check_status', v_check_status,
      'vta_signal', v_vta_signal,
      'de_minimis_left', v_left,
      'source_record_id', v_source_record_id,
      'rar_snapshot_id', v_snapshot_id
    )),
    updated_at = now()
  where q.id = p_queue_id;

  update sales_crm.prospect_companies p
  set
    de_minimis_left = v_left,
    de_minimis_checked_at = now(),
    vta_signal = v_vta_signal,
    next_action = case
      when v_vta_signal in ('high_left', 'some_left') then 'VTA jääk paistab kasutatav. Tee kõne ja paku praktilist esimest sammu.'
      when v_vta_signal = 'low_left' then 'VTA jääk on väike. Kontrolli enne toetusega pakkumist.'
      when v_vta_signal = 'used_up' then 'VTA paistab kasutatud. Ära alusta toetuse jutuga enne käsitsi kontrolli.'
      when v_vta_signal = 'source_unavailable' then 'VTA allikas ei andnud vastust. Proovi hiljem või kontrolli käsitsi.'
      else 'VTA vajab käsitsi ülevaatust enne pakkumist.'
    end,
    updated_at = now()
  where p.registry_code = v_registry_code
    and p.crm_status not in ('do_not_contact', 'won', 'lost');

  if v_queue.prospect_company_id is not null then
    insert into sales_crm.prospect_activities (
      prospect_company_id,
      activity_type,
      activity_note,
      created_by
    ) values (
      v_queue.prospect_company_id,
      'qualification',
      case
        when v_vta_signal in ('high_left', 'some_left') then 'VTA kontroll tehtud: jääk paistab kasutatav.'
        when v_vta_signal = 'used_up' then 'VTA kontroll tehtud: jääk paistab kasutatud.'
        when v_vta_signal = 'source_unavailable' then 'VTA kontroll ebaõnnestus: allikas ei olnud kättesaadav.'
        else 'VTA kontroll vajab käsitsi ülevaatust.'
      end,
      'amos-n8n-vta'
    );
  end if;

  return query
  select
    p_queue_id,
    v_registry_code,
    v_snapshot_id,
    v_queue_status,
    v_vta_signal,
    v_left;
end;
$$;

create or replace function public.crm_worker_mark_vta_failed(
  p_queue_id uuid,
  p_error_summary text,
  p_retry_after_minutes integer default 1440,
  p_manual_review boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = sales_crm, public
as $$
declare
  v_queue sales_crm.vta_check_queue%rowtype;
  v_error text := left(coalesce(nullif(trim(p_error_summary), ''), 'VTA lookup failed'), 500);
  v_retry_minutes integer := greatest(15, least(10080, coalesce(p_retry_after_minutes, 1440)));
  v_final boolean;
begin
  select *
  into v_queue
  from sales_crm.vta_check_queue q
  where q.id = p_queue_id
  for update;

  if not found then
    raise exception 'VTA queue item not found';
  end if;

  v_final = coalesce(p_manual_review, false) or v_queue.attempt_count >= 3;

  update sales_crm.vta_check_queue q
  set
    queue_status = case when v_final then 'manual_review' else 'queued' end,
    scheduled_for = case when v_final then q.scheduled_for else (now() + make_interval(mins => v_retry_minutes))::date end,
    checked_at = case when v_final then now() else null end,
    error_summary = v_error,
    result_summary = jsonb_build_object(
      'error_summary', v_error,
      'manual_review', v_final,
      'attempt_count', v_queue.attempt_count,
      'next_retry_after_minutes', case when v_final then null else v_retry_minutes end
    ),
    updated_at = now()
  where q.id = p_queue_id;

  if v_queue.prospect_company_id is not null and v_final then
    insert into sales_crm.prospect_activities (
      prospect_company_id,
      activity_type,
      activity_note,
      created_by
    ) values (
      v_queue.prospect_company_id,
      'qualification',
      'VTA kontroll jäi käsitsi ülevaatuseks: ' || v_error,
      'amos-n8n-vta'
    );
  end if;

  return true;
end;
$$;

create or replace function public.crm_worker_get_vta_queue_summary()
returns table (
  queue_status text,
  item_count bigint,
  top_priority_score integer,
  oldest_created_at timestamptz
)
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select
    q.queue_status,
    count(*) as item_count,
    max(q.priority_score) as top_priority_score,
    min(q.created_at) as oldest_created_at
  from sales_crm.vta_check_queue q
  where q.scheduled_for <= current_date
  group by q.queue_status
  order by
    case q.queue_status
      when 'checking' then 0
      when 'queued' then 1
      when 'failed' then 2
      when 'manual_review' then 3
      when 'checked' then 4
      else 5
    end;
$$;

grant execute on function public.crm_worker_claim_vta_checks(text, integer) to service_role;
grant execute on function public.crm_worker_record_vta_result(uuid, text, text, numeric, numeric, numeric, text, text, text) to service_role;
grant execute on function public.crm_worker_mark_vta_failed(uuid, text, integer, boolean) to service_role;
grant execute on function public.crm_worker_get_vta_queue_summary() to service_role;
