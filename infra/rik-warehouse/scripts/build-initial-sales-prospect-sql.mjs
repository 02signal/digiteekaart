import { createWriteStream } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const defaults = {
  lihtandmedZip: "/private/tmp/digiteekaart-rik/lihtandmed.csv.zip",
  reportMetaZip: "/private/tmp/digiteekaart-rik/aruanded-yld.zip",
  reportElementsZip: "/private/tmp/digiteekaart-rik/aruanded2024.zip",
  out: "/private/tmp/digiteekaart-rik/initial-sales-prospects.sql",
  year: 2024,
  limit: 75,
  warehouseLimit: 250,
  minRevenue: 200000,
  maxRevenue: 5000000,
  minAge: 10,
  warehouseMinRevenue: 50000,
  warehouseMaxRevenue: 10000000,
  warehouseMinAge: 5,
  maxEmployees: 50,
  warehouseMaxEmployees: 100,
  prospectMinScore: 75,
  sourceDate: "2026-04-30"
};

const officialFiles = {
  lihtandmedZip: "https://avaandmed.ariregister.rik.ee/sites/default/files/avaandmed/ettevotja_rekvisiidid__lihtandmed.csv.zip",
  reportMetaZip: "https://avaandmed.ariregister.rik.ee/sites/default/files/1.aruannete_yldandmed_kuni_30042026_1.zip",
  reportElementsZip: "https://avaandmed.ariregister.rik.ee/sites/default/files/4.2024_aruannete_elemendid_kuni_30042026.zip"
};

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  const key = process.argv[index]?.replace(/^--/, "");
  const value = process.argv[index + 1];
  if (key && value) args.set(key, value);
}

const options = {
  lihtandmedZip: args.get("lihtandmed") || process.env.RIK_LIHTANDMED_ZIP || defaults.lihtandmedZip,
  reportMetaZip: args.get("reports-meta") || process.env.RIK_REPORT_META_ZIP || defaults.reportMetaZip,
  reportElementsZip: args.get("report-elements") || process.env.RIK_REPORT_ELEMENTS_ZIP || defaults.reportElementsZip,
  out: args.get("out") || process.env.RIK_PROSPECT_SQL_OUT || defaults.out,
  year: Number(args.get("year") || process.env.RIK_REPORT_YEAR || defaults.year),
  limit: Number(args.get("limit") || process.env.RIK_PROSPECT_LIMIT || defaults.limit),
  warehouseLimit: Number(args.get("warehouse-limit") || process.env.RIK_WAREHOUSE_LIMIT || defaults.warehouseLimit),
  minRevenue: Number(args.get("min-revenue") || process.env.RIK_MIN_REVENUE || defaults.minRevenue),
  maxRevenue: Number(args.get("max-revenue") || process.env.RIK_MAX_REVENUE || defaults.maxRevenue),
  minAge: Number(args.get("min-age") || process.env.RIK_MIN_AGE || defaults.minAge),
  warehouseMinRevenue: Number(args.get("warehouse-min-revenue") || process.env.RIK_WAREHOUSE_MIN_REVENUE || defaults.warehouseMinRevenue),
  warehouseMaxRevenue: Number(args.get("warehouse-max-revenue") || process.env.RIK_WAREHOUSE_MAX_REVENUE || defaults.warehouseMaxRevenue),
  warehouseMinAge: Number(args.get("warehouse-min-age") || process.env.RIK_WAREHOUSE_MIN_AGE || defaults.warehouseMinAge),
  maxEmployees: Number(args.get("max-employees") || process.env.RIK_MAX_EMPLOYEES || defaults.maxEmployees),
  warehouseMaxEmployees: Number(args.get("warehouse-max-employees") || process.env.RIK_WAREHOUSE_MAX_EMPLOYEES || defaults.warehouseMaxEmployees),
  prospectMinScore: Number(args.get("prospect-min-score") || process.env.RIK_PROSPECT_MIN_SCORE || defaults.prospectMinScore),
  sourceDate: args.get("source-date") || process.env.RIK_SOURCE_DATE || defaults.sourceDate
};

const parseCsvLine = (line) => {
  const cells = [];
  let current = "";
  let quoted = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === "\"" && quoted && next === "\"") {
      current += "\"";
      index += 1;
      continue;
    }

    if (char === "\"") {
      quoted = !quoted;
      continue;
    }

    if (char === ";" && !quoted) {
      cells.push(current);
      current = "";
      continue;
    }

    current += char;
  }

  cells.push(current);
  return cells.map((cell, index) => (index === 0 ? cell.replace(/^\uFEFF/, "") : cell));
};

