type CompanyLookupRequest = {
  registryCode?: string;
};

type CompanyLookupResult = {
  registryCode: string;
  companyName: string | null;
  statusCode: string | null;
  statusText: string | null;
  legalForm: string | null;
  firstRegisteredAt: string | null;
  addressSummary: string | null;
  foundCount: number | null;
  checkedAt: string;
  source: "RIK";
};

const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

const corsHeaders = (request: Request) => {
  const origin = request.headers.get("Origin") || "";
  const allowOrigin =
    allowedOrigins.length === 0 || allowedOrigins.includes(origin)
      ? origin || "*"
      : allowedOrigins[0];

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
};

const jsonResponse = (request: Request, status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
    },
  });

const escapeXml = (value: string) =>
  value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");

const decodeXml = (value: string) =>
  value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();

const readTag = (xml: string, tag: string) => {
  const match = xml.match(new RegExp(`<[^:>]*:?${tag}[^>]*>(.*?)</[^:>]*:?${tag}>`, "s"));
  return match?.[1] ? decodeXml(match[1]) : null;
};

const readNumberTag = (xml: string, tag: string) => {
  const value = readTag(xml, tag);
  if (!value) return null;
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : null;
};

const normalizeRegistryCode = (value: unknown) =>
  String(value || "")
    .replace(/\D/g, "")
    .slice(0, 8);

const buildEnvelope = (username: string, password: string, registryCode: string) => `<?xml version="1.0" encoding="UTF-8"?>
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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(request) });
  }

  if (request.method !== "POST") {
    return jsonResponse(request, 405, { error: "method_not_allowed" });
  }

  const username = Deno.env.get("RIK_API_USERNAME");
  const password = Deno.env.get("RIK_API_PASSWORD");
  const endpoint = Deno.env.get("RIK_API_ENDPOINT") || "https://ariregxmlv6.rik.ee/";

  if (!username || !password) {
    return jsonResponse(request, 500, { error: "rik_credentials_missing" });
  }

  let payload: CompanyLookupRequest;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse(request, 400, { error: "invalid_json" });
  }

  const registryCode = normalizeRegistryCode(payload.registryCode);
  if (!/^[0-9]{8}$/.test(registryCode)) {
    return jsonResponse(request, 400, { error: "invalid_registry_code" });
  }

  const startedAt = Date.now();
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "text/xml; charset=utf-8",
      SOAPAction: "",
    },
    body: buildEnvelope(username, password, registryCode),
  });

  const xml = await response.text();
  const checkedAt = new Date().toISOString();

  if (!response.ok) {
    return jsonResponse(request, 502, {
      error: "rik_http_error",
      status: response.status,
      checkedAt,
    });
  }

  const result: CompanyLookupResult = {
    registryCode,
    companyName: readTag(xml, "evnimi"),
    statusCode: readTag(xml, "staatus"),
    statusText: readTag(xml, "staatus_tekstina"),
    legalForm: readTag(xml, "oiguslik_vorm_tekstina"),
    firstRegisteredAt: readTag(xml, "esmakande_aeg"),
    addressSummary: readTag(xml, "aadress_ads__ads_normaliseeritud_taisaadress"),
    foundCount: readNumberTag(xml, "leitud_ettevotjate_arv"),
    checkedAt,
    source: "RIK",
  };

  return jsonResponse(request, 200, {
    result,
    meta: {
      durationMs: Date.now() - startedAt,
      rawPayloadReturned: false,
    },
  });
});
