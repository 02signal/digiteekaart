// Vercel serverless function — Estonian business registry (RIK) lookup for
// digiteekaart.ee's form autocomplete.
//
// Ported from supabase/functions/rik-company-lookup/index.ts (Deno edge
// function), which called RIK directly and stored/proxied nothing itself —
// no PII, no site_leads-style problem, just a same-origin proxy in front of
// RIK's own APIs. Kept as its OWN function, deliberately NOT folded into the
// AMOS lead-capture migration: this is a company-registry enrichment lookup
// (autocomplete-as-you-type + full lookup by registry code), not a lead
// capture, and AMOS has no equivalent endpoint (checked: no live single-
// company RIK lookup exists anywhere in 02S-AMOS outside its unrelated
// labor-market ingestion pipeline). The owner wants this feature kept — it
// is the difference between a form filled out correctly and one abandoned
// partway through a registry code.
//
// Two RIK data sources, same as the original:
//   1. Free-text autocomplete search (`query`) — RIK's own public JSON API,
//      https://ariregister.rik.ee/est/api/autocomplete, no credentials.
//   2. Full lookup by registry code (`registryCode`) — RIK's X-Road SOAP/XML
//      API (lihtandmed_v2), which DOES require X-Road member credentials.
//
// Required env (Vercel project settings):
//   RIK_API_USERNAME    X-Road member username for the lihtandmed_v2 lookup
//   RIK_API_PASSWORD    X-Road member password
//   RIK_API_ENDPOINT     optional; defaults to https://ariregxmlv6.rik.ee/
//
// IMPORTANT — could not be verified by this change: these three env vars
// previously lived in the (now-dead) Supabase project's function settings,
// never in this Vercel project (this route did not exist here before). No
// Vercel API access was available while writing this port, so whether
// RIK_API_USERNAME/RIK_API_PASSWORD need to be newly added to Vercel, or
// already exist from some other integration, is NOT something this change
// can confirm — check the Vercel dashboard before relying on the
// registry-code lookup path. The autocomplete path needs no credentials and
// works either way.
//
// No CORS layer: unlike the Supabase edge function (a genuinely different
// origin the browser called cross-origin), this is a same-origin Vercel
// route under the site's own domain — matches every other api/*.js function
// in this repo (subscribe.js has no CORS handling either).

const registryCodeRe = /^[0-9]{8}$/;

function readBody(req) {
  return new Promise((resolve) => {
    if (req.body) { resolve(typeof req.body === 'string' ? safeParse(req.body) : req.body); return; }
    let raw = '';
    req.on('data', (c) => { raw += c; if (raw.length > 8192) req.destroy(); });
    req.on('end', () => resolve(safeParse(raw)));
    req.on('error', () => resolve(null));
  });
}
function safeParse(s) { try { return JSON.parse(s); } catch { return null; } }

function normalizeRegistryCode(value) {
  return String(value || '').replace(/\D/g, '').slice(0, 8);
}

function normalizeCompanyQuery(value) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, 80);
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function decodeXml(value) {
  return String(value)
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

function readTag(xml, tag) {
  const match = xml.match(new RegExp(`<[^:>]*:?${tag}[^>]*>(.*?)</[^:>]*:?${tag}>`, 's'));
  return match && match[1] ? decodeXml(match[1]) : null;
}

function readNumberTag(xml, tag) {
  const value = readTag(xml, tag);
  if (!value) return null;
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : null;
}

function buildEnvelope(username, password, registryCode) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:prod="http://arireg.x-road.eu/producer/">
  <soapenv:Body>
    <prod:lihtandmed_v2>
      <prod:keha>
        <prod:ariregister_kasutajanimi>${escapeXml(username)}</prod:ariregister_kasutajanimi>
        <prod:ariregister_parool>${escapeXml(password)}</prod:ariregister_parool>
        <prod:ariregistri_kood>${registryCode}</prod:ariregistri_kood>
        <prod:keel>est</prod:keel>
      </prod:keha>
    </prod:lihtandmed_v2>
  </soapenv:Body>
</soapenv:Envelope>`;
}

function autocompleteUrl(query) {
  return `https://ariregister.rik.ee/est/api/autocomplete?q=${encodeURIComponent(query)}&deleted_companies=0&historical_names=0`;
}

