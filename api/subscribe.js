// Vercel serverless function — lead capture for digiteekaart.ee.
//
// Ported from ~/GitHub/teekaart/api/subscribe.js (itself ported from
// automatiseerimine, from mikrokvalifikatsioon — the ONE lead capture pattern
// proven end to end: site form -> this function -> AMOS outreach-capture ->
// Listmonk double opt-in -> confirmed subscriber). This site's form used to
// POST to a Supabase edge function (PUBLIC_SITE_LEAD_WEBHOOK_URL,
// miwpctshbcmkpwvdokne.supabase.co/functions/v1/site-lead-intake -> table
// site_leads, name/email/phone/company stored in CLEAR TEXT) whose data-plane
// subdomain stopped resolving entirely on 2026-08-27 (confirmed NXDOMAIN from
// three independent resolvers) — every submission has been silently falling
// back to mailto: since. Per owner direction, this is a privacy correction as
// much as a plumbing fix: the digiteekaart ADR says verbatim "person data is
// never loaded into digiteekaart Supabase", and the AMOS path never receives
// name/phone/company at all (see below) — that PII stays in the mailto
// fallback text only, exactly as it does on every other ported site. Per
// owner direction, site_leads is retired outright; no migration of its
// existing rows is attempted (it is unreachable, and recovery was written
// off — see the digiteekaart migration recon report, 2026-08-28).
//
// Only ONE capture surface exists on this site today: the "eelhindamine"
// (pre-assessment) form on / (index.astro). `source_site` is therefore fixed
// to `funnel_digiteekaart` — already a live member of both the AMOS
// lead-capture-contract ALLOWED_CAPTURE_SITES enum and the service's
// CAPTURE_SITE_TO_BRAND_KEY map (-> brand_key "digiteekaart", its own
// registered brand and Resend-verified sender, info@digiteekaart.ee — same
// as teekaart, unlike automatiseerimine/digitaliseerimine which ride the
// shared evk_base face). It already has its own confirm-page face (#4499).
//
// Topic choice: `interest_topic` MUST be a member of AMOS's
// ALLOWED_INTEREST_TOPICS (infra/contracts/outreach/lead-capture-contract.mjs)
// — inventing a new one is out of scope for this change. Unlike teekaart/
// digitaliseerimine/automatiseerimine (which all had to borrow an adjacent
// topic), digiteekaart does NOT need to borrow: "digiteekaart" is itself a
// ratified ALLOWED_INTEREST_TOPICS member. No topic routing to
// "koolitus_huvi" — that topic is pre-contractual-inquiry lawful basis only,
// excluded at the contract level (CONFIRMED_SUBSCRIBER_LIST_EXCLUDED_TOPICS),
// never a marketing consent topic.
//
// TWO separate consents, ONE capture call: this form has two checkboxes —
// consentContact (required: "Nõustun, et Ettevõtluskeskus OÜ kasutab minu
// andmeid eelhindamiseks ja ühenduse võtmiseks") and consentFundingUpdates
// (optional: "Soovin saada e-mailiga infot avanevate toetuste ja uute
// rahastusvõimaluste kohta"). Two capture calls would mint two capture_refs
// and send the person TWO double opt-in emails — the owner ruled this out.
// So this function sends AT MOST ONE call to AMOS, with `consent_purpose`
// for the always-required contact consent and, only when
// consentFundingUpdates is checked, `consent_purpose_secondary` for the
// funding-updates consent (2026-08-28 AMOS-side addition — see
// 02S-AMOS PR feat/lead-capture-two-consents, cross-linked from this PR).
//
//   consent_purpose: "b2b_outreach" — this is advisory/pre-assessment work,
//     not a course; same choice every other ported site made.
//   consent_purpose_secondary: "newsletter" — the funding-updates checkbox is
//     literally "email me later when something new opens", an ongoing
//     informational subscription, not tied to any specific course
//     (course_offers), event (event_info), or survey (survey_followup), and
//     NOT the same purpose as the contact consent (b2b_outreach covers the
//     immediate advisory contact, not a standing subscription) — reusing
//     b2b_outreach for both would collapse two genuinely different consents
//     into one and lose the distinction the two checkboxes exist to capture.
//
// Required env (Vercel project settings — same ingress every ported site uses):
//   AMOS_TOPIC_CAPTURE_URL   the AMOS ingress endpoint (https)
//   AMOS_CAPTURE_TOKEN       shared bearer the ingress checks (legacy shared
//                            token path — no OUTREACH_CAPTURE_TOKEN__* per-site
//                            token exists for ANY site today, confirmed by
//                            team-lead directly against the host secrets file;
//                            per-site tokens are a separate hygiene question
//                            for all five brands, not this migration)

