import os from "node:os";
import { SNAPSHOT_SCHEMA, type RuntimeSnapshot } from "../models/runtime-snapshot.js";
import { collectEnvFlagNames, collectGlobals, collectPath, collectTools } from "./collectors.js";

export interface CaptureOptions {
  /** Include the (slow) global package inventory. */
  globals?: boolean;
}

/** Capture this machine's live runtime into a snapshot. Never records any value. */
export async function captureSnapshot(opts: CaptureOptions = {}): Promise<RuntimeSnapshot> {
  const [tools, globals] = await Promise.all([
    collectTools(),
    opts.globals ? collectGlobals() : Promise.resolve({}),
  ]);

  return {
    schema: SNAPSHOT_SCHEMA,
    capturedAt: new Date().toISOString(),
    os: { platform: process.platform, arch: process.arch, release: os.release() },
    tools,
    path: collectPath(),
    globals,
    envFlagNames: collectEnvFlagNames(),
  };
}
