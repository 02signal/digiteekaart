-- Digiteekaart.ee / 02Signal lead quality engine foundation
-- PostgreSQL / Supabase compatible schema.
-- Purpose: internal operating memory for Toomas' B2B sales prioritisation.
--
-- Privacy rule:
-- - company facts and scores may be used in owner/operator views;
-- - personal contact data is stored only in the restricted table;
-- - do not expose restricted contacts through public views or static pages.

create schema if not exists sales_crm;

create table if not exists sales_crm.prospect_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  source text not null default 'rik_warehouse'
    check (source in ('rik_warehouse', 'manual', 'campaign', 'partner', 'other')),
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists sales_crm.crm_users (
  email text primary key,
  role text not null default 'sales'
    check (role in ('sales', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table sales_crm.crm_users is
  'Allowed users for the internal CRM. Insert Toomas and admins here before exposing CRM data.';

create table if not exists sales_crm.prospect_companies (
  id uuid primary key default gen_random_uuid(),
  list_id uuid references sales_crm.prospect_lists(id) on delete set null,
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  company_name text not null,
  legal_form text,
  status text,
  registered_at date,
  company_age_years integer check (company_age_years is null or company_age_years >= 0),
  primary_activity_code text,
  primary_activity_name text,
  address_summary text,
  average_revenue_last_two numeric(14, 2),
  latest_employee_count integer,
  latest_fiscal_year integer,
  de_minimis_left numeric(14, 2),
  de_minimis_checked_at timestamptz,
  vta_signal text not null default 'not_checked'
    check (vta_signal in ('not_checked', 'high_left', 'some_left', 'low_left', 'used_up', 'manual_review', 'source_unavailable')),
  sales_signal text not null default 'needs_review'
    check (sales_signal in ('good_first_call', 'needs_review', 'weak_fit', 'do_not_contact')),
  priority_score integer not null default 0 check (priority_score between 0 and 100),
  score_reason text[] not null default array[]::text[],
  recommended_pitch text,
  next_action text,
  owner_name text not null default 'Toomas',
  crm_status text not null default 'new'
    check (crm_status in (
      'new',
      'to_review',
      'call_next',
      'called',
      'not_relevant',
      'meeting_booked',
      'proposal_sent',
      'won',
      'lost',
      'do_not_contact'
    )),
  last_contacted_at timestamptz,
  next_follow_up_at timestamptz,
  source_system text not null default 'rik_warehouse',
  source_observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (list_id, registry_code)
);

create index if not exists prospect_companies_registry_idx
  on sales_crm.prospect_companies (registry_code);

create index if not exists prospect_companies_status_score_idx
  on sales_crm.prospect_companies (crm_status, priority_score desc);

create index if not exists prospect_companies_name_idx
  on sales_crm.prospect_companies using gin (to_tsvector('simple', coalesce(company_name, '')));

create table if not exists sales_crm.prospect_contacts_restricted (
  id uuid primary key default gen_random_uuid(),
  prospect_company_id uuid references sales_crm.prospect_companies(id) on delete cascade,
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  person_name text,
  role text,
  email text,
  phone text,
  source_system text not null default 'rik_open_data',
  lawful_basis_note text not null default 'Legitimate interest for B2B contact about company support/digitalisation; review before outreach.',
  contact_allowed boolean not null default true,
  do_not_contact boolean not null default false,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table sales_crm.prospect_contacts_restricted is
  'Restricted personal-data layer. Do not expose in public views, static pages, llms files or client-side API responses.';

create index if not exists prospect_contacts_restricted_company_idx
  on sales_crm.prospect_contacts_restricted (registry_code, observed_at desc);

create table if not exists sales_crm.prospect_activities (
  id uuid primary key default gen_random_uuid(),
  prospect_company_id uuid not null references sales_crm.prospect_companies(id) on delete cascade,
  activity_type text not null
    check (activity_type in (
      'note',
      'call_attempt',
      'call_connected',
      'email_sent',
      'meeting_booked',
      'qualification',
      'do_not_contact'
    )),
  activity_note text,
  activity_at timestamptz not null default now(),
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists prospect_activities_company_idx
  on sales_crm.prospect_activities (prospect_company_id, activity_at desc);

create table if not exists sales_crm.vta_check_queue (
  id uuid primary key default gen_random_uuid(),
  prospect_company_id uuid references sales_crm.prospect_companies(id) on delete cascade,
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  company_name text not null,
  priority_score integer not null default 0 check (priority_score between 0 and 100),
  check_method text not null default 'rar_public_manual'
    check (check_method in ('rar_public_manual', 'xtee_rar_api', 'manual')),
  queue_status text not null default 'queued'
    check (queue_status in ('queued', 'checking', 'checked', 'manual_review', 'failed', 'skipped')),
  scheduled_for date not null default current_date,
  checked_at timestamptz,
  rar_snapshot_id uuid references support_assessment.rar_de_minimis_snapshots(id),
  error_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (registry_code, scheduled_for, check_method)
);

create index if not exists vta_check_queue_work_idx
  on sales_crm.vta_check_queue (queue_status, scheduled_for, priority_score desc);

create or replace view sales_crm.toomas_priority_board as
select
  p.id as prospect_id,
  p.registry_code,
  coalesce(s.name, p.company_name) as company_name,
  coalesce(s.status, p.status) as company_status,
  p.company_age_years,
  coalesce(s.primary_activity_code, p.primary_activity_code) as primary_activity_code,
  coalesce(s.primary_activity_name, p.primary_activity_name) as primary_activity_name,
  coalesce(s.latest_fiscal_year, p.latest_fiscal_year) as latest_fiscal_year,
  coalesce(s.average_revenue_last_two, p.average_revenue_last_two) as average_revenue_last_two,
  coalesce(s.latest_employee_count, p.latest_employee_count) as latest_employee_count,
  coalesce(s.de_minimis_left, p.de_minimis_left) as de_minimis_left,
  coalesce(s.de_minimis_checked_at, p.de_minimis_checked_at) as de_minimis_checked_at,
  case
    when coalesce(s.de_minimis_left, p.de_minimis_left) is null then p.vta_signal
    when coalesce(s.de_minimis_left, p.de_minimis_left) >= 50000 then 'high_left'
    when coalesce(s.de_minimis_left, p.de_minimis_left) >= 10000 then 'some_left'
    when coalesce(s.de_minimis_left, p.de_minimis_left) > 0 then 'low_left'
    else 'used_up'
  end as vta_signal,
  p.priority_score,
  p.sales_signal,
  p.score_reason,
  p.recommended_pitch,
  p.next_action,
  p.owner_name,
  p.crm_status,
  p.last_contacted_at,
  p.next_follow_up_at,
  q.queue_status as vta_queue_status,
  q.scheduled_for as vta_scheduled_for,
  array_remove(array[
    case when p.company_age_years >= 10 then 'vanem toimiv ettevõte' end,
    case when coalesce(s.average_revenue_last_two, p.average_revenue_last_two) >= 50000 then 'müügitulu paistab piisav' end,
    case when coalesce(s.de_minimis_left, p.de_minimis_left) >= 10000 then 'VTA jääk paistab kasutatav' end,
    case when coalesce(s.de_minimis_checked_at, p.de_minimis_checked_at) is null then 'VTA vajab kontrolli' end
  ], null) as why_now
from sales_crm.prospect_companies p
left join lateral (
  select
    name,
    status,
    primary_activity_code,
    primary_activity_name,
    latest_fiscal_year,
    average_revenue_last_two,
    latest_employee_count,
    de_minimis_left,
    de_minimis_checked_at
  from support_assessment.company_support_snapshots s
  where s.registry_code = p.registry_code
  order by
    case when s.preliminary_status = 'can_check_further' then 0 else 1 end,
    s.source_checked_at desc
  limit 1
) s on true
left join lateral (
  select
    queue_status,
    scheduled_for
  from sales_crm.vta_check_queue q
  where q.registry_code = p.registry_code
  order by scheduled_for desc, created_at desc
  limit 1
) q on true
where p.crm_status not in ('do_not_contact', 'won', 'lost');

comment on view sales_crm.toomas_priority_board is
  'Public-company-fact CRM board for Toomas. Excludes restricted personal contact fields.';

create or replace view sales_crm.toomas_call_sheet_export as
select
  prospect_id,
  registry_code,
  company_name,
  company_status,
  company_age_years,
  primary_activity_name,
  average_revenue_last_two,
  latest_employee_count,
  de_minimis_left,
  de_minimis_checked_at,
  vta_signal,
  priority_score,
  sales_signal,
  recommended_pitch,
  next_action,
  owner_name,
  crm_status,
  next_follow_up_at
from sales_crm.toomas_priority_board;

comment on view sales_crm.toomas_call_sheet_export is
  'CSV/export-safe call sheet. Contact people and personal e-mails must be joined only in an authenticated restricted tool.';

create or replace function sales_crm.current_crm_user_allowed()
returns boolean
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select exists (
    select 1
    from sales_crm.crm_users u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and u.active is true
  );
$$;

create or replace function public.crm_get_toomas_priority_board()
returns table (
  prospect_id uuid,
  registry_code text,
  company_name text,
  company_status text,
  company_age_years integer,
  primary_activity_code text,
  primary_activity_name text,
  latest_fiscal_year integer,
  average_revenue_last_two numeric,
  latest_employee_count integer,
  de_minimis_left numeric,
  de_minimis_checked_at timestamptz,
  vta_signal text,
  priority_score integer,
  sales_signal text,
  score_reason text[],
  recommended_pitch text,
  next_action text,
  owner_name text,
  crm_status text,
  last_contacted_at timestamptz,
  next_follow_up_at timestamptz,
  vta_queue_status text,
  vta_scheduled_for date,
  why_now text[]
)
language sql
stable
security definer
set search_path = sales_crm, support_assessment, public
as $$
  select
    b.prospect_id,
    b.registry_code,
    b.company_name,
    b.company_status,
    b.company_age_years,
    b.primary_activity_code,
    b.primary_activity_name,
    b.latest_fiscal_year,
    b.average_revenue_last_two,
    b.latest_employee_count,
    b.de_minimis_left,
    b.de_minimis_checked_at,
    b.vta_signal,
    b.priority_score,
    b.sales_signal,
    b.score_reason,
    b.recommended_pitch,
    b.next_action,
    b.owner_name,
    b.crm_status,
    b.last_contacted_at,
    b.next_follow_up_at,
    b.vta_queue_status,
    b.vta_scheduled_for,
    b.why_now
  from sales_crm.toomas_priority_board b
  where sales_crm.current_crm_user_allowed()
  order by
    case b.crm_status
      when 'call_next' then 0
      when 'new' then 1
      when 'to_review' then 2
      else 3
    end,
    b.priority_score desc,
    b.company_age_years desc nulls last,
    b.company_name asc;
$$;

create or replace function public.crm_update_prospect_status(
  p_prospect_id uuid,
  p_crm_status text,
  p_note text default null,
  p_next_follow_up_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = sales_crm, public
as $$
declare
  v_activity_type text;
begin
  if not sales_crm.current_crm_user_allowed() then
    raise exception 'CRM access denied';
  end if;

  if p_crm_status not in (
    'new',
    'to_review',
    'call_next',
    'called',
    'not_relevant',
    'meeting_booked',
    'proposal_sent',
    'won',
    'lost',
    'do_not_contact'
  ) then
    raise exception 'Invalid CRM status: %', p_crm_status;
  end if;

  update sales_crm.prospect_companies
  set
    crm_status = p_crm_status,
    next_follow_up_at = p_next_follow_up_at,
    last_contacted_at = case
      when p_crm_status in ('called', 'meeting_booked', 'proposal_sent', 'won', 'lost', 'do_not_contact') then now()
      else last_contacted_at
    end,
    updated_at = now()
  where id = p_prospect_id;

  if not found then
    raise exception 'Prospect not found';
  end if;

  v_activity_type = case
    when p_crm_status = 'called' then 'call_connected'
    when p_crm_status = 'meeting_booked' then 'meeting_booked'
    when p_crm_status = 'do_not_contact' then 'do_not_contact'
    else 'note'
  end;

  insert into sales_crm.prospect_activities (
    prospect_company_id,
    activity_type,
    activity_note,
    created_by
  ) values (
    p_prospect_id,
    v_activity_type,
    nullif(p_note, ''),
    lower(coalesce(auth.jwt() ->> 'email', 'unknown'))
  );

  return true;
end;
$$;

grant execute on function public.crm_get_toomas_priority_board() to authenticated;
grant execute on function public.crm_update_prospect_status(uuid, text, text, timestamptz) to authenticated;

alter table sales_crm.prospect_lists enable row level security;
alter table sales_crm.crm_users enable row level security;
alter table sales_crm.prospect_companies enable row level security;
alter table sales_crm.prospect_contacts_restricted enable row level security;
alter table sales_crm.prospect_activities enable row level security;
alter table sales_crm.vta_check_queue enable row level security;
