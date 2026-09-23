#!/usr/bin/env node
// Turn an envdoctor SARIF file into GitHub Actions annotations + a job summary.
// Annotations (::error / ::warning / ::notice workflow commands) show inline on
// the PR diff and in the run's Annotations panel — no code scanning / GHAS
// required, so this works on every repo. Never throws: a missing or invalid
// SARIF file yields zero findings and a clean exit.
import { readFileSync, appendFileSync } from "node:fs";

const sarifPath = process.argv[2];

/** @type {Array<{ruleId?:string, level?:string, message?:{text?:string}, locations?:any[]}>} */
let results = [];
try {
  const doc = JSON.parse(readFileSync(sarifPath, "utf8"));
  results = doc?.runs?.[0]?.results ?? [];
} catch {
  results = []; // missing/invalid SARIF (e.g. usage error) — nothing to annotate
}

const cmdFor = { error: "error", warning: "warning", note: "notice" };
let errors = 0;
let warnings = 0;
let notes = 0;

const esc = (s) =>
  String(s).replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
// Annotation *properties* additionally escape ':' and ','.
const escProp = (s) => esc(s).replace(/:/g, "%3A").replace(/,/g, "%2C");

for (const r of results) {
  const level = r.level ?? "warning";
  const cmd = cmdFor[level] ?? "warning";
  if (level === "error") errors++;
  else if (level === "note") notes++;
  else warnings++;

  const msg = r.message?.text ?? "envdoctor finding";
  const phys = r.locations?.[0]?.physicalLocation;
  const file = phys?.artifactLocation?.uri;
  const line = phys?.region?.startLine;

  const props = [];
  if (file) props.push(`file=${escProp(file)}`);
  if (line) props.push(`line=${line}`);
  if (r.ruleId) props.push(`title=${escProp(`envdoctor: ${r.ruleId}`)}`);
  console.log(`::${cmd} ${props.join(",")}::${esc(msg)}`);
}

// Outputs for downstream steps.
if (process.env.GITHUB_OUTPUT) {
  appendFileSync(
    process.env.GITHUB_OUTPUT,
    `error-count=${errors}\nwarning-count=${warnings}\nnote-count=${notes}\n`,
  );
}

// Job summary — the at-a-glance panel on the workflow run page.
if (process.env.GITHUB_STEP_SUMMARY) {
  const total = errors + warnings + notes;
  let md = `## envdoctor\n\n`;
  if (total === 0) {
    md += `✅ No environment variable issues found.\n`;
  } else {
    md += `| Severity | Count |\n| --- | ---: |\n`;
    md += `| ❌ Errors | ${errors} |\n| ⚠️ Warnings | ${warnings} |\n`;
    if (notes) md += `| ℹ️ Notes | ${notes} |\n`;
    md += `\nSee the **Annotations** section above for file locations.\n`;
  }
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, md);
}

console.log(
  `envdoctor: ${errors} error(s), ${warnings} warning(s)${notes ? `, ${notes} note(s)` : ""}.`,
);
