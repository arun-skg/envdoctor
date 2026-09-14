import Foundation
import CZlib

/// Portable snapshot token: `base64url(gzip(json))` with an `envd1:` prefix.
public enum Token {
    private static let prefix = "envd1:"

    public struct TokenError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Serialize a snapshot to compact JSON with the reference property order.
    public static func snapshotToJson(_ snapshot: RuntimeSnapshot) -> String {
        var globals = JSONObject()
        for (eco, packages) in snapshot.globals {
            globals.set(eco, .array(packages.map { p in
                var pkg = JSONObject()
                pkg.set("name", .string(p.name))
                pkg.set("version", .string(p.version))
                return .object(pkg)
            }))
        }

        var osObj = JSONObject()
        osObj.set("platform", .string(snapshot.osPlatform))
        osObj.set("arch", .string(snapshot.osArch))
        osObj.set("release", .string(snapshot.osRelease))

        var root = JSONObject()
        root.set("schema", .int(snapshot.schema))
        root.set("capturedAt", .string(snapshot.capturedAt))
        root.set("os", .object(osObj))
        root.set("tools", .array(snapshot.tools.map { t in
            var tool = JSONObject()
            tool.set("tool", .string(t.tool))
            tool.set("version", .string(t.version))
            tool.set("resolvedFrom", .string(t.resolvedFrom))
            return .object(tool)
        }))
        root.set("path", .array(snapshot.path.map { .string($0) }))
        root.set("globals", .object(globals))
        root.set("envFlagNames", .array(snapshot.envFlagNames.map { .string($0) }))
        return Json.compact(.object(root))
    }

    /// Encode a snapshot into a single-line, paste-safe token.
    public static func encodeToken(_ snapshot: RuntimeSnapshot) -> String {
        let json = Array(snapshotToJson(snapshot).utf8)
        let gzipped = gzip(json)
        return prefix + base64UrlEncode(gzipped)
    }

    /// Decode a token back into a snapshot. Throws a clear error on malformed
    /// or too-new input.
    public static func decodeToken(_ token: String) throws -> RuntimeSnapshot {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(prefix) else {
            throw TokenError(description: "Not an envdoctor snapshot token (missing envd1: prefix).")
        }
        let payload = String(trimmed.dropFirst(prefix.count))
        let snapshot: RuntimeSnapshot
        do {
            let gzipped = try base64UrlDecode(payload)
            let json = try gunzip(gzipped)
            guard let text = String(bytes: json, encoding: .utf8) else {
                throw TokenError(description: "Corrupt snapshot token: could not decode.")
            }
            snapshot = try parseSnapshot(text)
        } catch let e as TokenError {
            throw e
        } catch {
            throw TokenError(description: "Corrupt snapshot token: could not decode.")
        }
        try assertReadable(snapshot)
        return snapshot
    }

    /// Parse raw JSON (from a `--output` file) into a validated snapshot.
    public static func parseSnapshotJson(_ text: String) throws -> RuntimeSnapshot {
        let snapshot: RuntimeSnapshot
        do {
            snapshot = try parseSnapshot(text)
        } catch let e as TokenError {
            throw e
        } catch {
            throw TokenError(description: "Invalid snapshot JSON.")
        }
        try assertReadable(snapshot)
        return snapshot
    }

    /// Reject snapshots from a newer schema than this build understands.
    private static func assertReadable(_ snapshot: RuntimeSnapshot) throws {
        if snapshot.schema > snapshotSchema {
            throw TokenError(description: "Snapshot schema v\(snapshot.schema) is newer than this envdoctor (v\(snapshotSchema)). Upgrade to compare it.")
        }
    }

