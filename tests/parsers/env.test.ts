import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { envParser, environmentLabelForDotenv, parseDotenv } from "../../src/parsers/env.js";
import { fixturePath } from "../helpers.js";

describe("environmentLabelForDotenv", () => {
  it.each([
    [".env", "development"],
    [".env.example", "example"],
    [".env.production", "production"],
    [".env.development.local", "development"],
    [".env.local", "local"],
    [".env.test", "test"],
  ])("%s → %s", (name, expected) => {
    expect(environmentLabelForDotenv(name)).toBe(expected);
  });
});

describe("parseDotenv", () => {
  it("parses the fixture with correct values and line numbers", () => {
    const content = fs.readFileSync(
      path.join(fixturePath("parsers"), "env-file.env"),
      "utf8",
    );
    const entries = parseDotenv(content);

    const byKey = new Map<string, typeof entries>();
    for (const e of entries) {
      byKey.set(e.key, [...(byKey.get(e.key) ?? []), e]);
    }

    expect(byKey.get("NODE_ENV")?.[0]?.value).toBe("production");
    expect(byKey.get("NODE_ENV")?.[0]?.line).toBe(2); // export prefix handled
    expect(byKey.get("TABBED_EXPORT")?.[0]?.value).toBe("enabled");
    expect(byKey.get("PLAIN")?.[0]?.value).toBe("value");
    expect(byKey.get("QUOTED")?.[0]?.value).toBe("double quoted");
    expect(byKey.get("SINGLE")?.[0]?.value).toBe("single quoted");
    expect(byKey.get("WITH_COMMENT")?.[0]?.value).toBe("value");
    expect(byKey.get("ESCAPED_HASH")?.[0]?.value).toBe("value#kept");
    expect(byKey.get("MULTILINE")?.[0]?.value).toBe("line one\nline two");
    expect(byKey.get("UNQUOTED_NUMBER")?.[0]?.value).toBe("42");
    expect(byKey.get("EMPTY")?.[0]?.value).toBe("");
  });

  it("accepts export prefixes with whitespace variants", () => {
    const entries = parseDotenv("export\tTABBED=one\n  export   SPACED=two\n");

    expect(entries.map((entry) => [entry.key, entry.value])).toEqual([
      ["TABBED", "one"],
      ["SPACED", "two"],
    ]);
  });

  it("parses export assignments identically to plain assignments", () => {
    const exported = parseDotenv("export \t API_URL=https://example.com\n");
    const plain = parseDotenv("API_URL=https://example.com\n");

    expect(exported).toEqual(plain);
  });

  it("does not treat variable names beginning with export as prefixes", () => {
    expect(parseDotenv("exported=value\n")).toEqual([
      { key: "exported", value: "value", line: 1 },
    ]);
  });

  it("keeps duplicate keys so the duplicates detector can see them", () => {
    const entries = parseDotenv("DUPLICATE=first\nDUPLICATE=second\n");
    expect(entries).toHaveLength(2);
    expect(entries.map((e) => e.value)).toEqual(["first", "second"]);
  });

  it("skips lines without an equals sign", () => {
    const entries = parseDotenv("NOT_A_KEY\nKEY=value\n");
    expect(entries).toHaveLength(1);
    expect(entries[0]?.key).toBe("KEY");
  });

  it("strips inline comments only when unescaped", () => {
    expect(parseDotenv("A=hello # world\n").map((e) => e.value)).toEqual(["hello"]);
    expect(parseDotenv('B="hello # world"\n').map((e) => e.value)).toEqual(["hello # world"]);
    expect(parseDotenv("C=hello\\#world\n").map((e) => e.value)).toEqual(["hello#world"]);
  });

  it("handles double-quoted escape sequences", () => {
    expect(parseDotenv('A="line1\\nline2"\n').map((e) => e.value)).toEqual(["line1\nline2"]);
    expect(parseDotenv('A="tab\\there"\n').map((e) => e.value)).toEqual(["tab\there"]);
  });
});

describe("envParser", () => {
  it("produces definitions with origins and inferred types", () => {
    const file = envParser.parse("PORT=3000\nDEBUG=true\nURL=https://x.dev\n", "/proj/.env");
    expect(file.format).toBe("dotenv");
    expect(file.environment).toBe("development");

    const byName = new Map(file.variables.map((v) => [v.name, v]));
    expect(byName.get("PORT")?.type).toBe("integer");
    expect(byName.get("DEBUG")?.type).toBe("boolean");
    expect(byName.get("URL")?.type).toBe("url");
    expect(byName.get("PORT")?.origins[0]?.line).toBe(1);
    expect(byName.get("PORT")?.origins[0]?.kind).toBe("definition");
  });

  it("flags secret-like names", () => {
    const file = envParser.parse("API_KEY=abc\nDATABASE_URL=postgres://x\n", "/proj/.env");
    const byName = new Map(file.variables.map((v) => [v.name, v]));
    expect(byName.get("API_KEY")?.isSecret).toBe(true);
    expect(byName.get("DATABASE_URL")?.isSecret).toBe(false);
  });

  it("captures inline ignore directives on the preceding line", () => {
    const file = envParser.parse(
      "# envdoctor:ignore unused\nDEBUG_MODE=true\n# envdoctor:ignore unused, weak-secret\nAPI_KEY=short\n",
      "/proj/.env",
    );
    const byName = new Map(file.variables.map((v) => [v.name, v]));
    expect(byName.get("DEBUG_MODE")?.ignoreRules).toEqual(["unused"]);
    expect(byName.get("API_KEY")?.ignoreRules).toEqual(["unused", "weak-secret"]);
  });
});
