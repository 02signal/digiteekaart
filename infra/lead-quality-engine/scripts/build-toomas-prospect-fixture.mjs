import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "../../..");
const fixturePath = resolve(root, "infra/rik-warehouse/fixtures/ettevotluskeskus.sample.json");

const fixture = JSON.parse(await readFile(fixturePath, "utf8"));

const checkedAt = new Date(`${fixture.sourceCheckedAt}T00:00:00.000Z`);
const registeredAt = new Date(`${fixture.company.registeredAt}T00:00:00.000Z`);
const companyAgeYears = Math.max(
  0,
  Math.floor((checkedAt.getTime() - registeredAt.getTime()) / (365.25 * 24 * 60 * 60 * 1000))
);

const latestTwoReports = fixture.annualReports
  .slice()
  .sort((a, b) => Number(b.fiscalYear) - Number(a.fiscalYear))
  .slice(0, 2);

const averageRevenueLastTwo = Math.round(
  latestTwoReports.reduce((sum, report) => sum + Number(report.revenue || 0), 0) /
    Math.max(1, latestTwoReports.length)
);
const latestEmployeeCount = latestTwoReports.find((report) => report.employeeCount !== null)?.employeeCount ?? null;

const deMinimisLimit = 300000;
const deMinimisUsed = Number(fixture.ownerInputs.deMinimisUsed ?? 0);
const deMinimisLeft = Math.max(0, deMinimisLimit - deMinimisUsed);

const scoreReason = [];
let priorityScore = 0;

if (fixture.company.status === "active") {
  priorityScore += 15;
  scoreReason.push("ettevõte on aktiivne");
}

if (companyAgeYears >= 30) {
  priorityScore += 25;
  scoreReason.push("ettevõte on tegutsenud vähemalt 30 aastat");
} else if (companyAgeYears >= 20) {
  priorityScore += 22;
  scoreReason.push("ettevõte on tegutsenud vähemalt 20 aastat");
} else if (companyAgeYears >= 10) {
  priorityScore += 18;
  scoreReason.push("ettevõte on tegutsenud vähemalt 10 aastat");
} else if (companyAgeYears >= 5) {
  priorityScore += 10;
  scoreReason.push("ettevõte on tegutsenud üle 5 aasta");
}

if (latestEmployeeCount >= 25) {
  priorityScore += 20;
  scoreReason.push("ettevõttes on vähemalt 25 töötajat");
} else if (latestEmployeeCount >= 10) {
  priorityScore += 14;
  scoreReason.push("ettevõttes on vähemalt 10 töötajat");
} else if (latestEmployeeCount >= 3) {
  priorityScore += 8;
  scoreReason.push("ettevõttes on mitu inimest tööl");
}

if (averageRevenueLastTwo >= 1000000) {
  priorityScore += 25;
  scoreReason.push("müügitulu on tugev");
} else if (averageRevenueLastTwo >= 200000) {
  priorityScore += 20;
  scoreReason.push("müügitulu lubab praktilist projekti arutada");
} else if (averageRevenueLastTwo >= 50000) {
  priorityScore += 12;
  scoreReason.push("müügitulu paistab toetuse eelhinnanguks piisav");
}

if (deMinimisLeft >= 50000) {
  priorityScore += 10;
  scoreReason.push("VTA jääk paistab suur");
} else if (deMinimisLeft >= 10000) {
  priorityScore += 6;
  scoreReason.push("VTA jääki paistab veel olevat");
}

if (fixture.company.primaryActivityName) {
  priorityScore += 5;
  scoreReason.push("tegevusala on tuvastatav");
}

priorityScore = Math.min(100, priorityScore);

const vtaSignal =
  deMinimisLeft >= 50000
    ? "high_left"
    : deMinimisLeft >= 10000
      ? "some_left"
      : deMinimisLeft > 0
        ? "low_left"
        : "used_up";

const salesSignal =
  priorityScore >= 75 ? "good_first_call" : priorityScore >= 50 ? "needs_review" : "weak_fit";

const recommendedPitch =
  salesSignal === "good_first_call"
    ? `Tere, vaatasin avalike andmete põhjal, et ${fixture.company.name} on tegutsenud ${companyAgeYears} aastat ja VTA jääk paistab kasutatav. Kas teil on sel aastal mõni tarkvara, andmete või tööde korrastamise plaan, mille võiks toetusega läbi mõelda?`
    : `Tere, kontrollime ettevõtte andmeid ja toetuse võimalust. Kas teil on mõni korduv töö või tarkvara plaan, mille kohta soovite kiiret eelhinnangut?`;

const result = {
  registryCode: fixture.company.registryCode,
  companyName: fixture.company.name,
  status: fixture.company.status,
  companyAgeYears,
  primaryActivityName: fixture.company.primaryActivityName,
  averageRevenueLastTwo,
  latestEmployeeCount,
  deMinimisUsed,
  deMinimisLeft,
  vtaSignal,
  priorityScore,
  salesSignal,
  scoreReason,
  recommendedPitch,
  nextAction:
    salesSignal === "good_first_call"
      ? "Lisa VTA kontrolli järjekorda. Kui jääk sobib, tee esimene kõne."
      : "Kontrolli andmed üle enne müügikõnet."
};

console.log(JSON.stringify(result, null, 2));

if (result.priorityScore < 50) {
  process.exitCode = 1;
}
