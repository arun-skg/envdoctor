import fs from "node:fs";
import path from "node:path";
import { compareSnapshots, type RuntimeDiff } from "../runtime/compare.js";
import { decodeToken, parseSnapshotJson } from "../runtime/token.js";
import type { RuntimeSnapshot } from "../models/runtime-snapshot.js";
import { EXIT_ISSUES, EXIT_OK, EXIT_USAGE } from "../core/exit-codes.js";
import { rule, ui } from "../utils/logger.js";

export interface SnapshotDiffOptions {
  rootDir: string;
  a: string;
  b: string;
  json: boolean;
}

/** Resolve a positional arg that may be a token string or a file path. */
function loadSnapshot(rootDir: string, arg: string): RuntimeSnapshot {
  if (arg.trim().startsWith("envd1:")) {
    return decodeToken(arg);
  }
  const file = path.resolve(rootDir, arg);
  if (!fs.existsSync(file)) {
    throw new Error(`Not a snapshot token, and file not found: ${arg}`);
  }
  return parseSnapshotJson(fs.readFileSync(file, "utf8"));
}

/** `envdoctor snapshot-diff <a> <b>` — compare two runtime snapshots. */
export async function runSnapshotDiff(opts: SnapshotDiffOptions): Promise<number> {
  let a: RuntimeSnapshot;
  let b: RuntimeSnapshot;
  try {
    a = loadSnapshot(opts.rootDir, opts.a);
    b = loadSnapshot(opts.rootDir, opts.b);
  } catch (err) {
    process.stderr.write(`${ui.error("error")} ${err instanceof Error ? err.message : String(err)}\n`);
    return EXIT_USAGE;
  }

  const diff = compareSnapshots(a, b);

  if (opts.json) {
    process.stdout.write(
      JSON.stringify({ exitCode: diff.equivalent ? 0 : 1, ...diff }, null, 2) + "\n",
    );
    return diff.equivalent ? EXIT_OK : EXIT_ISSUES;
  }

  renderHuman(diff);
  return diff.equivalent ? EXIT_OK : EXIT_ISSUES;
}

function renderHuman(diff: RuntimeDiff): void {
  const title = "RUNTIME DIFF";
  process.stdout.write(ui.title(title) + "\n");
  process.stdout.write(`${rule(title.length * 2)}\n\n`);
  process.stdout.write(`  ${ui.bold("A → B")}\n\n`);

  if (diff.os.status === "same") {
    process.stdout.write(`  ${ui.same()} OS  ${ui.dim(diff.os.a)}\n\n`);
  } else {
    process.stdout.write(`  ${ui.different()} OS  ${diff.os.a} ${ui.dim("→")} ${diff.os.b}\n\n`);
  }

  process.stdout.write(`  ${ui.section("Tools")}\n`);
  for (const t of diff.tools) {
    if (t.status === "same") {
      process.stdout.write(`  ${ui.same()} ${ui.name(t.name.padEnd(8))} ${ui.dim(t.a ?? "")}\n`);
    } else if (t.status === "different") {
      process.stdout.write(`  ${ui.different()} ${ui.name(t.name.padEnd(8))} ${t.a} ${ui.dim("→")} ${t.b}\n`);
    } else if (t.status === "onlyA") {
      process.stdout.write(`  ${ui.missing()} ${ui.name(t.name.padEnd(8))} ${ui.error("missing in B")} ${ui.dim(`(A: ${t.a})`)}\n`);
    } else {
      process.stdout.write(`  ${ui.missing()} ${ui.name(t.name.padEnd(8))} ${ui.error("missing in A")} ${ui.dim(`(B: ${t.b})`)}\n`);
    }
  }

  if (diff.pathReordered || diff.pathOnlyA.length || diff.pathOnlyB.length) {
    process.stdout.write(`\n  ${ui.section("PATH")}\n`);
    if (diff.pathReordered) {
      process.stdout.write(`  ${ui.different()} same entries, different order\n`);
    }
    for (const p of diff.pathOnlyA) process.stdout.write(`  ${ui.missing()} ${ui.dim("only in A:")} ${p}\n`);
    for (const p of diff.pathOnlyB) process.stdout.write(`  ${ui.missing()} ${ui.dim("only in B:")} ${p}\n`);
  }

  if (diff.globals.length) {
    process.stdout.write(`\n  ${ui.section("Globals")}\n`);
    for (const g of diff.globals) {
      const label = `${g.ecosystem}:${g.name}`;
      if (g.status === "different") {
        process.stdout.write(`  ${ui.different()} ${label}  ${g.a} ${ui.dim("→")} ${g.b}\n`);
      } else if (g.status === "onlyA") {
        process.stdout.write(`  ${ui.missing()} ${label}  ${ui.error("missing in B")}\n`);
      } else {
        process.stdout.write(`  ${ui.missing()} ${label}  ${ui.error("missing in A")}\n`);
      }
    }
  }

  const status = diff.equivalent
    ? ui.success("✓ runtimes are equivalent")
    : ui.error("✗ runtime drift detected");
  process.stdout.write(`\n  ${status}\n`);
}
