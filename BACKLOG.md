# Sales-Site Backlog

## Current Priority

- Keep all public wording simple enough for a 65+ pragmatic owner.
- Show money, time saved, and payback wherever it helps the decision.
- Route funding and support questions to `digiteekaart.ee`.
- Keep every conversion path measurable in GA4.

## Automatiseerimine.ee

- Improve the repeated-work calculator with clearer examples by business type.
- Add one small case example: "Excelist teavituseni" with rough before/after numbers.
- Add a local lead form later if the current 02Signal quick-check route loses intent.

## Digitaliseerimine.ee

- Add more examples where old software does not need to be replaced immediately.
- Expand the manual-work cost calculator with an optional "errors per month" field.
- Add a short "tasuvuse näide" section near pricing.

## Digiteekaart.ee

- Done: first on-page funding filter shows likely route, possible support, own contribution logic and missing checks before consultant contact.
- Done: `funding-programs.json` exposes the bounded support-rule register for agents and future integrations.
- Done: RIK warehouse foundation added under `infra/rik-warehouse/` with PostgreSQL schema, fixture and smoke test.
- Done: privacy wording now covers public registry/RAR/MTA data use for support pre-assessment.
- Done: warehouse foundation now separates raw public source archive from owner-facing product views and stores dated VTA/tax-debt snapshots.
- Done: Supabase Edge Function `rik-company-lookup` deployed and smoke-tested against RIK simple data API for Ettevõtluskeskus OÜ.
- Done: homepage registry-code field now runs live RIK lookup, shows company status on-page and sends bounded RIK facts with the lead.
- Done: homepage company-name autocomplete lets owners start by typing the company name, select the right company and auto-fill the registry code before the RIK check.
- Done: sample digitalisation roadmap page added to show owners what a practical roadmap should contain and why it can be useful.
- Done: internal lead quality engine foundation added for Toomas: prospect scoring, public-safe priority board, VTA check queue and restricted contact layer.
- Done: first internal CRM page added for `crm.digiteekaart.ee` with Supabase magic-link login, public-safe priority board and status update actions.
- Next: add RAR/VTA lookup adapter and refresh VTA before showing a detailed paid recommendation.
- Next: after RIK contract is active, implement bulk importer from avaandmed files and API refresh for a single registry code.
- Next: run first bounded RIK company import and populate 50-100 sales prospects for Toomas without exposing restricted contacts publicly.
- Next: apply lead quality SQL in Supabase, add Toomas to `sales_crm.crm_users`, add `crm.digiteekaart.ee` in Vercel/Cloudflare and smoke-test magic link.
- Next: add email verification before showing a more detailed generated report.
- After Google Ads data arrives, refine the result/CTA section around phone calls and owner-level next steps.
- Keep official funding facts checked against official sources before publishing.

## Teekaart.ee

- Improve the route selector with a stronger final CTA per route.
- Add a one-page example of "omaniku teekaart" with practical next-step pricing.
- Cross-link route results to the right microsite with UTM parameters.