const ALLOWED_TOPICS = new Set(['digiteekaart']);
const ALLOWED_SITES = new Set(['funnel_digiteekaart']);
const ALLOWED_KINDS = new Set(['topic_subscribe']);
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Bounded per the shared envelope contract (infra/contracts/outreach/
// lead-capture-contract.mjs: MAX_CONTEXT_OUTCOMES=24, MAX_CONTEXT_TEXT_LENGTH=240,
// CONTEXT_FORBIDDEN_TEXT_REGEX rejects @ / http(s):// / < / > / control chars).
// `field` is clipped tighter (64) on purpose — it carries a short task label,
// never a paragraph.
const MAX_FIELD_LEN = 64;
const MAX_OUTCOMES = 24;
const MAX_OUTCOME_LEN = 240;
const FORBIDDEN_TEXT_RE = /(@|https?:\/\/|<|>|[\u0000-\u001f])/gi;

function readBody(req) {
  return new Promise((resolve) => {
    if (req.body) { resolve(typeof req.body === 'string' ? safeParse(req.body) : req.body); return; }
    let raw = '';
    req.on('data', (c) => { raw += c; if (raw.length > 32768) req.destroy(); });
    req.on('end', () => resolve(safeParse(raw)));
    req.on('error', () => resolve(null));
  });
}
function safeParse(s) { try { return JSON.parse(s); } catch { return null; } }

// Defensive client-side-adjacent sanitising: strip whatever the envelope
// contract would reject outright (never trust the browser), then bound
// length. Returns null for "nothing usable left" rather than an empty string,
// so callers can tell "not provided" from "provided but empty".
function cleanText(value, maxLen) {
  if (typeof value !== 'string') return null;
  const stripped = value.replace(FORBIDDEN_TEXT_RE, '').trim().slice(0, maxLen);
  return stripped || null;
}

function cleanOutcomes(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const out = [];
  for (const item of value) {
    const text = cleanText(item, MAX_OUTCOME_LEN);
    if (!text) continue;
    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(text);
    if (out.length >= MAX_OUTCOMES) break;
  }
  return out;
}

// GDPR erasure (Art. 17): route an account-deletion request to the AMOS erasure
// endpoint (POST /api/outreach/v1/erasure — suppression-first, then deletion).
// NEVER subscribes. Endpoint: AMOS_ERASURE_URL, else derived from
// AMOS_TOPIC_CAPTURE_URL (…/erasure). Kept even though this site has no
// account UI: it is the same public POST target, so the same fail-closed
// GDPR branch has to exist here too.
async function forwardErasure(email, sourceSite, res) {
  const erasureUrl =
    process.env.AMOS_ERASURE_URL
    || (process.env.AMOS_TOPIC_CAPTURE_URL || '').replace(/\/[^/]*$/, '/erasure');
  if (erasureUrl) {
    try {
      const r = await fetch(erasureUrl, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          ...(process.env.AMOS_CAPTURE_TOKEN ? { authorization: `Bearer ${process.env.AMOS_CAPTURE_TOKEN}` } : {}),
        },
        body: JSON.stringify({
          capture_version: 'amos.outreach.lead_capture/v1',
          email,
          requested_at: new Date().toISOString(),
          scope: 'all_outreach_data',
          status: 'received',
          source_site: sourceSite,
        }),
      });
      if (r.ok) { res.status(200).json({ ok: true, status: 'erasure_requested' }); return; }
      console.error('subscribe: erasure ingress status', r.status);
    } catch (e) {
      console.error('subscribe: erasure ingress error', e && e.message);
    }
  } else {
    console.error('subscribe: no erasure endpoint configured (AMOS_ERASURE_URL / AMOS_TOPIC_CAPTURE_URL)');
  }
  // Fail-closed for GDPR: we did NOT subscribe. Honest response.
  res.status(200).json({
    ok: true,
    status: 'erasure_pending',
    message: 'Kustutustaotlus on vastu võetud. Kui see ei jõua automaatselt kohale, kirjuta info@02signal.ai.',
  });
}