    private static func parseSnapshot(_ text: String) throws -> RuntimeSnapshot {
        guard case .object(let el) = try JsonParser.parse(text) else {
            throw TokenError(description: "Invalid snapshot JSON.")
        }
        var snapshot = RuntimeSnapshot(
            capturedAt: "",
            osPlatform: "",
            osArch: "",
            osRelease: "",
            tools: [],
            path: [],
            globals: [],
            envFlagNames: []
        )
        if case .int(let schema)? = el["schema"] {
            snapshot.schema = schema
        }
        if case .string(let capturedAt)? = el["capturedAt"] {
            snapshot.capturedAt = capturedAt
        }
        if case .object(let osObj)? = el["os"] {
            snapshot.osPlatform = getStr(osObj, "platform")
            snapshot.osArch = getStr(osObj, "arch")
            snapshot.osRelease = getStr(osObj, "release")
        }
        if case .array(let tools)? = el["tools"] {
            snapshot.tools = tools.map { t in
                guard case .object(let tool) = t else {
                    return ToolVersion(tool: "", version: "", resolvedFrom: "")
                }
                return ToolVersion(
                    tool: getStr(tool, "tool"),
                    version: getStr(tool, "version"),
                    resolvedFrom: getStr(tool, "resolvedFrom")
                )
            }
        }
        if case .array(let path)? = el["path"] {
            snapshot.path = path.map { $0.asString ?? "" }
        }
        if case .object(let globals)? = el["globals"] {
            snapshot.globals = globals.entries.map { eco, value in
                let packages: [GlobalPackage]
                if case .array(let items) = value {
                    packages = items.map { p in
                        guard case .object(let pkg) = p else {
                            return GlobalPackage(name: "", version: "")
                        }
                        return GlobalPackage(name: getStr(pkg, "name"), version: getStr(pkg, "version"))
                    }
                } else {
                    packages = []
                }
                return (eco, packages)
            }
        }
        if case .array(let flags)? = el["envFlagNames"] {
            snapshot.envFlagNames = flags.map { $0.asString ?? "" }
        }
        return snapshot
    }

    private static func getStr(_ obj: JSONObject, _ name: String) -> String {
        obj[name]?.asString ?? ""
    }

    // MARK: - gzip via zlib

    static func gzip(_ data: [UInt8]) -> [UInt8] {
        var stream = z_stream()
        var status = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return data }
        defer { deflateEnd(&stream) }
        var input = data
        var out: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let bufferCount = buffer.count
        input.withUnsafeMutableBytes { inPtr in
            stream.next_in = inPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(data.count)
            repeat {
                buffer.withUnsafeMutableBytes { outPtr in
                    stream.next_out = outPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(bufferCount)
                    status = deflate(&stream, Z_FINISH)
                }
                let produced = bufferCount - Int(stream.avail_out)
                out.append(contentsOf: buffer[0..<produced])
            } while status == Z_OK && stream.avail_out == 0
        }
        return out
    }

    static func gunzip(_ data: [UInt8]) throws -> [UInt8] {
        var stream = z_stream()
        var input = data
        let status = inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            throw TokenError(description: "Corrupt snapshot token: could not decode.")
        }
        defer { inflateEnd(&stream) }
        var out: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let bufferCount = buffer.count
        var inflateStatus: Int32 = Z_OK
        input.withUnsafeMutableBytes { inPtr in
            stream.next_in = inPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(data.count)
            repeat {
                buffer.withUnsafeMutableBytes { outPtr in
                    stream.next_out = outPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(bufferCount)
                    inflateStatus = inflate(&stream, Z_NO_FLUSH)
                }
                let produced = bufferCount - Int(stream.avail_out)
                out.append(contentsOf: buffer[0..<produced])
            } while inflateStatus == Z_OK
        }
        guard inflateStatus == Z_STREAM_END || inflateStatus == Z_BUF_ERROR else {
            throw TokenError(description: "Corrupt snapshot token: could not decode.")
        }
        return out
    }

    // MARK: - base64url

    static func base64UrlEncode(_ data: [UInt8]) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64UrlDecode(_ input: String) throws -> [UInt8] {
        var b64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch b64.count % 4 {
        case 2: b64 += "=="
        case 3: b64 += "="
        case 1: throw TokenError(description: "Corrupt snapshot token: could not decode.")
        default: break
        }
        guard let data = Data(base64Encoded: b64) else {
            throw TokenError(description: "Corrupt snapshot token: could not decode.")
        }
        return Array(data)
    }
}
