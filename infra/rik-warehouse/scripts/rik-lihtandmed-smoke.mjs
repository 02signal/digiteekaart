#!/usr/bin/env node

const endpoint = process.env.RIK_API_ENDPOINT || "https://ariregxmlv6.rik.ee/";
const username = process.env.RIK_API_USERNAME;
const password = process.env.RIK_API_PASSWORD;
const registryCode = process.env.RIK_REGISTRY_CODE || "14127891";

if (!username || !password) {
  console.error("Missing RIK_API_USERNAME or RIK_API_PASSWORD.");
  console.error("Example:");
  console.error("RIK_API_USERNAME=... RIK_API_PASSWORD=... RIK_REGISTRY_CODE=14127891 node infra/rik-warehouse/scripts/rik-lihtandmed-smoke.mjs");
  process.exit(1);
}

if (!/^[0-9]{8}$/.test(registryCode)) {
  console.error("RIK_REGISTRY_CODE must be an 8-digit Estonian registry code.");
  process.exit(1);
}

const escapeXml = (value) =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");

const envelope = `<?xml version="1.0" encoding="UTF-8"?>
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

const response = await fetch(endpoint, {
  method: "POST",
  headers: {
    "Content-Type": "text/xml; charset=utf-8",
    "SOAPAction": "",
  },
  body: envelope,
});

const text = await response.text();

if (!response.ok) {
  console.error(`RIK API HTTP ${response.status}`);
  console.error(text.slice(0, 1000));
  process.exit(1);
}

const readTag = (tag) => {
  const match = text.match(new RegExp(`<[^:>]*:?${tag}[^>]*>(.*?)</[^:>]*:?${tag}>`, "s"));
  return match?.[1]?.replace(/\s+/g, " ").trim() || null;
};

const result = {
  endpoint,
  registryCode,
  companyName: readTag("evnimi"),
  statusCode: readTag("staatus"),
  statusText: readTag("staatus_tekstina"),
  legalForm: readTag("oiguslik_vorm_tekstina"),
  firstRegisteredAt: readTag("esmakande_aeg"),
  foundCount: readTag("leitud_ettevotjate_arv"),
};

console.log(JSON.stringify(result, null, 2));
