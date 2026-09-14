import Foundation

/// How an item relates across two snapshots.
public enum RuntimeStatus: String {
    case same, different, onlyA = "onlyA", onlyB = "onlyB"
}

public struct OsDiff {
    public var status: RuntimeStatus
    public var a: String
    public var b: String
}

public struct ToolDiff {
    public var name: String
    public var status: RuntimeStatus
    public var a: String?
    public var b: String?
}

public struct GlobalDiff {
    public var ecosystem: String
    public var name: String
    public var status: RuntimeStatus
    public var a: String?
    public var b: String?
}

public struct RuntimeDiff {
    public var os: OsDiff
    public var tools: [ToolDiff]
    /// True when both share the same PATH entries but in a different order.
    public var pathReordered: Bool
    public var pathOnlyA: [String]
    public var pathOnlyB: [String]
    public var globals: [GlobalDiff]
    public var envFlagOnlyA: [String]
    public var envFlagOnlyB: [String]
    /// True when nothing meaningful differs (drift-free).
    public var equivalent: Bool
}

public enum CompareSnapshots {
    private static func statusFor(_ a: String?, _ b: String?) -> RuntimeStatus {
        if let a, let b { return a == b ? .same : .different }
        return a != nil ? .onlyA : .onlyB
    }

    private static func diffTools(_ a: RuntimeSnapshot, _ b: RuntimeSnapshot) -> [ToolDiff] {
        var av: [String: String] = [:]
        for t in a.tools { av[t.tool] = t.version }
        var bv: [String: String] = [:]
        for t in b.tools { bv[t.tool] = t.version }
        let names = Set(av.keys).union(bv.keys).sorted()
        return names.map { name in
            ToolDiff(name: name, status: statusFor(av[name], bv[name]), a: av[name], b: bv[name])
        }
    }

    private static func diffGlobals(_ a: RuntimeSnapshot, _ b: RuntimeSnapshot) -> [GlobalDiff] {
        let aEcos = Dictionary(uniqueKeysWithValues: a.globals)
        let bEcos = Dictionary(uniqueKeysWithValues: b.globals)
        var result: [GlobalDiff] = []
        for eco in Set(aEcos.keys).union(bEcos.keys).sorted() {
            func index(_ list: [GlobalPackage]?) -> [String: String] {
                var map: [String: String] = [:]
                for p in list ?? [] { map[p.name] = p.version }
                return map
            }
            let av = index(aEcos[eco])
            let bv = index(bEcos[eco])
            for name in Set(av.keys).union(bv.keys).sorted() {
                let status = statusFor(av[name], bv[name])
                if status == .same { continue }
                result.append(GlobalDiff(ecosystem: eco, name: name, status: status, a: av[name], b: bv[name]))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Set difference preserving A's order.
    private static func onlyIn(_ a: [String], _ b: [String]) -> [String] {
        let set = Set(b)
        return a.filter { !set.contains($0) }
    }

    /// Pure comparison of two runtime snapshots. `capturedAt` is ignored.
    public static func compare(_ a: RuntimeSnapshot, _ b: RuntimeSnapshot) -> RuntimeDiff {
        let tools = diffTools(a, b)
        let pathOnlyA = onlyIn(a.path, b.path)
        let pathOnlyB = onlyIn(b.path, a.path)
        let pathReordered = pathOnlyA.isEmpty && pathOnlyB.isEmpty && a.path.joined(separator: "\0") != b.path.joined(separator: "\0")
        let globals = diffGlobals(a, b)
        let envFlagOnlyA = onlyIn(a.envFlagNames, b.envFlagNames)
        let envFlagOnlyB = onlyIn(b.envFlagNames, a.envFlagNames)

        let osSame = a.osPlatform == b.osPlatform && a.osArch == b.osArch && a.osRelease == b.osRelease
        func fmtOs(_ s: RuntimeSnapshot) -> String { "\(s.osPlatform)/\(s.osArch) \(s.osRelease)" }

        let equivalent = tools.allSatisfy { $0.status == .same }
            && !pathReordered
            && pathOnlyA.isEmpty
            && pathOnlyB.isEmpty
            && globals.isEmpty

        return RuntimeDiff(
            os: OsDiff(status: osSame ? .same : .different, a: fmtOs(a), b: fmtOs(b)),
            tools: tools,
            pathReordered: pathReordered,
            pathOnlyA: pathOnlyA,
            pathOnlyB: pathOnlyB,
            globals: globals,
            envFlagOnlyA: envFlagOnlyA,
            envFlagOnlyB: envFlagOnlyB,
            equivalent: equivalent
        )
    }
}
