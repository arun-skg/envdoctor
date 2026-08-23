import { gzipSync, gunzipSync } from "node:zlib";
import { SNAPSHOT_SCHEMA, type RuntimeSnapshot } from "../models/runtime-snapshot.js";

/**
 * Portable snapshot token: base64url(gzip(json)). Compact enough to paste into
 * an issue or chat, self-contained, and schema-versioned so a decoder can
 * refuse a token from a newer envdoctor instead of mis-diffing it.
 */

const PREFIX = "envd1:";

/** Encode a snapshot into a single-line, paste-safe token. */
export function encodeToken(snapshot: RuntimeSnapshot): string {
  const json = Buffer.from(JSON.stringify(snapshot), "utf8");
  return PREFIX + gzipSync(json).toString("base64url");
}

/** Decode a token back into a snapshot. Throws a clear error on malformed or too-new input. */
export function decodeToken(token: string): RuntimeSnapshot {
  const trimmed = token.trim();
  if (!trimmed.startsWith(PREFIX)) {
    throw new Error("Not an envdoctor snapshot token (missing envd1: prefix).");
  }
  let snapshot: RuntimeSnapshot;
  try {
    const buf = Buffer.from(trimmed.slice(PREFIX.length), "base64url");
    snapshot = JSON.parse(gunzipSync(buf).toString("utf8")) as RuntimeSnapshot;
  } catch {
    throw new Error("Corrupt snapshot token: could not decode.");
  }
  assertReadable(snapshot);
  return snapshot;
}

/** Parse raw JSON (from a `--output` file) into a validated snapshot. */
export function parseSnapshotJson(text: string): RuntimeSnapshot {
  let snapshot: RuntimeSnapshot;
  try {
    snapshot = JSON.parse(text) as RuntimeSnapshot;
  } catch {
    throw new Error("Invalid snapshot JSON.");
  }
  assertReadable(snapshot);
  return snapshot;
}

function assertReadable(snapshot: RuntimeSnapshot): void {
  if (typeof snapshot?.schema !== "number" || !Array.isArray(snapshot?.tools)) {
    throw new Error("Not a runtime snapshot.");
  }
  if (snapshot.schema > SNAPSHOT_SCHEMA) {
    throw new Error(
      `Snapshot schema v${snapshot.schema} is newer than this envdoctor (v${SNAPSHOT_SCHEMA}). Upgrade to compare it.`,
    );
  }
}
