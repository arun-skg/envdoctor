import Foundation

public struct ToolVersion {
    public var tool: String
    public var version: String
    /// PATH directory the tool resolved from, with $HOME collapsed to "~".
    public var resolvedFrom: String

    public init(tool: String, version: String, resolvedFrom: String) {
        self.tool = tool
        self.version = version
        self.resolvedFrom = resolvedFrom
    }
}

public struct GlobalPackage {
    public var name: String
    public var version: String
}

/// Bumped whenever the snapshot shape changes; `snapshot-diff` refuses tokens
/// it can't read.
public let snapshotSchema = 1

/// A snapshot captures the *live* shell runtime of one machine. Only variable
/// *names* are recorded in `envFlagNames`, and names that look secret are
/// dropped entirely.
public struct RuntimeSnapshot {
    public var schema: Int
    /// Informational only — never diffed.
    public var capturedAt: String
    public var osPlatform: String
    public var osArch: String
    public var osRelease: String
    /// Present tools only, sorted by tool id.
    public var tools: [ToolVersion]
    /// Ordered `$PATH` entries, $HOME collapsed to "~". Order is significant.
    public var path: [String]
    /// Ecosystem id ("npm", ...) → package inventory. Empty unless --globals.
    public var globals: [(String, [GlobalPackage])]
    /// Non-secret env var NAMES only. Never any values.
    public var envFlagNames: [String]

    public init(schema: Int = snapshotSchema, capturedAt: String, osPlatform: String, osArch: String, osRelease: String, tools: [ToolVersion], path: [String], globals: [(String, [GlobalPackage])], envFlagNames: [String]) {
        self.schema = schema
        self.capturedAt = capturedAt
        self.osPlatform = osPlatform
        self.osArch = osArch
        self.osRelease = osRelease
        self.tools = tools
        self.path = path
        self.globals = globals
        self.envFlagNames = envFlagNames
    }
}
