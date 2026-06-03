-- Digiteekaart.ee / 02Signal business registry foundation
-- PostgreSQL / Supabase compatible schema.
-- Purpose: normalized operating memory for owner-facing funding pre-assessments.

create schema if not exists public_registry;
create schema if not exists support_assessment;
create schema if not exists source_archive;

create table if not exists source_archive.public_source_records (
  id uuid primary key default gen_random_uuid(),
  source_system text not null check (source_system in ('rik', 'rar', 'mta', 'eis', 'manual')),
  source_kind text not null,
  record_key text not null,
  registry_code text check (registry_code is null or registry_code ~ '^[0-9]{8}$'),
  source_date date,
  observed_at timestamptz not null default now(),
  checksum_sha256 text,
  payload_classification text not null default 'public_business_data'
    check (payload_classification in ('public_business_data', 'public_person_data', 'restricted', 'unknown')),
  retention_policy text not null default 'business_analysis',
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create unique index if not exists public_source_records_source_record_idx
  on source_archive.public_source_records (source_system, source_kind, record_key, observed_at);

create index if not exists public_source_records_registry_idx
  on source_archive.public_source_records (registry_code, observed_at desc);

create table if not exists public_registry.rik_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_name text not null,
  source_kind text not null check (source_kind in ('bulk_file', 'api_refresh', 'manual_fixture')),
  source_url text,
  source_date date,
  checksum_sha256 text,
  record_count integer not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'started' check (status in ('started', 'completed', 'failed')),
  error_summary text,
  created_at timestamptz not null default now()
);

create table if not exists public_registry.rik_companies (
  registry_code text primary key check (registry_code ~ '^[0-9]{8}$'),
  name text not null,
  legal_form text,
  status text,
  registered_at date,
  deleted_at date,
  primary_activity_code text,
  primary_activity_name text,
  address_summary text,
  board_member_count integer,
  oldest_board_member_age integer,
  has_mobile_phone boolean not null default false,
  source_updated_at timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_import_batch_id uuid references public_registry.rik_import_batches(id),
  raw_source_kind text not null default 'bounded_normalized'
);

alter table public_registry.rik_companies
  add column if not exists board_member_count integer,
  add column if not exists oldest_board_member_age integer,
  add column if not exists has_mobile_phone boolean not null default false;

create index if not exists rik_companies_name_idx
  on public_registry.rik_companies using gin (to_tsvector('simple', coalesce(name, '')));

create index if not exists rik_companies_activity_idx
  on public_registry.rik_companies (primary_activity_code);