const zipLines = (zipPath) => {
  const unzip = spawn("unzip", ["-p", zipPath], { stdio: ["ignore", "pipe", "inherit"] });
  return {
    lines: createInterface({ input: unzip.stdout, crlfDelay: Infinity }),
    done: new Promise((resolveDone, rejectDone) => {
      unzip.on("error", rejectDone);
      unzip.on("close", (code) => {
        if (code === 0) resolveDone();
        else rejectDone(new Error(`unzip failed for ${zipPath} with exit code ${code}`));
      });
    })
  };
};

const downloadIfRequested = async () => {
  if (args.get("download") !== "1" && process.env.RIK_DOWNLOAD_FILES !== "1") return;

  await mkdir(dirname(options.lihtandmedZip), { recursive: true });

  for (const [key, url] of Object.entries(officialFiles)) {
    const destination = options[key];
    const response = await fetch(url);
    if (!response.ok || !response.body) {
      throw new Error(`Download failed for ${url}: ${response.status}`);
    }

    const writer = createWriteStream(destination);
    const buffer = Buffer.from(await response.arrayBuffer());
    await new Promise((resolveWrite, rejectWrite) => {
      writer.on("error", rejectWrite);
      writer.end(buffer, resolveWrite);
    });
  }
};

const normalizeRegistryCode = (value) =>
  String(value || "").replace(/\D/g, "").slice(0, 8);

const toNumber = (value) => {
  const normalized = String(value || "").replace(",", ".").trim();
  if (!normalized) return null;
  const numberValue = Number(normalized);
  return Number.isFinite(numberValue) ? numberValue : null;
};

const toSql = (value) => {
  if (value === null || value === undefined || value === "") return "null";
  return `'${String(value).replace(/'/g, "''")}'`;
};

const toSqlNumber = (value) => {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "null";
  return String(Number(value));
};

const toIsoDate = (value) => {
  const text = String(value || "").trim();
  if (!text) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return text;

  const match = text.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/);
  if (!match) return null;

  const [, day, month, year] = match;
  return `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`;
};

const toSqlArray = (values) =>
  `array[${values.map(toSql).join(", ")}]::text[]`;

const yearsBetween = (registeredAt, sourceDate) => {
  if (!registeredAt) return null;
  const start = new Date(`${registeredAt}T00:00:00.000Z`);
  const end = new Date(`${sourceDate}T00:00:00.000Z`);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return null;
  return Math.max(0, Math.floor((end.getTime() - start.getTime()) / (365.25 * 24 * 60 * 60 * 1000)));
};

const scoreCandidate = (candidate) => {
  const scoreReason = [];
  let score = 0;

  if (candidate.statusText === "Registrisse kantud") {
    score += 15;
    scoreReason.push("ettevõte on registris aktiivne");
  }

  if (candidate.companyAgeYears >= 10) {
    score += 25;
    scoreReason.push("ettevõte on tegutsenud vähemalt 10 aastat");
  } else if (candidate.companyAgeYears >= 5) {
    score += 15;
    scoreReason.push("ettevõte on tegutsenud üle 5 aasta");
  }

  if (candidate.revenue >= 200000) {
    score += 35;
    scoreReason.push("müügitulu on tugev");
  } else if (candidate.revenue >= 50000) {
    score += 25;
    scoreReason.push("müügitulu paistab piisav");
  }

  scoreReason.push("VTA vajab kontrolli");

  return {
    priorityScore: Math.min(100, score),
    salesSignal: score >= 75 ? "good_first_call" : score >= 50 ? "needs_review" : "weak_fit",
    scoreReason
  };
};

const isProspectFit = (candidate) =>
  candidate.priorityScore >= options.prospectMinScore &&
  candidate.revenue >= options.minRevenue &&
  candidate.revenue <= options.maxRevenue &&
  candidate.companyAgeYears >= options.minAge &&
  (candidate.employeeCount === null || candidate.employeeCount <= options.maxEmployees);

const loadReportRegistryMap = async () => {
  const reportMap = new Map();
  const { lines, done } = zipLines(options.reportMetaZip);
  let header;

  for await (const line of lines) {
    const cells = parseCsvLine(line);
    if (!header) {
      header = cells;
      continue;
    }

    const row = Object.fromEntries(header.map((key, index) => [key, cells[index]]));
    const fiscalYear = Number(row.aruandeaasta);
    const registryCode = normalizeRegistryCode(row.registrikood);
    const reportId = String(row.report_id || "").trim();

    if (fiscalYear === options.year && registryCode && reportId) {
      reportMap.set(reportId, registryCode);
    }
  }

  await done;
  return reportMap;
};

