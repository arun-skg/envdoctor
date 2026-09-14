import Foundation

public struct ConfigError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}

/// Load and validate the config for a project root. Like the reference ports,
/// `envdoctor.config.js/.mjs/.cjs/.ts` are detected but not evaluated (no JS
/// engine); TOML and JSON configs and the `package.json` `envdoctor` key are
/// fully supported.
public enum ConfigLoader {
    private static let configBasenames = [
        "envdoctor.config.toml",
        "envdoctor.config.json",
    ]

    public static func loadConfig(_ rootDir: String) throws -> EnvdoctorConfig {
        let configPath = findConfigFile(rootDir)
        let pkgConfig = readPackageJsonConfig(rootDir)

        if configPath == nil && pkgConfig == nil {
            return EnvdoctorConfig()
        }

        let raw: [String: Any?]
        if let configPath {
            let content: String
            do {
                content = try String(contentsOfFile: configPath, encoding: .utf8)
            } catch {
                throw ConfigError(
                    "Could not load config \(configPath): \(error.localizedDescription). Use envdoctor.config.toml (or package.json#envdoctor).")
            }
            do {
                if configPath.hasSuffix(".toml") {
                    raw = try TomlParser.parse(content)
                } else {
                    guard case .object(let obj) = try JsonParser.parse(content) else {
                        throw ConfigError("Invalid envdoctor config: root must be an object")
                    }
                    raw = jsonObjectToPlain(obj)
                }
            } catch let e as ConfigError {
                throw e
            } catch {
                throw ConfigError("Invalid envdoctor config: \(error.localizedDescription)")
            }
        } else {
            raw = pkgConfig!
        }

        do {
            return try mapConfig(raw)
        } catch let e as ConfigError {
            throw e
        } catch {
            throw ConfigError("Invalid envdoctor config: \(error.localizedDescription)")
        }
    }

    /// Silently fall back to defaults on error, matching the pipeline's
    /// `unwrap_or_default` behavior in the other ports.
    public static func loadConfigOrDefault(_ rootDir: String) -> EnvdoctorConfig {
        do {
            return try loadConfig(rootDir)
        } catch {
            return EnvdoctorConfig()
        }
    }

    private static func findConfigFile(_ rootDir: String) -> String? {
        for basename in configBasenames {
            let candidate = (rootDir as NSString).appendingPathComponent(basename)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func readPackageJsonConfig(_ rootDir: String) -> [String: Any?]? {
        let path = (rootDir as NSString).appendingPathComponent("package.json")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              case .object(let obj) = try? JsonParser.parse(content),
              let section = obj["envdoctor"],
              case .object(let sectionObj) = section else {
            return nil
        }
        return jsonObjectToPlain(sectionObj)
    }

    private static func jsonObjectToPlain(_ obj: JSONObject) -> [String: Any?] {
        var out: [String: Any?] = [:]
        for (key, value) in obj.entries {
            out[key] = jsonValueToPlain(value)
        }
        return out
    }

    private static func jsonValueToPlain(_ value: JSONValue) -> Any? {
        switch value {
        case .null: return nil
        case .bool(let b): return b
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .array(let items): return items.map { jsonValueToPlain($0) }
        case .object(let obj): return jsonObjectToPlain(obj) as Any?
        }
    }

    private struct PlainError: Error, CustomStringConvertible {
        let description: String
    }

    private static func mapConfig(_ raw: [String: Any?]) throws -> EnvdoctorConfig {
        var config = EnvdoctorConfig()
        for (key, value) in raw {
            switch key {
            case "envFilePatterns": config.envFilePatterns = try asStringList(value)
            case "composeFilePatterns": config.composeFilePatterns = try asStringList(value)
            case "actionsFilePatterns": config.actionsFilePatterns = try asStringList(value)
            case "k8sFilePatterns": config.k8sFilePatterns = try asStringList(value)
            case "sourceExtensions": config.sourceExtensions = try asStringList(value)
            case "ignoreVariables": config.ignoreVariables = try asStringList(value)
            case "ignoreFiles": config.ignoreFiles = try asStringList(value)
            case "environments":
                guard let map = value as? [String: Any?] else {
                    throw PlainError(description: "expected a table/object")
                }
                var envs: [String: [String]] = [:]
                for (label, files) in map {
                    envs[label] = try asStringList(files)
                }
                config.environments = envs
            case "strict":
                guard let b = value as? Bool else { throw PlainError(description: "expected a boolean") }
                config.strict = b
            case "rules":
                guard let map = value as? [String: Any?] else {
                    throw PlainError(description: "expected a table/object")
                }
                var rules: [String: RuleSeverity] = [:]
                for (rule, rawSeverity) in map {
                    guard let s = rawSeverity as? String, let severity = RuleSeverity(rawValue: s) else {
                        throw PlainError(description: "expected \"error\", \"warning\", or \"off\"")
                    }
                    rules[rule] = severity
                }
                config.rules = rules
            case "schema":
                guard let map = value as? [String: Any?] else {
                    throw PlainError(description: "expected a table/object")
                }
                var schemas: [String: VariableSchema] = [:]
                for (name, rawSchema) in map {
                    schemas[name] = try parseVariableSchema(rawSchema)
                }
                config.schema = schemas
            default:
                // Unknown keys are ignored, matching the other ports.
                break
            }
        }
        return config
    }

    private static func asStringList(_ value: Any?) throws -> [String] {
        guard let list = value as? [Any?] else {
            throw PlainError(description: "expected an array of strings")
        }
        return try list.map { item in
            guard let s = item as? String else {
                throw PlainError(description: "expected a string")
            }
            return s
        }
    }

    private static func parseVariableSchema(_ value: Any?) throws -> VariableSchema {
        guard let map = value as? [String: Any?] else {
            throw PlainError(description: "expected a table/object")
        }
        var schema = VariableSchema()
        for (key, v) in map {
            switch key {
            case "type":
                guard let s = v as? String, let type = SchemaType(rawValue: s) else {
                    throw PlainError(description: "unknown schema type")
                }
                schema.type = type
            case "optional":
                guard let b = v as? Bool else { throw PlainError(description: "expected a boolean") }
                schema.optional = b
            case "enum", "enumValues":
                schema.enumValues = try asStringList(v)
            case "regex":
                schema.regex = v as? String
            case "min":
                schema.min = try asNumber(v)
            case "max":
                schema.max = try asNumber(v)
            default:
                break
            }
        }
        return schema
    }

    private static func asNumber(_ value: Any?) throws -> Double {
        if let i = value as? Int { return Double(i) }
        if let d = value as? Double { return d }
        throw PlainError(description: "expected an integer")
    }
}
