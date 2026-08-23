#!/usr/bin/env node
// Consolidated downloads chart for envdoctor across ecosystems.
// Daily trend lines are drawn for the registries that expose a time-series
// (npm and PyPI); current totals are shown for those that expose only a count
// (RubyGems, Packagist). Maven Central and Go publish no download stats.
// Dependency-free — fetches public APIs and renders raw SVG.
// Usage: node scripts/downloads-chart.mjs [outfile]   (default: downloads.svg)

const NPM_PKG = "@arunskg/envdoctor";
const PYPI_PKG = "arun-envdoctor";
const GEM_PKG = "envdoctor";
const PACKAGIST_PKG = "arun-skg/envdoctor";
const DAYS = 90;
const OUT = process.argv[2] || "downloads.svg";

const W = 820;
const H = 300;
const PAD = { top: 30, right: 16, bottom: 64, left: 46 };

const iso = (d) => d.toISOString().slice(0, 10);

function niceMax(v) {
  if (v <= 0) return 1;
  const pow = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) if (v <= m * pow) return m * pow;
  return 10 * pow;
}

async function safeJson(url, opts) {
  try {
    const res = await fetch(url, opts);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

// Returns a Map<YYYY-MM-DD, downloads> for npm over the window.
async function npmSeries(days) {
  const end = new Date();
  const start = new Date(end.getTime() - (days - 1) * 86400000);
  const url = `https://api.npmjs.org/downloads/range/${iso(start)}:${iso(end)}/${NPM_PKG}`;
  const data = await safeJson(url);
  const m = new Map();
  if (data?.downloads) for (const d of data.downloads) m.set(d.day, d.downloads);
  return m;
}

// PyPI daily downloads via pypistats overall API (without mirrors).
async function pypiSeries() {
  const data = await safeJson(
    `https://pypistats.org/api/packages/${PYPI_PKG}/overall?mirrors=false`,
    { headers: { "User-Agent": "envdoctor-chart" } },
  );
  const m = new Map();
  if (data?.data) {
    for (const row of data.data) {
      if (row.category === "without_mirrors") m.set(row.date, row.downloads);
    }
  }
  return m;
}

async function gemTotal() {
  const d = await safeJson(`https://rubygems.org/api/v1/gems/${GEM_PKG}.json`);
  return typeof d?.downloads === "number" ? d.downloads : null;
}

async function packagistTotal() {
  const d = await safeJson(`https://packagist.org/packages/${PACKAGIST_PKG}.json`);
  return d?.package?.downloads?.total ?? null;
}

function seriesForDates(map, dates) {
  return dates.map((day) => map.get(day) ?? 0);
}

function polyline(values, dates, x, y) {
  return values
    .map((v, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`)
    .join(" ");
}

async function main() {
  const end = new Date();
  const dates = [];
  for (let i = DAYS - 1; i >= 0; i--) dates.push(iso(new Date(end.getTime() - i * 86400000)));

  const [npmMap, pypiMap, gem, pkgist] = await Promise.all([
    npmSeries(DAYS),
    pypiSeries(),
    gemTotal(),
    packagistTotal(),
  ]);

  const npm = seriesForDates(npmMap, dates);
  const pypi = seriesForDates(pypiMap, dates);
  const npmTotal = npm.reduce((a, b) => a + b, 0);
  const pypiTotal = pypi.reduce((a, b) => a + b, 0);
  const peak = Math.max(1, ...npm, ...pypi);
  const yMax = niceMax(peak);

  const plotW = W - PAD.left - PAD.right;
  const plotH = H - PAD.top - PAD.bottom;
  const x = (i) => PAD.left + (i / (dates.length - 1 || 1)) * plotW;
  const y = (n) => PAD.top + plotH - (n / yMax) * plotH;

  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => {
    const val = Math.round(yMax * f);
    return `<line x1="${PAD.left}" y1="${y(val).toFixed(1)}" x2="${(W - PAD.right).toFixed(1)}" y2="${y(val).toFixed(1)}" stroke="#8888" stroke-width="1" stroke-dasharray="2 3"/>` +
      `<text x="${PAD.left - 8}" y="${(y(val) + 4).toFixed(1)}" text-anchor="end" font-size="11" fill="#888">${val}</text>`;
  }).join("");

  const NPM = "#cb3837";
  const PY = "#3775a9";
  const npmPath = `<path d="${polyline(npm, dates, x, y)}" fill="none" stroke="${NPM}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;
  const pyPath = `<path d="${polyline(pypi, dates, x, y)}" fill="none" stroke="${PY}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;

  const xLabels =
    `<text x="${PAD.left}" y="${PAD.top + plotH + 16}" text-anchor="start" font-size="11" fill="#888">${dates[0]}</text>` +
    `<text x="${W - PAD.right}" y="${PAD.top + plotH + 16}" text-anchor="end" font-size="11" fill="#888">${dates[dates.length - 1]}</text>`;

  const fmt = (n) => (n == null ? "n/a" : n.toLocaleString());
  const legendY = PAD.top + plotH + 34;
  const legend =
    `<rect x="${PAD.left}" y="${legendY - 8}" width="12" height="3" fill="${NPM}"/>` +
    `<text x="${PAD.left + 18}" y="${legendY - 3}" font-size="11" fill="#666">npm (${fmt(npmTotal)}/90d)</text>` +
    `<rect x="${PAD.left + 150}" y="${legendY - 8}" width="12" height="3" fill="${PY}"/>` +
    `<text x="${PAD.left + 168}" y="${legendY - 3}" font-size="11" fill="#666">PyPI (${fmt(pypiTotal)}/90d)</text>`;

  const totalsY = legendY + 18;
  const totals =
    `<text x="${PAD.left}" y="${totalsY}" font-size="11" fill="#888">` +
    `Totals — RubyGems: ${fmt(gem)} · Packagist: ${fmt(pkgist)} · Maven Central &amp; Go: no public download stats</text>`;

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="Consolidated envdoctor downloads across ecosystems, last ${DAYS} days">
  <text x="${PAD.left}" y="18" font-size="13" font-weight="600" fill="#888">envdoctor downloads — daily trend (npm + PyPI), last ${DAYS} days</text>
  ${ticks}
  ${npmPath}
  ${pyPath}
  ${xLabels}
  ${legend}
  ${totals}
</svg>
`;

  const { writeFile } = await import("node:fs/promises");
  await writeFile(OUT, svg, "utf8");
  console.log(
    `Wrote ${OUT} — npm ${npmTotal}/90d, PyPI ${pypiTotal}/90d, gem ${gem}, packagist ${pkgist}`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
