import { execFile } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { isSensitiveName } from "../utils/redact.js";
import type { GlobalPackage, ToolVersion } from "../models/runtime-snapshot.js";

const run = promisify(execFile);

/** First dotted version-looking token in a tool's output. */
const VERSION_RE = /(\d+\.\d+(?:\.\d+)?)/;

/** Collapse a leading $HOME to "~" so snapshots don't leak usernames and stay comparable. */
export function collapseHome(p: string): string {
  const home = os.homedir();
  if (home && (p === home || p.startsWith(home + path.sep))) {
    return "~" + p.slice(home.length);
  }
  return p;
}

/** Ordered, de-duplicated `$PATH` entries with $HOME collapsed. Order is significant. */
export function collectPath(pathEnv = process.env.PATH ?? ""): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of pathEnv.split(path.delimiter)) {
    if (!raw) continue;
    const entry = collapseHome(raw);
    if (seen.has(entry)) continue;
    seen.add(entry);
    out.push(entry);
  }
  return out;
}

/** Non-secret env var NAMES only. Secret-looking names are dropped, not masked. */
export function collectEnvFlagNames(env: NodeJS.ProcessEnv = process.env): string[] {
  return Object.keys(env)
    .filter((name) => !isSensitiveName(name))
    .sort();
}

/** Probe one CLI's version; returns null when the tool isn't installed or misbehaves. */
export async function probeVersion(tool: string, args: string[]): Promise<string | null> {
  try {
    const { stdout, stderr } = await run(tool, args, {
      timeout: 4000,
      windowsHide: true,
    });
    return (stdout + stderr).match(VERSION_RE)?.[1] ?? null;
  } catch {
    // ENOENT (not installed), nonzero exit, or timeout → treat as "not present".
    return null;
  }
}

/** Locate which PATH directory a command resolves from, $HOME collapsed. */
export async function resolveFrom(tool: string): Promise<string> {
  const finder = process.platform === "win32" ? "where" : "which";
  try {
    const { stdout } = await run(finder, [tool], { timeout: 4000, windowsHide: true });
    const first = stdout.split(/\r?\n/).find((l) => l.trim());
    return first ? collapseHome(path.dirname(first.trim())) : "";
  } catch {
    return "";
  }
}

/** Tools probed by default. Order here is the display order. */
export const TOOL_PROBES: ReadonlyArray<readonly [string, string[]]> = [
  ["node", ["-v"]],
  ["python3", ["--version"]],
  ["python", ["--version"]],
  ["go", ["version"]],
  ["rustc", ["-V"]],
  ["java", ["-version"]],
  ["ruby", ["-v"]],
  ["php", ["-v"]],
  ["perl", ["-v"]],
  ["cc", ["--version"]],
  ["git", ["--version"]],
];

/** Probe every known tool; only installed ones appear in the result. */
export async function collectTools(): Promise<ToolVersion[]> {
  const results = await Promise.all(
    TOOL_PROBES.map(async ([tool, args]) => {
      const version = await probeVersion(tool, args);
      if (version === null) return null;
      const resolvedFrom = await resolveFrom(tool);
      return { tool, version, resolvedFrom } satisfies ToolVersion;
    }),
  );
  return results
    .filter((r): r is ToolVersion => r !== null)
    .sort((a, b) => a.tool.localeCompare(b.tool));
}

/** Parse `npm ls -g --json` into a name/version list; tolerant of partial JSON. */
function parseNpmGlobals(stdout: string): GlobalPackage[] {
  try {
    const parsed = JSON.parse(stdout) as { dependencies?: Record<string, { version?: string }> };
    return Object.entries(parsed.dependencies ?? {})
      .map(([name, meta]) => ({ name, version: meta.version ?? "" }))
      .sort((a, b) => a.name.localeCompare(b.name));
  } catch {
    return [];
  }
}

/** Global package inventory, opt-in (`--globals`) because it is slow. Best-effort per ecosystem. */
export async function collectGlobals(): Promise<Record<string, GlobalPackage[]>> {
  const globals: Record<string, GlobalPackage[]> = {};

  try {
    const { stdout } = await run("npm", ["ls", "-g", "--depth=0", "--json"], {
      timeout: 15000,
      maxBuffer: 8 * 1024 * 1024,
      windowsHide: true,
    });
    const pkgs = parseNpmGlobals(stdout);
    if (pkgs.length > 0) globals.npm = pkgs;
  } catch {
    // npm absent or errored — skip this ecosystem silently.
  }

  return globals;
}
