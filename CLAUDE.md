# 02Signal Sales Site Rules

This repository is part of the Ettevõtluskeskus OÜ / 02Signal sales-site group.

## Audience

Write for a pragmatic Estonian business owner, often 60-70+ years old, with little technical background.

Use plain Estonian. Prefer:
- "tüütu töö"
- "aeg"
- "raha"
- "kordub iga nädal"
- "inimene vaatab üle"
- "tasub ära"

Avoid jargon unless it is necessary. Avoid words such as "agentic", "flow", "pipeline", "autonomy", "canonical", "maturity" in public copy.

## Commercial Rule

Every main page should answer:
- what pain this solves;
- what the owner gets;
- what it may cost;
- when the first small project may pay back;
- what the next safe step is.

Money matters. Where possible, show time saved, monthly euro value, and payback logic.

## Site Roles

- `automatiseerimine.ee`: repeated manual work, reminders, copying, first small automation.
- `digitaliseerimine.ee`: paper, Excel, old software, information movement, small practical digitalisation.
- `digiteekaart.ee`: EIS digitalisation roadmap, RTE/software support and funding pre-assessment.
- `teekaart.ee`: route selector when the owner does not know which direction to choose.

Support and funding questions should route to `https://digiteekaart.ee/`.

## Tracking

Keep GA4 events stable:
- `tool_start`
- `tool_completed`
- `result_high_intent`
- `cta_click`
- `phone_click`
- `email_click`
- `partner_site_click`
- `lead_form_start`
- `lead_form_submit_attempt`
- `lead_form_submit`

When adding tools, include useful event parameters such as `tool_name`, `result_tier`, `monthly_cost`, `payback_months`, or `result_route`.

## Privacy

Do not expose raw personal data, secrets, tokens, signed URLs, or private payloads. Lead forms must explain what data is collected and why.

## Internal CRM Rules

- Do not expose restricted contacts (`sales_crm.prospect_contacts_restricted`) or any personal ID numbers (isikukood) in public views or Astro static pages.
- Lead scoring must run in SQL (e.g. `001_sales_quality_engine.sql`), outputting reasons via arrays (`score_reason`); Astro only displays the result.
- **Layout:** The default CRM view is a 3-pane Master-Detail layout (Filters -> List -> Detail Worksheet). Do not modify the CRM to default to a single-card "Focus Mode" or a wide table view. Keep action buttons visually neutral (outline style) so they don't look "already completed".
- **VTA Restrictions:** VTA signals automatically handle sector-based restrictions using EMTAK codes (primary_activity_code starting with 01, 02, 03 are restricted).
- **Nomenclature:** Never use specific person names (e.g., "Toomas") for variables, file names, views, or comments. Use role-based, neutral naming (e.g., `sales_priority_board`, "sales user").
- **Activity Logging:** Prefer natural language activity logging (`crm_add_activity`) connected to the prospect card rather than forcing the user to manually edit database rows.

## Technical

The site is an Astro static site deployed on Vercel and served through Cloudflare/DNS.

Before completing code work:
1. Run `npm run build`.
2. Commit the scoped change.
3. Push and deploy only when requested.
4. Verify the live domain when deployed.
5. Update `BACKLOG.md` if a new follow-up is discovered.
