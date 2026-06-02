import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "../../..");

const fixturePath = resolve(__dirname, "../fixtures/ettevotluskeskus.sample.json");
const rulesPath = resolve(root, "public/funding-programs.json");

const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
const rules = JSON.parse(await readFile(rulesPath, "utf8"));

const averageRevenue = Math.round(
  fixture.annualReports
    .slice(0, 2)
    .reduce((sum, report) => sum + Number(report.revenue || 0), 0) / 2
);

const requestedNeed = fixture.ownerInputs.requestedNeed;
const hasRoadmap = fixture.ownerInputs.hasRoadmap;

const byId = new Map(rules.programs.map((program) => [program.id, program]));

let programId = "digital_roadmap";
if (requestedNeed === "software") programId = "rte_software";
if (requestedNeed === "development") programId = hasRoadmap === "yes" ? "roadmap_development" : "digital_roadmap";
if (requestedNeed === "automation") programId = "rte_automation";

const program = byId.get(programId);
const revenueOk = averageRevenue >= Number(program.minAverageRevenue || 0);

const missingChecks = [
  "VTA jääk",
  "maksuvõla kontroll",
  "varasemad sama sisuga toetused"
];

const result = {
  registryCode: fixture.company.registryCode,
  companyName: fixture.company.name,
  averageRevenue,
  recommendedProgram: program.shortName,
  possibleSupport: program.supportText,
  preliminaryStatus: revenueOk ? "can_check_further" : "revenue_below_threshold",
  ownerAnswer: revenueOk
    ? `${program.shortName} võib olla loogiline esimene tee.`
    : `Müügitulu ei paista selle programmi piiri täitvat.`,
  missingChecks
};

console.log(JSON.stringify(result, null, 2));

if (result.preliminaryStatus !== "can_check_further") {
  process.exitCode = 1;
}
