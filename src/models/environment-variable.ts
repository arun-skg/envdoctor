import { inferType } from "../utils/type-infer.js";
import type { Origin } from "./origin.js";
import type { VariableType } from "./variable-type.js";

/**
 * A normalized view of one environment variable across every file in the
 * project. A single `EnvironmentVariable` aggregates every origin (definition,
 * reference, or usage) that mentions `name`.
 *
 * `value` is only ever set for definitions and is an implementation detail:
 * it is never rendered in CLI output and never written into generated files.
 */
export interface EnvironmentVariable {
  name: string;
  /** Raw value, present when at least one origin is a definition with a value. */
  value?: string;
  /** True when the name matches the secret heuristic. */
  isSecret: boolean;
  /** Inferred from `value` when available, else "unknown". */
  type: VariableType;
  /** Every place this name was observed. */
  origins: Origin[];
  /**
   * Rule ids that should be ignored for this variable, declared inline in the
   * env file via `# envdoctor:ignore <rule>` comments.
   */
  ignoreRules?: string[];
}

/**
 * True when the name matches the secret heuristic.
 *
 * `PASS` is matched only as a whole token (e.g. `DB_PASS`, `PASS`) rather than
 * as a substring, so names like `PASSPORT`, `COMPASS`, `BYPASS`, and
 * `PASSENGER` are not misreported as secrets. `PASSWORD`, `PASSWD`, and
 * `PASSPHRASE` remain covered explicitly. The pattern deliberately uses no
 * look-around so it ports verbatim to every native port's regex engine,
 * including Go (RE2) and Rust, which lack lookbehind.
 */
export const isSecretName = (name: string): boolean =>
  /(SECRET|TOKEN|PASSWORD|PASSWD|PASSPHRASE|(^|[^A-Za-z])PASS([^A-Za-z]|$)|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)/i.test(
    name,
  );

/** Build a normalized variable from a name, optional value, and origins. */
export function createVariable(
  name: string,
  value: string | undefined,
  origins: Origin[],
  ignoreRules?: string[],
): EnvironmentVariable {
  return {
    name,
    value,
    isSecret: isSecretName(name),
    type: inferType(value),
    origins,
    ignoreRules,
  };
}

/**
 * Merge multiple variables with the same name into one, preserving every
 * origin and preferring the first non-empty value. Used by parsers to flatten
 * repeated references into a single variable.
 */
export function mergeVariables(variables: EnvironmentVariable[]): EnvironmentVariable[] {
  const byName = new Map<string, EnvironmentVariable>();
  for (const v of variables) {
    const existing = byName.get(v.name);
    if (!existing) {
      byName.set(v.name, { ...v, origins: [...v.origins] });
      continue;
    }
    existing.origins.push(...v.origins);
    if (existing.value === undefined && v.value !== undefined) {
      existing.value = v.value;
      existing.type = inferType(v.value);
    }
  }
  return Array.from(byName.values());
}
