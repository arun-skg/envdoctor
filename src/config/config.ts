import path from "node:path";
import fs from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { z } from "zod";

/**
 * envdoctor is configured through `envdoctor.config.ts|js|mjs|cjs` or a
 * `envdoctor` key in package.json. The config is optional — defaults are
 * sensible for most projects. Everything is validated with zod so a bad
 * config fails fast with a clear message instead of behaving mysteriously.
 */
export const envdoctorConfigSchema = z.object({
  /** Glob patterns (relative to the project root) for dotenv files. */
  envFilePatterns: z.array(z.string()).default([".env", ".env.*"]),
  /** Glob patterns for docker-compose files. */
  composeFilePatterns: z
    .array(z.string())
    .default(["**/docker-compose*.y*ml", "**/compose*.y*ml"]),
  /** Glob patterns for GitHub Actions workflows. */
  actionsFilePatterns: z
    .array(z.string())
    .default([".github/workflows/**/*.y*ml"]),
  /** Glob patterns for Kubernetes manifests. */
  k8sFilePatterns: z
    .array(z.string())
    .default([
      "**/*.{deployment,service,statefulset,daemonset,cronjob,job,configmap,secret,ingress,pvc}.y*ml",
      "**/k8s/**/*.y*ml",
      "**/kubernetes/**/*.y*ml",
      "**/manifests/**/*.y*ml",
      "**/deploy/**/*.y*ml",
    ]),
  /** File extensions scanned for source usage. */
  sourceExtensions: z
    .array(z.string())
    .default(["ts", "tsx", "js", "jsx", "mjs", "cjs"]),
  /** Glob patterns of variable names to never report (e.g. "AWS_*"). */
  ignoreVariables: z.array(z.string()).default([]),
  /** Glob patterns of files to skip. */
  ignoreFiles: z.array(z.string()).default([]),
  /**
   * Explicit environment label → file mapping. When provided it overrides the
   * default label derivation for dotenv files.
   */
  environments: z.record(z.string(), z.array(z.string())).optional(),
  /** Fail the audit when only warnings are present. */
  strict: z.boolean().default(false),
  /**
   * Override severity per detector. Use "off" to disable a detector entirely.
   * Example: `{ unused: "off", "environment-diff": "warn" }`
   */
  rules: z.record(z.string(), z.enum(["error", "warning", "off"])).default({}),
  /**
   * Per-variable validation schema. Values in env files are checked against
   * these rules.
   */
  schema: z
    .record(
      z.string(),
      z.object({
        type: z
          .enum(["string", "integer", "float", "boolean", "url", "json", "enum", "regex"])
          .optional(),
        optional: z.boolean().optional(),
        enum: z.array(z.string()).optional(),
        regex: z.string().optional(),
        min: z.number().optional(),
        max: z.number().optional(),
      }),
    )
    .default({}),
});

export type EnvdoctorConfig = z.infer<typeof envdoctorConfigSchema>;

export const DEFAULT_CONFIG: EnvdoctorConfig = envdoctorConfigSchema.parse({});

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

const CONFIG_BASENAMES = [
  "envdoctor.config.mjs",
  "envdoctor.config.cjs",
  "envdoctor.config.js",
  "envdoctor.config.ts",
];

/**
 * Locate a config file in the project root. Returns `null` when none exists.
 */
async function findConfigFile(rootDir: string): Promise<string | null> {
  for (const basename of CONFIG_BASENAMES) {
    const candidate = path.join(rootDir, basename);
    try {
      const stat = await fs.stat(candidate);
      if (stat.isFile()) return candidate;
    } catch {
      // not present, try the next candidate
    }
  }
  return null;
}

/** Load the `envdoctor` key from package.json when present. */
async function readPackageJsonConfig(rootDir: string): Promise<unknown> {
  try {
    const raw = await fs.readFile(path.join(rootDir, "package.json"), "utf8");
    const pkg = JSON.parse(raw) as { envdoctor?: unknown };
    return pkg.envdoctor;
  } catch {
    return undefined;
  }
}

/**
 * Load and validate the config for a project root. Falls back to defaults
 * when no config exists. Throws `ConfigError` when a config file is present
 * but invalid (syntax error, wrong shape, or unimportable).
 */
export async function loadConfig(rootDir: string): Promise<EnvdoctorConfig> {
  const configPath = await findConfigFile(rootDir);
  const pkgConfig = await readPackageJsonConfig(rootDir);

  if (!configPath && pkgConfig === undefined) return DEFAULT_CONFIG;

  let raw: unknown;
  if (configPath) {
    try {
      const mod = await import(pathToFileURL(configPath).href);
      raw = (mod.default ?? mod) ?? {};
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      throw new ConfigError(
        `Could not load config ${path.relative(rootDir, configPath)}: ${reason}. ` +
          "Use envdoctor.config.js/.mjs/.cjs (or package.json#envdoctor).",
      );
    }
  } else {
    raw = pkgConfig;
  }

  const parsed = envdoctorConfigSchema.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((issue) => `${issue.path.join(".") || "config"}: ${issue.message}`)
      .join("; ");
    throw new ConfigError(`Invalid envdoctor config: ${issues}`);
  }
  return parsed.data;
}
