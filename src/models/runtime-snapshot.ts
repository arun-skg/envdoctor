/**
 * Runtime snapshot model.
 *
 * A snapshot captures the *live* shell runtime of one machine — installed tool
 * versions, `$PATH` resolution order, optional global packages, and the OS —
 * so two machines can be diffed to explain "builds on my laptop, fails on the
 * server". It is a different data source from the static file model the rest of
 * envdoctor works on, and lives beside the pipeline rather than inside it.
 *
 * The envdoctor invariant still holds: **values are never captured.** Only
 * variable *names* are recorded in `envFlagNames`, and names that look secret
 * are dropped entirely.
 */

/** Bumped whenever the snapshot shape changes; `snapshot-diff` refuses tokens it can't read. */
export const SNAPSHOT_SCHEMA = 1;

export interface ToolVersion {
  /** Probe id, e.g. "node". */
  tool: string;
  /** Normalized version string (digits and dots), e.g. "20.11.1". */
  version: string;
  /** PATH directory the tool resolved from, with $HOME collapsed to "~". */
  resolvedFrom: string;
}

export interface GlobalPackage {
  name: string;
  version: string;
}

export interface RuntimeSnapshot {
  schema: number;
  /** Informational only — never diffed. */
  capturedAt: string;
  os: { platform: string; arch: string; release: string };
  /** Present tools only, sorted by tool id. */
  tools: ToolVersion[];
  /** Ordered `$PATH` entries, $HOME collapsed to "~". Order is significant. */
  path: string[];
  /** Ecosystem id ("npm", "pip", …) → package inventory. Empty unless --globals. */
  globals: Record<string, GlobalPackage[]>;
  /** Non-secret env var NAMES only. Never any values. */
  envFlagNames: string[];
}