create table if not exists public_registry.rik_annual_reports (
  registry_code text not null references public_registry.rik_companies(registry_code) on delete cascade,
  fiscal_year integer not null check (fiscal_year between 1995 and 2100),
  report_submitted_at date,
  revenue numeric(14, 2),
  employee_count integer,
  report_status text,
  source_updated_at timestamptz,
  last_import_batch_id uuid references public_registry.rik_import_batches(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (registry_code, fiscal_year)
);

create index if not exists rik_annual_reports_revenue_idx
  on public_registry.rik_annual_reports (fiscal_year, revenue);

create table if not exists support_assessment.support_program_rules (
  program_id text primary key,
  program_name text not null,
  short_name text not null,
  status text not null default 'active' check (status in ('active', 'paused', 'closed', 'unknown')),
  support_min numeric(14, 2),
  support_max numeric(14, 2),
  support_text text not null,
  own_contribution_text text not null,
  min_average_revenue numeric(14, 2) not null default 0,
  roadmap_required boolean not null default false,
  plain_use text not null,
  owner_answer text not null,
  source_url text not null,
  source_checked_at date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists support_assessment.rar_de_minimis_snapshots (
  id uuid primary key default gen_random_uuid(),
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  company_name text,
  de_minimis_used numeric(14, 2),
  de_minimis_limit numeric(14, 2) not null default 300000,
  de_minimis_left numeric(14, 2),
  check_status text not null default 'checked'
    check (check_status in ('checked', 'not_found', 'source_unavailable', 'manual_review')),
  checked_at timestamptz not null default now(),
  source_system text not null default 'RAR',
  source_record_id uuid references source_archive.public_source_records(id),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists rar_de_minimis_registry_idx
  on support_assessment.rar_de_minimis_snapshots (registry_code, checked_at desc);

create table if not exists support_assessment.mta_tax_debt_snapshots (
  id uuid primary key default gen_random_uuid(),
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  has_tax_debt boolean,
  tax_debt_amount numeric(14, 2),
  check_status text not null default 'checked'
    check (check_status in ('checked', 'not_found', 'source_unavailable', 'manual_review')),
  checked_at timestamptz not null default now(),
  source_system text not null default 'MTA',
  source_record_id uuid references source_archive.public_source_records(id),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists mta_tax_debt_registry_idx
  on support_assessment.mta_tax_debt_snapshots (registry_code, checked_at desc);

create table if not exists support_assessment.support_preassessment_events (
  id uuid primary key default gen_random_uuid(),
  lead_id text,
  registry_code text,
  company_name text,
  email_hash text,
  consent_contact boolean not null default false,
  consent_funding_updates boolean not null default false,
  requested_need text,
  has_roadmap text,
  revenue_year_1 numeric(14, 2),
  revenue_year_2 numeric(14, 2),
  average_revenue numeric(14, 2),
  de_minimis_used numeric(14, 2),
  recommended_program_id text references support_assessment.support_program_rules(program_id),
  result_status text,
  possible_support_text text,
  missing_checks text[],
  source_site text,
  source_path text,
  attribution jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists support_preassessment_registry_idx
  on support_assessment.support_preassessment_events (registry_code);

create index if not exists support_preassessment_created_idx
  on support_assessment.support_preassessment_events (created_at desc);

drop view if exists support_assessment.company_support_snapshots cascade;
drop view if exists support_assessment.company_revenue_summary cascade;

create or replace view support_assessment.company_revenue_summary as
with ranked_reports as (
  select
    registry_code,
    fiscal_year,
    revenue,
    employee_count,
    row_number() over (partition by registry_code order by fiscal_year desc) as report_rank
  from public_registry.rik_annual_reports
  where revenue is not null
),
latest_two as (
  select
    registry_code,
    avg(revenue) filter (where report_rank <= 2) as average_revenue_last_two,
    max(fiscal_year) as latest_fiscal_year,
    max(employee_count) filter (where report_rank = 1) as latest_employee_count,
    count(*) filter (where report_rank <= 2) as revenue_years_count
  from ranked_reports
  group by registry_code
)
select
  c.registry_code,
  c.name,
  c.legal_form,
  c.status,
  c.primary_activity_code,
  c.primary_activity_name,
  c.registered_at,
  c.board_member_count,
  c.oldest_board_member_age,
  c.has_mobile_phone,
  c.last_seen_at,
  l.latest_fiscal_year,
  l.average_revenue_last_two,
  l.latest_employee_count,
  l.revenue_years_count,
  case
    when c.status is null then 'status_unknown'
    when lower(c.status) in ('registrisse kantud', 'active', 'aktiivne') then 'active'
    else 'needs_review'
  end as company_status_flag
from public_registry.rik_companies c
left join latest_two l on l.registry_code = c.registry_code;

create or replace view support_assessment.company_support_snapshots as
select
  s.registry_code,
  s.name,
  s.status,
  s.company_status_flag,
  s.primary_activity_code,
  s.primary_activity_name,
  s.latest_fiscal_year,
  s.average_revenue_last_two,
  s.latest_employee_count,
  s.board_member_count,
  s.oldest_board_member_age,
  s.has_mobile_phone,
  v.de_minimis_used,
  v.de_minimis_limit,
  v.de_minimis_left,
  v.checked_at as de_minimis_checked_at,
  t.has_tax_debt,
  t.tax_debt_amount,
  t.checked_at as tax_debt_checked_at,
  r.program_id,
  r.short_name as recommended_program,
  r.support_text,
  r.own_contribution_text,
  r.min_average_revenue,
  case
    when s.company_status_flag <> 'active' then 'needs_review'
    when t.has_tax_debt is true then 'needs_review'
    when s.average_revenue_last_two is null then 'missing_revenue'
    when s.average_revenue_last_two >= r.min_average_revenue then 'can_check_further'
    else 'revenue_below_threshold'
  end as preliminary_status,
  array_remove(array[
    case when s.company_status_flag <> 'active' then 'ettevõtte staatus' end,
    case when s.average_revenue_last_two is null then 'kahe viimase aasta müügitulu' end,
    case when v.checked_at is null then 'VTA jääk' end,
    case when t.checked_at is null then 'maksuvõla kontroll' end,
    case when t.has_tax_debt is true then 'maksuvõla lahendamine' end,
    'varasemad sama sisuga toetused'
  ], null) as missing_checks,
  r.source_url,
  r.source_checked_at
from support_assessment.company_revenue_summary s
left join lateral (
  select
    de_minimis_used,
    de_minimis_limit,
    de_minimis_left,
    checked_at
  from support_assessment.rar_de_minimis_snapshots v
  where v.registry_code = s.registry_code
  order by checked_at desc
  limit 1
) v on true
left join lateral (
  select
    has_tax_debt,
    tax_debt_amount,
    checked_at
  from support_assessment.mta_tax_debt_snapshots t
  where t.registry_code = s.registry_code
  order by checked_at desc
  limit 1
) t on true
cross join support_assessment.support_program_rules r
where r.status = 'active';