const loadReportFacts = async (reportMap) => {
  const facts = new Map();
  const { lines, done } = zipLines(options.reportElementsZip);
  let header;

  for await (const line of lines) {
    const cells = parseCsvLine(line);
    if (!header) {
      header = cells;
      continue;
    }

    const row = Object.fromEntries(header.map((key, index) => [key, cells[index]]));
    const reportId = String(row.report_id || "").trim();
    const registryCode = reportMap.get(reportId);
    if (!registryCode) continue;

    const element = row.elemendi_nimetus;
    if (
      element !== "Revenue" &&
      element !== "AverageNumberOfEmployeesInFullTimeEquivalentUnits"
    ) {
      continue;
    }

    const fact = facts.get(registryCode) || { revenue: null, employeeCount: null };
    if (element === "Revenue") fact.revenue = toNumber(row.vaartus);
    if (element === "AverageNumberOfEmployeesInFullTimeEquivalentUnits") {
      fact.employeeCount = Math.round(toNumber(row.vaartus) || 0);
    }
    facts.set(registryCode, fact);
  }

  await done;
  return facts;
};

const loadCompanies = async (facts) => {
  const candidates = [];
  const { lines, done } = zipLines(options.lihtandmedZip);
  let header;

  for await (const line of lines) {
    const cells = parseCsvLine(line);
    if (!header) {
      header = cells;
      continue;
    }

    const row = Object.fromEntries(header.map((key, index) => [key, cells[index]]));
    const registryCode = normalizeRegistryCode(row.ariregistri_kood);
    const fact = facts.get(registryCode);
    if (!fact?.revenue || fact.revenue < options.warehouseMinRevenue) continue;
    if (fact.revenue > options.warehouseMaxRevenue) continue;
    if (fact.employeeCount !== null && fact.employeeCount > options.warehouseMaxEmployees) continue;

    const legalForm = row.ettevotja_oiguslik_vorm || "";
    if (!["Osaühing", "Aktsiaselts"].includes(legalForm)) continue;

    const statusText = row.ettevotja_staatus_tekstina || "";
    if (statusText !== "Registrisse kantud") continue;

    const registeredAt = toIsoDate(row.ettevotja_esmakande_kpv);
    const companyAgeYears = yearsBetween(registeredAt, options.sourceDate);
    if (companyAgeYears === null || companyAgeYears < options.warehouseMinAge) continue;

    const candidate = {
      registryCode,
      companyName: row.nimi || "",
      legalForm,
      statusText,
      registeredAt,
      companyAgeYears,
      addressSummary: row.asukoha_ehak_tekstina || row.asukoht_ettevotja_aadressis || null,
      revenue: fact.revenue,
      employeeCount: fact.employeeCount,
      latestFiscalYear: options.year
    };

    candidates.push({
      ...candidate,
      ...scoreCandidate(candidate)
    });
  }

  await done;

  return candidates
    .sort((a, b) =>
      Number(isProspectFit(b)) - Number(isProspectFit(a)) ||
      b.priorityScore - a.priorityScore ||
      b.revenue - a.revenue ||
      b.companyAgeYears - a.companyAgeYears ||
      a.companyName.localeCompare(b.companyName, "et")
    )
    .slice(0, options.warehouseLimit);
};

