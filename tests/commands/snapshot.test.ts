import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { runSnapshot } from "../../src/commands/snapshot.js";
import { runSnapshotDiff } from "../../src/commands/snapshot-diff.js";
import { EXIT_ISSUES, EXIT_OK, EXIT_USAGE } from "../../src/core/exit-codes.js";
import { decodeToken } from "../../src/runtime/token.js";
import { capture } from "../helpers.js";

describe("envdoctor snapshot", () => {
  let tmpDir: string;

  beforeAll(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "envd-snap-"));
  });

  afterAll(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("prints a human summary with OS and PATH", async () => {
    const result = await capture(() =>
      runSnapshot({ rootDir: tmpDir, token: false, json: false, globals: false }),
    );
    expect(result.code).toBe(EXIT_OK);
    expect(result.stdout).toContain("RUNTIME SNAPSHOT");
    expect(result.stdout).toContain("PATH");
  });

  it("emits a decodable token", async () => {
    const result = await capture(() =>
      runSnapshot({ rootDir: tmpDir, token: true, json: false, globals: false }),
    );
    expect(result.code).toBe(EXIT_OK);
    const token = result.stdout.trim();
    const snap = decodeToken(token);
    expect(snap.os.platform).toBe(process.platform);
  });

  it("never captures secret values — only non-secret names", async () => {
    process.env.ENVD_TEST_SECRET_TOKEN = "should-not-leak";
    try {
      const result = await capture(() =>
        runSnapshot({ rootDir: tmpDir, token: false, json: true, globals: false }),
      );
      expect(result.stdout).not.toContain("should-not-leak");
      const snap = JSON.parse(result.stdout);
      expect(snap.envFlagNames).not.toContain("ENVD_TEST_SECRET_TOKEN");
    } finally {
      delete process.env.ENVD_TEST_SECRET_TOKEN;
    }
  });

  it("writes JSON to --output", async () => {
    const out = "snap.json";
    const result = await capture(() =>
      runSnapshot({ rootDir: tmpDir, output: out, token: false, json: false, globals: false }),
    );
    expect(result.code).toBe(EXIT_OK);
    expect(fs.existsSync(path.join(tmpDir, out))).toBe(true);
  });
});

describe("envdoctor snapshot-diff", () => {
  let tmpDir: string;

  beforeAll(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "envd-diff-"));
  });

  afterAll(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const snap = (over: object) =>
    JSON.stringify({
      schema: 1,
      capturedAt: "2026-08-22T00:00:00Z",
      os: { platform: "linux", arch: "x64", release: "6.0" },
      tools: [{ tool: "node", version: "20.0.0", resolvedFrom: "/usr/bin" }],
      path: ["/usr/bin"],
      globals: {},
      envFlagNames: [],
      ...over,
    });

  it("exits 0 for equivalent snapshots", async () => {
    const a = path.join(tmpDir, "a.json");
    const b = path.join(tmpDir, "b.json");
    fs.writeFileSync(a, snap({}));
    fs.writeFileSync(b, snap({ capturedAt: "2020-01-01T00:00:00Z" }));
    const result = await capture(() => runSnapshotDiff({ rootDir: tmpDir, a, b, json: false }));
    expect(result.code).toBe(EXIT_OK);
    expect(result.stdout).toContain("equivalent");
  });

  it("exits 1 and shows drift on a version mismatch", async () => {
    const a = path.join(tmpDir, "a2.json");
    const b = path.join(tmpDir, "b2.json");
    fs.writeFileSync(a, snap({}));
    fs.writeFileSync(b, snap({ tools: [{ tool: "node", version: "18.0.0", resolvedFrom: "/usr/bin" }] }));
    const result = await capture(() => runSnapshotDiff({ rootDir: tmpDir, a, b, json: false }));
    expect(result.code).toBe(EXIT_ISSUES);
    expect(result.stdout).toContain("drift");
  });

  it("returns a usage error for a missing file", async () => {
    const result = await capture(() =>
      runSnapshotDiff({ rootDir: tmpDir, a: "nope.json", b: "also-nope.json", json: false }),
    );
    expect(result.code).toBe(EXIT_USAGE);
  });
});
