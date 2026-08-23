import type { GlobalPackage, RuntimeSnapshot } from "../models/runtime-snapshot.js";

/** How an item relates across two snapshots. */
export type RuntimeStatus = "same" | "different" | "onlyA" | "onlyB";

export interface ToolDiff {
  name: string;
  status: RuntimeStatus;
  a?: string;
  b?: string;
}

export interface GlobalDiff {
  ecosystem: string;
  name: string;
  status: RuntimeStatus;
  a?: string;
  b?: string;
}

export interface RuntimeDiff {
  os: { status: RuntimeStatus; a: string; b: string };
  tools: ToolDiff[];
  /** True when both share the same PATH entries but in a different order. */
  pathReordered: boolean;
  pathOnlyA: string[];
  pathOnlyB: string[];
  globals: GlobalDiff[];
  envFlagOnlyA: string[];
  envFlagOnlyB: string[];
  /** True when nothing meaningful differs (drift-free). */
  equivalent: boolean;
}

function statusFor<T>(a: T | undefined, b: T | undefined, eq: (x: T, y: T) => boolean): RuntimeStatus {
  if (a !== undefined && b !== undefined) return eq(a, b) ? "same" : "different";
  return a !== undefined ? "onlyA" : "onlyB";
}

function diffTools(a: RuntimeSnapshot, b: RuntimeSnapshot): ToolDiff[] {
  const names = new Set([...a.tools.map((t) => t.tool), ...b.tools.map((t) => t.tool)]);
  const av = new Map(a.tools.map((t) => [t.tool, t.version]));
  const bv = new Map(b.tools.map((t) => [t.tool, t.version]));
  return [...names]
    .sort()
    .map((name) => ({
      name,
      status: statusFor(av.get(name), bv.get(name), (x, y) => x === y),
      a: av.get(name),
      b: bv.get(name),
    }));
}

function diffGlobals(a: RuntimeSnapshot, b: RuntimeSnapshot): GlobalDiff[] {
  const ecosystems = new Set([...Object.keys(a.globals), ...Object.keys(b.globals)]);
  const out: GlobalDiff[] = [];
  for (const eco of [...ecosystems].sort()) {
    const index = (list: GlobalPackage[] = []) => new Map(list.map((p) => [p.name, p.version]));
    const av = index(a.globals[eco]);
    const bv = index(b.globals[eco]);
    for (const name of new Set([...av.keys(), ...bv.keys()])) {
      const status = statusFor(av.get(name), bv.get(name), (x, y) => x === y);
      if (status === "same") continue;
      out.push({ ecosystem: eco, name, status, a: av.get(name), b: bv.get(name) });
    }
  }
  return out.sort((x, y) => x.name.localeCompare(y.name));
}

/** Set difference preserving A's order. */
const onlyIn = (a: string[], b: string[]): string[] => {
  const set = new Set(b);
  return a.filter((x) => !set.has(x));
};

/** Pure comparison of two runtime snapshots. `capturedAt` is ignored. */
export function compareSnapshots(a: RuntimeSnapshot, b: RuntimeSnapshot): RuntimeDiff {
  const tools = diffTools(a, b);
  const pathOnlyA = onlyIn(a.path, b.path);
  const pathOnlyB = onlyIn(b.path, a.path);
  const pathReordered =
    pathOnlyA.length === 0 && pathOnlyB.length === 0 && a.path.join("\0") !== b.path.join("\0");
  const globals = diffGlobals(a, b);
  const envFlagOnlyA = onlyIn(a.envFlagNames, b.envFlagNames);
  const envFlagOnlyB = onlyIn(b.envFlagNames, a.envFlagNames);

  const osSame =
    a.os.platform === b.os.platform && a.os.arch === b.os.arch && a.os.release === b.os.release;
  const fmtOs = (s: RuntimeSnapshot) => `${s.os.platform}/${s.os.arch} ${s.os.release}`;

  const equivalent =
    tools.every((t) => t.status === "same") &&
    !pathReordered &&
    pathOnlyA.length === 0 &&
    pathOnlyB.length === 0 &&
    globals.length === 0;

  return {
    os: { status: osSame ? "same" : "different", a: fmtOs(a), b: fmtOs(b) },
    tools,
    pathReordered,
    pathOnlyA,
    pathOnlyB,
    globals,
    envFlagOnlyA,
    envFlagOnlyB,
    equivalent,
  };
}