const buildSql = (candidates) => {
  const batchId = randomUUID();
  const listId = randomUUID();
  const sourceName = `RIK avaandmed ${options.year} - esimene sales shortlist`;
  const nowIso = new Date().toISOString();
  let prospectCount = 0;
  const lines = [
    "-- Generated by infra/rik-warehouse/scripts/build-initial-sales-prospect-sql.mjs",
    "-- Public company facts only. No personal contacts are imported.",
    "begin;",
    "",
    `insert into public_registry.rik_import_batches (id, source_name, source_kind, source_url, source_date, record_count, started_at, finished_at, status) values (${toSql(batchId)}, ${toSql(sourceName)}, 'bulk_file', ${toSql(officialFiles.lihtandmedZip)}, ${toSql(options.sourceDate)}, ${candidates.length}, ${toSql(nowIso)}, ${toSql(nowIso)}, 'completed') on conflict (id) do nothing;`,
    `insert into sales_crm.prospect_lists (id, name, description, source, created_by) values (${toSql(listId)}, ${toSql(`Esimene kõrge signaaliga müüginimekiri ${options.year}`)}, ${toSql(`Aktiivne OÜ/AS, vähemalt ${options.minAge} aastat vana, ${options.year} müügitulu ${options.minRevenue}-${options.maxRevenue} eurot, kuni ${options.maxEmployees} töötajat või töötajate arv teadmata. VTA vajab eraldi kontrolli.`)}, 'rik_warehouse', 'ak@ettevotluskeskus.ee') on conflict (id) do nothing;`,
    ""
  ];

  for (const candidate of candidates) {
    const pitch = `Tere, vaatasin avalike andmete põhjal, et ${candidate.companyName} on tegutsenud ${candidate.companyAgeYears} aastat ja ${candidate.latestFiscalYear}. aasta müügitulu paistab tugev. Kas teil on sel aastal mõni tarkvara, andmete või korduva töö korrastamise plaan, mille võiks toetusega läbi mõelda?`;

    lines.push(
      `insert into public_registry.rik_companies (registry_code, name, legal_form, status, registered_at, address_summary, source_updated_at, last_seen_at, last_import_batch_id, raw_source_kind) values (${toSql(candidate.registryCode)}, ${toSql(candidate.companyName)}, ${toSql(candidate.legalForm)}, ${toSql(candidate.statusText)}, ${toSql(candidate.registeredAt)}, ${toSql(candidate.addressSummary)}, ${toSql(nowIso)}, ${toSql(nowIso)}, ${toSql(batchId)}, 'rik_avaandmed_csv') on conflict (registry_code) do update set name = excluded.name, legal_form = excluded.legal_form, status = excluded.status, registered_at = excluded.registered_at, address_summary = excluded.address_summary, source_updated_at = excluded.source_updated_at, last_seen_at = excluded.last_seen_at, last_import_batch_id = excluded.last_import_batch_id;`,
      `insert into public_registry.rik_annual_reports (registry_code, fiscal_year, revenue, employee_count, report_status, source_updated_at, last_import_batch_id) values (${toSql(candidate.registryCode)}, ${candidate.latestFiscalYear}, ${toSqlNumber(candidate.revenue)}, ${toSqlNumber(candidate.employeeCount)}, 'avaandmed', ${toSql(nowIso)}, ${toSql(batchId)}) on conflict (registry_code, fiscal_year) do update set revenue = excluded.revenue, employee_count = excluded.employee_count, report_status = excluded.report_status, source_updated_at = excluded.source_updated_at, last_import_batch_id = excluded.last_import_batch_id, updated_at = now();`
    );

    if (
      prospectCount < options.limit &&
      isProspectFit(candidate)
    ) {
      prospectCount += 1;
      lines.push(
        `insert into sales_crm.prospect_companies (list_id, registry_code, company_name, legal_form, status, registered_at, company_age_years, address_summary, average_revenue_last_two, latest_employee_count, latest_fiscal_year, vta_signal, sales_signal, priority_score, score_reason, recommended_pitch, next_action, crm_status, source_system, source_observed_at) select ${toSql(listId)}, ${toSql(candidate.registryCode)}, ${toSql(candidate.companyName)}, ${toSql(candidate.legalForm)}, ${toSql(candidate.statusText)}, ${toSql(candidate.registeredAt)}, ${candidate.companyAgeYears}, ${toSql(candidate.addressSummary)}, ${toSqlNumber(candidate.revenue)}, ${toSqlNumber(candidate.employeeCount)}, ${candidate.latestFiscalYear}, 'not_checked', ${toSql(candidate.salesSignal)}, ${candidate.priorityScore}, ${toSqlArray(candidate.scoreReason)}, ${toSql(pitch)}, 'Kontrolli VTA jääk. Kui jääk sobib, tee esimene kõne.', 'call_next', 'rik_avaandmed_csv', ${toSql(nowIso)} where not exists (select 1 from sales_crm.prospect_companies where registry_code = ${toSql(candidate.registryCode)} and crm_status not in ('do_not_contact', 'won', 'lost'));`,
        `update sales_crm.prospect_companies set address_summary = ${toSql(candidate.addressSummary)}, updated_at = now() where registry_code = ${toSql(candidate.registryCode)} and source_system in ('rik_warehouse', 'rik_avaandmed_csv');`
      );
    }

    lines.push("");
  }

  lines.push("commit;", "");
  return {
    sql: lines.join("\n"),
    prospectCount
  };
};

await downloadIfRequested();

console.error("Loading report metadata...");
const reportMap = await loadReportRegistryMap();
console.error(`Loaded ${reportMap.size} report mappings for ${options.year}.`);

console.error("Loading report facts...");
const facts = await loadReportFacts(reportMap);
console.error(`Loaded ${facts.size} company report fact rows.`);

console.error("Selecting companies...");
const candidates = await loadCompanies(facts);
if (candidates.length === 0) {
  throw new Error("No candidates matched the current filters.");
}

const { sql, prospectCount } = buildSql(candidates);
await mkdir(dirname(resolve(options.out)), { recursive: true });
await writeFile(options.out, sql, "utf8");

console.log(JSON.stringify({
  out: options.out,
  warehouseCount: candidates.length,
  prospectCount,
  top: candidates.slice(0, 5).map((candidate) => ({
    registryCode: candidate.registryCode,
    companyName: candidate.companyName,
    revenue: candidate.revenue,
    companyAgeYears: candidate.companyAgeYears,
    priorityScore: candidate.priorityScore
  }))
}, null, 2));
