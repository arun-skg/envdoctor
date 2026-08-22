#!/usr/bin/env node
// Generates an SVG area chart of daily npm downloads for the package.
// No dependencies — fetches the public npm downloads API and renders raw SVG.
// Usage: node scripts/downloads-chart.mjs [outfile]  (default: downloads.svg)

const PKG = "@arunskg/envdoctor";
const DAYS = 90;
const OUT = process.argv[2] || "downloads.svg";

const W = 800;
const H = 240;
const PAD = { top: 24, right: 16, bottom: 28, left: 44 };

function niceMax(v) {
  if (v <= 0) return 1;
  const pow = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) {
    if (v <= m * pow) return m * pow;
  }
  return 10 * pow;
}

async function main() {
  // npm range API accepts explicit YYYY-MM-DD:YYYY-MM-DD windows.
  const end = new Date();
  const start = new Date(end.getTime() - (DAYS - 1) * 86400000);
  const iso = (d) => d.toISOString().slice(0, 10);
  const url = `https://api.npmjs.org/downloads/range/${iso(start)}:${iso(end)}/${PKG}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`npm API ${res.status}: ${await res.text()}`);
  const { downloads } = await res.json();

  const pts = downloads.map((d) => ({ day: d.day, n: d.downloads }));
  const total = pts.reduce((a, p) => a + p.n, 0);
  const peak = pts.reduce((a, p) => Math.max(a, p.n), 0);
  const yMax = niceMax(peak);

  const plotW = W - PAD.left - PAD.right;
  const plotH = H - PAD.top - PAD.bottom;
  const x = (i) => PAD.left + (i / (pts.length - 1 || 1)) * plotW;
  const y = (n) => PAD.top + plotH - (n / yMax) * plotH;

  const line = pts.map((p, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(p.n).toFixed(1)}`).join(" ");
  const area = `${line} L${x(pts.length - 1).toFixed(1)},${(PAD.top + plotH).toFixed(1)} L${x(0).toFixed(1)},${(PAD.top + plotH).toFixed(1)} Z`;

  // y gridlines / labels
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => {
    const val = Math.round(yMax * f);
    return { val, yy: y(val) };
  });
  const grid = ticks
    .map(
      (t) =>
        `<line x1="${PAD.left}" y1="${t.yy.toFixed(1)}" x2="${(W - PAD.right).toFixed(1)}" y2="${t.yy.toFixed(1)}" stroke="#8888" stroke-width="1" stroke-dasharray="2 3"/>` +
        `<text x="${PAD.left - 8}" y="${(t.yy + 4).toFixed(1)}" text-anchor="end" font-size="11" fill="#888">${t.val}</text>`
    )
    .join("");

  // x labels: first and last day
  const firstDay = pts[0]?.day ?? "";
  const lastDay = pts[pts.length - 1]?.day ?? "";
  const xLabels =
    `<text x="${PAD.left}" y="${H - 8}" text-anchor="start" font-size="11" fill="#888">${firstDay}</text>` +
    `<text x="${W - PAD.right}" y="${H - 8}" text-anchor="end" font-size="11" fill="#888">${lastDay}</text>`;

  const accent = "#8957e5"; // npm-ish purple, readable on light & dark
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="npm daily downloads for ${PKG}, last ${DAYS} days">
  <defs>
    <linearGradient id="fill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="${accent}" stop-opacity="0.35"/>
      <stop offset="100%" stop-color="${accent}" stop-opacity="0.02"/>
    </linearGradient>
  </defs>
  <text x="${PAD.left}" y="16" font-size="13" font-weight="600" fill="#888">npm downloads — last ${DAYS} days (${total.toLocaleString()} total, peak ${peak})</text>
  ${grid}
  <path d="${area}" fill="url(#fill)"/>
  <path d="${line}" fill="none" stroke="${accent}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
  ${xLabels}
</svg>
`;

  const { writeFile } = await import("node:fs/promises");
  await writeFile(OUT, svg, "utf8");
  console.log(`Wrote ${OUT} (${pts.length} days, total ${total}, peak ${peak})`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
