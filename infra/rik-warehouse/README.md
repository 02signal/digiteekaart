# RIK Warehouse Foundation

This folder defines the first reusable data foundation for Digiteekaart.ee and future 02Signal sales tools.

## Goal

Build one shared operating memory for Estonian company pre-assessments:

1. load bounded RIK / e-Business Register source data into our own PostgreSQL database;
2. normalize company facts that are useful across projects;
3. combine them with support-program rules;
4. expose simple views for owner-facing tools;
5. avoid storing unnecessary raw personal data.

## Source Strategy

Use two RIK data paths for different jobs:

- **Bulk dataset path:** daily public/open data files are the right source for loading the whole company dataset into our database.
- **API path:** after the RIK contract is active, use API calls for exact company lookup, autocomplete, and refreshing a specific registry code before a lead result is shown.

Do not use the API as a full-dataset crawler. It is slower, harder to operate, and usually rate/contract constrained.

## Layers

| Layer | Purpose |
| --- | --- |
| `rik_import_batches` | What file/API batch was loaded, when, and with what checksum. |
| `rik_companies` | Current company profile: registry code, name, status, legal form, activity code. |
| `rik_annual_reports` | Revenue and reporting facts by year. |
| `support_program_rules` | Bounded funding rules used for pre-assessment. |
| `company_support_snapshots` | Queryable owner-facing pre-assessment view. |
| `support_preassessment_events` | Lead-time assessment events for funnel analysis and follow-up. |

## Privacy Rule

For the MVP we do **not** ingest board-member names, beneficial owners, personal codes, raw reports, raw API payloads, or signed/source URLs into product tables.

If later needed, personal data must go into a separate restricted schema with a written purpose, retention rule, and access control.

## MVP Flow

1. Import RIK companies and latest annual-report revenue facts.
2. Upsert support rules from `public/funding-programs.json`.
3. Refresh `company_support_snapshots`.
4. The web tool can query by registry code:
   - company found / not found;
   - active / risky status;
   - average revenue;
   - likely support programs;
   - missing checks.
5. User confirms e-mail and consent before detailed report is generated or saved as a lead.

## Next Implementation Steps

1. Add Supabase migration from `sql/001_business_registry_foundation.sql`.
2. Build a batch loader for the RIK bulk files once the exact contract/API format is confirmed.
3. Add a server endpoint:
   - input: registry code;
   - output: bounded company support snapshot;
   - no raw RIK payload.
4. Add e-mail verification before showing a detailed report.
5. Store confirmed leads and assessment results in `support_preassessment_events`.

## Smoke Test

Run:

```bash
node infra/rik-warehouse/scripts/score-fixture.mjs
```

Expected outcome: the fixture company is classified against the support-program rules and prints the most likely first route.
