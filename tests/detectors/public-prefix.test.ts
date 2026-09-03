import { describe, expect, it } from "vitest";
import { buildIndex } from "../../src/detectors/index.js";
import { publicPrefixDetector } from "../../src/detectors/public-prefix.js";
import { buildModel } from "../helpers.js";

describe("public-prefix detector", () => {
  it("flags secret-looking variables with public framework prefixes", () => {
    const model = buildModel([
      { path: "/p/.env", content: "NEXT_PUBLIC_API_KEY=abc\nVITE_JWT_SECRET=def\n" },
    ]);
    const findings = publicPrefixDetector.detect(buildIndex(model));
    expect(findings.map((f) => f.variable).sort()).toEqual([
      "NEXT_PUBLIC_API_KEY",
      "VITE_JWT_SECRET",
    ]);
    expect(findings.every((f) => f.severity === "error")).toBe(true);
  });

  it("does not flag non-secret public-prefixed variables", () => {
    const model = buildModel([
      { path: "/p/.env", content: "NEXT_PUBLIC_APP_URL=https://example.com\n" },
    ]);
    expect(publicPrefixDetector.detect(buildIndex(model))).toEqual([]);
  });

  it("does not flag secrets without public prefixes", () => {
    const model = buildModel([{ path: "/p/.env", content: "API_KEY=abc\n" }]);
    expect(publicPrefixDetector.detect(buildIndex(model))).toEqual([]);
  });

  describe("framework prefix coverage", () => {
    const cases: Array<[string, string]> = [
      ["SvelteKit", "PUBLIC_API_KEY"],
      ["Astro", "PUBLIC_SESSION_TOKEN"],
      ["Create React App", "REACT_APP_API_KEY"],
      ["Gatsby", "GATSBY_AUTH_TOKEN"],
      ["Nuxt", "NUXT_PUBLIC_API_SECRET"],
      ["Next.js", "NEXT_PUBLIC_API_KEY"],
      ["Vite", "VITE_JWT_SECRET"],
      ["Expo", "EXPO_PUBLIC_ACCESS_TOKEN"],
      ["Astro (ASTRO_PUBLIC_)", "ASTRO_PUBLIC_API_KEY"],
    ];

    it.each(cases)("flags a secret behind the %s prefix", (_framework, name) => {
      const model = buildModel([{ path: "/p/.env", content: `${name}=abc\n` }]);
      const findings = publicPrefixDetector.detect(buildIndex(model));
      expect(findings.map((f) => f.variable)).toEqual([name]);
      const [finding] = findings;
      expect(finding?.severity).toBe("error");
    });

    // The detector matches the first prefix in array order whose value the name
    // starts with; because `startsWith` is anchored, a shorter prefix like
    // `PUBLIC_` never shadows a `NUXT_`-prefixed name. (Prefixes must stay
    // ordered longest-first if any ever become a true leading substring of
    // another — see PUBLIC_PREFIXES in src/detectors/public-prefix.ts.)
    it("matches the anchored prefix and ignores unrelated ones", () => {
      const model = buildModel([
        { path: "/p/.env", content: "NUXT_PUBLIC_API_SECRET=abc\n" },
      ]);
      const [finding] = publicPrefixDetector.detect(buildIndex(model));
      expect(finding?.message).toContain('"NUXT_PUBLIC_"');
      expect(finding?.message).not.toContain('"PUBLIC_"; ');
    });

    it("does not flag non-secret names behind the same prefixes", () => {
      const model = buildModel([
        {
          path: "/p/.env",
          content: [
            "PUBLIC_APP_URL=https://example.com",
            "REACT_APP_TITLE=hello",
            "GATSBY_SITE_NAME=blog",
            "NUXT_PUBLIC_BASE_URL=https://example.com",
          ].join("\n"),
        },
      ]);
      expect(publicPrefixDetector.detect(buildIndex(model))).toEqual([]);
    });
  });

  it("ignores .env.example", () => {
    const model = buildModel([
      { path: "/p/.env.example", content: "NEXT_PUBLIC_API_KEY=\n" },
    ]);
    expect(publicPrefixDetector.detect(buildIndex(model))).toEqual([]);
  });
});