async function searchCompanies(res, query) {
  const normalizedQuery = normalizeCompanyQuery(query);
  if (normalizedQuery.length < 2) {
    res.status(400).json({ error: 'query_too_short' });
    return;
  }

  const startedAt = Date.now();
  let response;
  try {
    response = await fetch(autocompleteUrl(normalizedQuery), { headers: { Accept: 'application/json' } });
  } catch (e) {
    console.error('rik-lookup: autocomplete fetch error', e && e.message);
    res.status(502).json({ error: 'rik_autocomplete_unreachable' });
    return;
  }
  const checkedAt = new Date().toISOString();

  if (!response.ok) {
    res.status(502).json({ error: 'rik_autocomplete_http_error', status: response.status, checkedAt });
    return;
  }

  const body = await response.json();
  const results = (body.data || [])
    .slice(0, 8)
    .map((item) => ({
      registryCode: normalizeRegistryCode(item.reg_code),
      companyName: item.name || null,
      statusCode: item.status || null,
      legalFormCode: item.legal_form ? String(item.legal_form) : null,
      addressSummary: item.legal_address || null,
      sourceUrl: item.url || null,
      source: 'RIK_AUTOCOMPLETE',
    }))
    .filter((item) => item.registryCode && item.companyName);

  res.status(200).json({
    query: normalizedQuery,
    results,
    meta: { durationMs: Date.now() - startedAt, checkedAt, rawPayloadReturned: false },
  });
}

export default async function handler(req, res) {
  res.setHeader('content-type', 'application/json; charset=utf-8');
  if (req.method !== 'POST') { res.status(405).json({ error: 'method_not_allowed' }); return; }

  const payload = await readBody(req);
  if (!payload || typeof payload !== 'object') { res.status(400).json({ error: 'invalid_json' }); return; }

  const query = normalizeCompanyQuery(payload.query);
  if (query) {
    await searchCompanies(res, query);
    return;
  }

  const registryCode = normalizeRegistryCode(payload.registryCode);
  if (!registryCodeRe.test(registryCode)) {
    res.status(400).json({ error: 'invalid_registry_code' });
    return;
  }

  const username = process.env.RIK_API_USERNAME;
  const password = process.env.RIK_API_PASSWORD;
  const endpoint = process.env.RIK_API_ENDPOINT || 'https://ariregxmlv6.rik.ee/';

  if (!username || !password) {
    console.error('rik-lookup: RIK_API_USERNAME/RIK_API_PASSWORD not configured');
    res.status(500).json({ error: 'rik_credentials_missing' });
    return;
  }

  const startedAt = Date.now();
  let response;
  try {
    response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'text/xml; charset=utf-8', SOAPAction: '' },
      body: buildEnvelope(username, password, registryCode),
    });
  } catch (e) {
    console.error('rik-lookup: registry lookup fetch error', e && e.message);
    res.status(502).json({ error: 'rik_unreachable' });
    return;
  }

  const xml = await response.text();
  const checkedAt = new Date().toISOString();

  if (!response.ok) {
    res.status(502).json({ error: 'rik_http_error', status: response.status, checkedAt });
    return;
  }

  const result = {
    registryCode,
    companyName: readTag(xml, 'evnimi'),
    statusCode: readTag(xml, 'staatus'),
    statusText: readTag(xml, 'staatus_tekstina'),
    legalForm: readTag(xml, 'oiguslik_vorm_tekstina'),
    firstRegisteredAt: readTag(xml, 'esmakande_aeg'),
    addressSummary: readTag(xml, 'aadress_ads__ads_normaliseeritud_taisaadress'),
    foundCount: readNumberTag(xml, 'leitud_ettevotjate_arv'),
    checkedAt,
    source: 'RIK',
  };

  res.status(200).json({
    result,
    meta: { durationMs: Date.now() - startedAt, rawPayloadReturned: false },
  });
}
