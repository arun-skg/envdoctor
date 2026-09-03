import { Command, CommanderError } from "commander";
import pkg from "../package.json";
import { EXIT_USAGE } from "./core/exit-codes.js";
import { runDiff } from "./commands/diff.js";
import { runFix } from "./commands/fix.js";
import { runInit } from "./commands/init.js";
import { runScan } from "./commands/scan.js";
import { runSnapshot } from "./commands/snapshot.js";
import { runSnapshotDiff } from "./commands/snapshot-diff.js";
import { runSync } from "./commands/sync.js";
import { resolveRootDir } from "./commands/shared.js";
import { ui } from "./utils/logger.js";

const parseRules = (value: string): string[] =>
  value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

/**
 * envdoctor CLI. Each command is a thin wrapper around a `commands/*` module
 * that returns an exit code; errors are normalized to exit code 2.
 */
export async function main(argv: string[]): Promise<void> {
  const program = new Command();

  program
    .name("envdoctor")
    .description(
      "Local-first consistency checker for environment variables. " +
        "Detects missing, unused, duplicate, and mismatched variables across " +
        ".env files, docker-compose, GitHub Actions, and source code.",
    )
    .version(pkg.version, "-V, --version");

  program
    .command("init")
    .description("Bootstrap envdoctor: config, .env.example, and ENVIRONMENT.md.")
    .option("--force", "Overwrite existing generated files")
    .option("--dir <path>", "Project directory (default: current directory)")
    .action(async (opts) => {
      const rootDir = resolveRootDir(opts.dir);
      process.exitCode = await runInit({ rootDir, force: Boolean(opts.force) });
    });

  program
    .command("scan")
    .description("Scan the project for environment variable inconsistencies.")
    .option("-d, --dir <path>", "Project directory (default: current directory)")
    .option("--strict", "Treat warnings as failures")
    .option("--format <format>", "Output format: human, json, or sarif", "human")
    .option("--json", "Alias for --format json")
    .option("--only <rules>", "Comma-separated detector ids to run", parseRules, [])
    .option("-v, --verbose", "Show file:line locations in the report")
    .option("--baseline <path>", "Suppress findings matching a baseline file")
    .option("--write-baseline <path>", "Write current findings to a baseline file")
    .option("--staged", "Only scan files with staged git changes")
    .option("--since <ref>", "Only scan files changed since a git ref")
    .action(async (opts) => {
      const rootDir = resolveRootDir(opts.dir);
      const format = opts.json ? "json" : opts.format;
      if (!["human", "json", "sarif"].includes(format)) {
        process.stderr.write(ui.error(`error: unknown format "${format}"\n`));
        process.exitCode = EXIT_USAGE;
        return;
      }
      process.exitCode = await runScan({
        rootDir,
        strict: Boolean(opts.strict),
        format,
        verbose: Boolean(opts.verbose),
        only: opts.only,
        baseline: opts.baseline,
        writeBaseline: opts.writeBaseline,
        gitFilter: opts.staged ? { staged: true } : opts.since ? { since: opts.since } : undefined,
      });
    });

  program
    .command("fix")
    .description(
      "Generate safe artifacts: .env.example, ENVIRONMENT.md, and a GitHub Actions checklist.",
    )
    .option("--dir <path>", "Project directory (default: current directory)")
    .option("--dry-run", "Preview changes without writing anything")
    .option("--force", "Overwrite existing generated files")
    .option("-v, --verbose", "Show extra detail")
    .action(async (opts) => {
      const rootDir = resolveRootDir(opts.dir);
      process.exitCode = await runFix({
        rootDir,
        dryRun: Boolean(opts.dryRun),
        force: Boolean(opts.force),
        verbose: Boolean(opts.verbose),
      });
    });

  program
    .command("diff <environment1> <environment2>")
    .description("Compare environment variable sets across two environments.")
    .option("--dir <path>", "Project directory (default: current directory)")
    .option("--json", "Emit machine-readable JSON to stdout")
    .action(async (envA, envB, opts) => {
      const rootDir = resolveRootDir(opts.dir);
      process.exitCode = await runDiff({ rootDir, envA, envB, json: Boolean(opts.json) });
    });

  program
    .command("sync <from> <to>")
    .description("Copy missing variable keys from one environment file to another with placeholders.")
    .option("-d, --dir <path>", "Project directory (default: current directory)")
    .option("--dry-run", "Preview changes without writing")
    .action(async (envA, envB, opts) => {
      const rootDir = resolveRootDir(opts.dir);
      process.exitCode = await runSync({ rootDir, envA: envA, envB: envB, dryRun: Boolean(opts.dryRun) });
    });

  program
    .command("snapshot")
    .description(
      "Capture this machine's live runtime (tool versions, PATH order, globals) as a portable token.",
    )
    .option("-d, --dir <path>", "Project directory (default: current directory)")
    .option("-o, --output <file>", "Write the full snapshot JSON to a file")
    .option("--token", "Emit a compact base64 token to stdout")
    .option("--json", "Emit the full snapshot as JSON to stdout")
    .option("--globals", "Include the global package inventory (slower)")
    .action(async (opts) => {
      const rootDir = resolveRootDir(opts.dir);
      process.exitCode = await runSnapshot({
        rootDir,
        output: opts.output,
        token: Boolean(opts.token),
        json: Boolean(opts.json),
        globals: Boolean(opts.globals),
      });
    });

  program
    .command("snapshot-diff <a> <b>")
    .description("Compare two runtime snapshots (file paths or pasted tokens).")
    .option("-d, --dir <path>", "Project directory (default: current directory)")
    .option("--json", "Emit machine-readable JSON to stdout")
    .action(async (a, b, opts) => {
      const rootDir = resolveRootDir(opts.dir);
      process.exitCode = await runSnapshotDiff({ rootDir, a, b, json: Boolean(opts.json) });
    });

  program.exitOverride();

  try {
    await program.parseAsync(argv);
  } catch (err) {
    if (err instanceof CommanderError) {
      // Help/version output is already printed — not an error.
      if (err.exitCode === 0) return;
      process.exitCode = EXIT_USAGE;
      return;
    }
    process.stderr.write(
      `${ui.error(`error:`)} ${err instanceof Error ? err.message : String(err)}\n`,
    );
    process.exitCode = EXIT_USAGE;
  }
}

main(process.argv).catch(() => {
  process.exitCode = EXIT_USAGE;
});
