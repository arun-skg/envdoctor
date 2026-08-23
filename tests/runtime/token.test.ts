import { describe, expect, it } from "vitest";
import { decodeToken, encodeToken, parseSnapshotJson } from "../../src/runtime/token.js";
import { SNAPSHOT_SCHEMA, type RuntimeSnapshot } from "../../src/models/runtime-snapshot.js";

const sample = (): RuntimeSnapshot => ({
  schema: SNAPSHOT_SCHEMA,
  capturedAt: "2026-08-22T00:00:00.000Z",
  os: { platform: "darwin", arch: "arm64", release: "25.6.0" },
  tools: [{ tool: "node", version: "20.11.1", resolvedFrom: "~/.nvm/bin" }],
  path: ["~/.nvm/bin", "/usr/bin"],
  globals: {},
  envFlagNames: ["HOME", "LANG"],
});

describe("snapshot token", () => {
  it("round-trips through encode/decode", () => {
    const snap = sample();
    const restored = decodeToken(encodeToken(snap));
    expect(restored).toEqual(snap);
  });

  it("produces a single-line, prefixed token", () => {
    const token = encodeToken(sample());
    expect(token.startsWith("envd1:")).toBe(true);
    expect(token).not.toContain("\n");
  });

  it("rejects a non-token string", () => {
    expect(() => decodeToken("hello")).toThrow(/envd1: prefix/);
  });

  it("rejects a corrupt token", () => {
    expect(() => decodeToken("envd1:@@@notbase64@@@")).toThrow(/Corrupt|decode/i);
  });

  it("refuses a snapshot from a newer schema", () => {
    const future = { ...sample(), schema: SNAPSHOT_SCHEMA + 1 };
    expect(() => parseSnapshotJson(JSON.stringify(future))).toThrow(/newer than this envdoctor/);
  });

  it("rejects JSON that is not a snapshot", () => {
    expect(() => parseSnapshotJson('{"foo":1}')).toThrow(/Not a runtime snapshot/);
  });
});
