import { describe, expect, it } from "vitest";
import { compareSnapshots } from "../../src/runtime/compare.js";
import { SNAPSHOT_SCHEMA, type RuntimeSnapshot } from "../../src/models/runtime-snapshot.js";

const base = (over: Partial<RuntimeSnapshot> = {}): RuntimeSnapshot => ({
  schema: SNAPSHOT_SCHEMA,
  capturedAt: "2026-08-22T00:00:00.000Z",
  os: { platform: "darwin", arch: "arm64", release: "25.6.0" },
  tools: [{ tool: "node", version: "20.11.1", resolvedFrom: "~/.nvm/bin" }],
  path: ["~/.nvm/bin", "/usr/bin"],
  globals: {},
  envFlagNames: [],
  ...over,
});

describe("compareSnapshots", () => {
  it("reports equivalent runtimes (ignoring capturedAt)", () => {
    const diff = compareSnapshots(base(), base({ capturedAt: "2020-01-01T00:00:00Z" }));
    expect(diff.equivalent).toBe(true);
    expect(diff.tools.every((t) => t.status === "same")).toBe(true);
  });

  it("flags a tool version mismatch", () => {
    const b = base({ tools: [{ tool: "node", version: "18.0.0", resolvedFrom: "~/.nvm/bin" }] });
    const diff = compareSnapshots(base(), b);
    expect(diff.equivalent).toBe(false);
    const node = diff.tools.find((t) => t.name === "node")!;
    expect(node.status).toBe("different");
    expect(node.a).toBe("20.11.1");
    expect(node.b).toBe("18.0.0");
  });

  it("flags a tool present only on one side", () => {
    const b = base({
      tools: [
        { tool: "node", version: "20.11.1", resolvedFrom: "~/.nvm/bin" },
        { tool: "go", version: "1.22.0", resolvedFrom: "/usr/local/go/bin" },
      ],
    });
    const diff = compareSnapshots(base(), b);
    const go = diff.tools.find((t) => t.name === "go")!;
    expect(go.status).toBe("onlyB");
    expect(diff.equivalent).toBe(false);
  });

  it("detects PATH reordering with the same entries", () => {
    const b = base({ path: ["/usr/bin", "~/.nvm/bin"] });
    const diff = compareSnapshots(base(), b);
    expect(diff.pathReordered).toBe(true);
    expect(diff.pathOnlyA).toEqual([]);
    expect(diff.pathOnlyB).toEqual([]);
    expect(diff.equivalent).toBe(false);
  });

  it("detects PATH entries unique to each side", () => {
    const diff = compareSnapshots(base({ path: ["/a", "/b"] }), base({ path: ["/b", "/c"] }));
    expect(diff.pathOnlyA).toEqual(["/a"]);
    expect(diff.pathOnlyB).toEqual(["/c"]);
  });

  it("diffs global packages when present", () => {
    const a = base({ globals: { npm: [{ name: "typescript", version: "5.4.0" }] } });
    const b = base({ globals: { npm: [{ name: "typescript", version: "5.5.0" }] } });
    const diff = compareSnapshots(a, b);
    expect(diff.globals).toHaveLength(1);
    expect(diff.globals[0]).toMatchObject({ name: "typescript", status: "different" });
  });

  it("does not let env flag name differences fail equivalence", () => {
    const diff = compareSnapshots(base({ envFlagNames: ["A"] }), base({ envFlagNames: ["B"] }));
    expect(diff.envFlagOnlyA).toEqual(["A"]);
    expect(diff.envFlagOnlyB).toEqual(["B"]);
    expect(diff.equivalent).toBe(true);
  });
});
