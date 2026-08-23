import fs from "node:fs";
import path from "node:path";
import { captureSnapshot } from "../runtime/snapshot.js";
import { encodeToken } from "../runtime/token.js";
import { EXIT_OK } from "../core/exit-codes.js";
import { rule, ui } from "../utils/logger.js";

export interface SnapshotOptions {
  rootDir: string;
  output?: string;
  token: boolean;
  json: boolean;
  globals: boolean;
}

/** `envdoctor snapshot` — capture this machine's live runtime. */
export async function runSnapshot(opts: SnapshotOptions): Promise<number> {
  const snapshot = await captureSnapshot({ globals: opts.globals });

  if (opts.output) {
    const dest = path.resolve(opts.rootDir, opts.output);
    fs.writeFileSync(dest, JSON.stringify(snapshot, null, 2) + "\n");
    process.stderr.write(`${ui.success("✓")} Snapshot written to ${ui.location(opts.output)}\n`);
  }

  if (opts.json) {
    process.stdout.write(JSON.stringify(snapshot, null, 2) + "\n");
    return EXIT_OK;
  }

  if (opts.token) {
    process.stdout.write(encodeToken(snapshot) + "\n");
    return EXIT_OK;
  }

  // Human summary.
  const title = "RUNTIME SNAPSHOT";
  process.stdout.write(ui.title(title) + "\n");
  process.stdout.write(`${rule(title.length * 2)}\n\n`);
  process.stdout.write(`  ${ui.bold("OS")}  ${snapshot.os.platform}/${snapshot.os.arch} ${ui.dim(snapshot.os.release)}\n\n`);

  process.stdout.write(`  ${ui.section("Tools")}\n`);
  if (snapshot.tools.length === 0) {
    process.stdout.write(`  ${ui.dim("none detected")}\n`);
  } else {
    for (const t of snapshot.tools) {
      process.stdout.write(`  ${ui.same()} ${ui.name(t.tool.padEnd(8))} ${t.version}  ${ui.dim(t.resolvedFrom)}\n`);
    }
  }

  process.stdout.write(`\n  ${ui.section(`PATH (${snapshot.path.length} entries)`)}\n`);
  snapshot.path.slice(0, 12).forEach((p, i) => {
    process.stdout.write(`  ${ui.dim(String(i + 1).padStart(2))}  ${p}\n`);
  });
  if (snapshot.path.length > 12) {
    process.stdout.write(`  ${ui.dim(`… ${snapshot.path.length - 12} more`)}\n`);
  }

  const ecosystems = Object.keys(snapshot.globals);
  if (ecosystems.length > 0) {
    process.stdout.write(`\n  ${ui.section("Globals")}\n`);
    for (const eco of ecosystems) {
      process.stdout.write(`  ${ui.dim(eco)}: ${(snapshot.globals[eco] ?? []).length} packages\n`);
    }
  } else if (!opts.globals) {
    process.stdout.write(`\n  ${ui.dim("Globals omitted — pass --globals to include the package inventory.")}\n`);
  }

  process.stdout.write(
    `\n  ${ui.dim(`Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>`)}\n`,
  );

  return EXIT_OK;
}
