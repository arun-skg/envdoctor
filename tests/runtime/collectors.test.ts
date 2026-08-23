import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { collapseHome, collectEnvFlagNames, collectPath } from "../../src/runtime/collectors.js";

describe("collectors (pure helpers)", () => {
  it("collapses $HOME to ~", () => {
    const home = os.homedir();
    expect(collapseHome(path.join(home, "bin"))).toBe("~" + path.sep + "bin");
    expect(collapseHome("/usr/bin")).toBe("/usr/bin");
  });

  it("splits PATH, preserves order, de-duplicates", () => {
    const d = path.delimiter;
    const result = collectPath(["/a", "/b", "/a", ""].join(d));
    expect(result).toEqual(["/a", "/b"]);
  });

  it("keeps only non-secret env var names", () => {
    const names = collectEnvFlagNames({
      HOME: "/home/x",
      API_KEY: "sk-123",
      DB_PASSWORD: "hunter2",
      LANG: "en_US",
    });
    expect(names).toContain("HOME");
    expect(names).toContain("LANG");
    expect(names).not.toContain("API_KEY");
    expect(names).not.toContain("DB_PASSWORD");
  });

  it("returns env names sorted", () => {
    const names = collectEnvFlagNames({ ZED: "1", ALPHA: "1" });
    expect(names).toEqual(["ALPHA", "ZED"]);
  });
});