export default async function handler(req, res) {
  res.setHeader('content-type', 'application/json; charset=utf-8');
  if (req.method !== 'POST') { res.status(405).json({ message: 'Method not allowed' }); return; }

  const body = await readBody(req);
  if (!body || typeof body !== 'object') { res.status(400).json({ message: 'Vigane päring.' }); return; }

  const kind = ALLOWED_KINDS.has(body.kind) ? body.kind : 'topic_subscribe';
  const email = String(body.email || '').trim().toLowerCase();
  const field = cleanText(body.field, MAX_FIELD_LEN);
  const outcomes = cleanOutcomes(body.outcomes);
  const sourceSite = ALLOWED_SITES.has(body.source_site) ? body.source_site : 'funnel_digiteekaart';

  if (!EMAIL_RE.test(email) || email.length > 254) { res.status(400).json({ message: 'Palun sisesta korrektne e-post.' }); return; }

  // PBI-01-equivalent (GDPR Art. 17): account deletion must NEVER fall through
  // to a subscription. Checked on the RAW body.kind, before normalisation.
  if (body.kind === 'account_delete' || body.kind === 'erasure') {
    return forwardErasure(email, sourceSite, res);
  }

  const topic = String(body.topic || '').trim();
  if (!ALLOWED_TOPICS.has(topic)) { res.status(400).json({ message: 'Tundmatu teema.' }); return; }

  // The required contact consent must actually be checked — mirrors the
  // form's own `required` attribute on consentContact, enforced again
  // server-side (never trust the browser).
  if (body.consentContact !== true) {
    res.status(400).json({ message: 'Palun anna nõusolek, et saaksime ühendust võtta.' });
    return;
  }

  const ingress = process.env.AMOS_TOPIC_CAPTURE_URL;
  if (!ingress) {
    // Never silently drop a subscriber: tell them honestly + log for the operator.
    console.error('subscribe: AMOS_TOPIC_CAPTURE_URL is not configured');
    res.status(503).json({ message: 'Ühenduse võtmine on hetkel ajutiselt suletud. Proovi varsti uuesti või helista +372 5818 0435.' });
    return;
  }

  try {
    const r = await fetch(ingress, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(process.env.AMOS_CAPTURE_TOKEN ? { authorization: `Bearer ${process.env.AMOS_CAPTURE_TOKEN}` } : {}),
      },
      body: JSON.stringify({
        // Forward ONLY keys the AMOS lead_capture ingress allow-lists (kind,
        // email, interest_topic, field, outcomes, consent_purpose,
        // consent_purpose_secondary, source_site, captured_at) — any other
        // key is rejected (422).
        kind,
        email,
        interest_topic: topic,
        ...(field ? { field } : {}),
        ...(outcomes.length ? { outcomes } : {}),
        // Digiteekaart sells EIS teekaardi/funding pre-assessment advisory
        // work, not a course — b2b_outreach is the correct ratified consent
        // purpose (amos.outreach.lead_capture/v1), distinct from
        // course_offers, same choice every other ported site made.
        consent_purpose: 'b2b_outreach',
        // Second, OPTIONAL consent: only when the funding-updates checkbox
        // was actually checked. "newsletter" is the ongoing informational
        // subscription purpose — see the header comment above for why this
        // is not b2b_outreach again, and never koolitus_huvi.
        ...(body.consentFundingUpdates === true ? { consent_purpose_secondary: 'newsletter' } : {}),
        source_site: sourceSite,
        captured_at: new Date().toISOString(),
      }),
    });
    if (r.status === 429) {
      // The rate limiter working as designed, not a server failure — must
      // not be reported to the visitor or logged as one (measured live,
      // 28.08.2026: this was being mapped to 502 "Saatmine ebaõnnestus",
      // indistinguishable from a real outage in both the response and our
      // own error logs).
      res.status(429).json({ ok: false, message: 'Korraga tuli liiga palju päringuid. Palun proovi mõne minuti pärast uuesti.' });
      return;
    }
    if (!r.ok) { console.error('subscribe: ingress status', r.status); res.status(502).json({ message: 'Saatmine ebaõnnestus. Proovi hiljem uuesti.' }); return; }
    res.status(200).json({ ok: true });
  } catch (e) {
    console.error('subscribe: ingress error', e && e.message);
    res.status(502).json({ message: 'Saatmine ebaõnnestus. Proovi hiljem uuesti.' });
  }
}
