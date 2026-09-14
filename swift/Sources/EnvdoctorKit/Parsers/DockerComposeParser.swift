import Foundation

/// Parser for docker-compose files.
///
/// Definitions come from `services.<name>.environment:` blocks (both the map
/// and the list form). Bare list entries (`- FOO`) become value-less
/// definitions. `$VAR` / `${VAR}` interpolation anywhere in the file becomes
/// usages.
public struct DockerComposeParser: Parser {
    public let id = "docker-compose"

    private static let basenames: Set<String> = [
        "docker-compose.yml",
        "docker-compose.yaml",
        "docker-compose.override.yml",
        "docker-compose.override.yaml",
        "compose.yml",
        "compose.yaml",
    ]

    public init() {}

    public func match(_ filePath: String) -> Bool {
        DockerComposeParser.basenames.contains((filePath as NSString).lastPathComponent)
    }

    public func parse(_ content: String, _ filePath: String) -> EnvironmentFile {
        let doc = YamlFacade.loadFirst(content)
        var variables: [EnvironmentVariable] = []

        if case .map(let root) = doc, case .map(let services)? = root["services"] {
            for (_, serviceValue) in services.entries {
                guard case .map(let service) = serviceValue else { continue }
                if let env = service["environment"] {
                    variables.append(contentsOf: normalizeEnvironment(env, content, filePath))
                }
            }
        }

        // `$VAR` / `${VAR}` interpolation → usages.
        var usages: [EnvironmentVariable] = []
        for interp in scanInterpolations(content) {
            usages.append(createVariable(
                interp.name,
                nil,
                [Origin(filePath: filePath, line: interp.line, kind: .usage, format: .dockerCompose)]
            ))
        }

        return EnvironmentFile(
            filePath: filePath,
            format: .dockerCompose,
            variables: mergeVariables(variables),
            usages: mergeVariables(usages)
        )
    }

    /// Flatten a service's `environment:` value into definition variables.
    private func normalizeEnvironment(_ env: YamlValue, _ content: String, _ filePath: String) -> [EnvironmentVariable] {
        var variables: [EnvironmentVariable] = []

        switch env {
        case .map(let map):
            // Map form: KEY: value
            for (key, rawValue) in map.entries {
                let value: String?
                let origin: Origin
                switch rawValue {
                case .null:
                    value = nil
                    origin = Origin(filePath: filePath, line: lineForNameMapOrList(content, key), kind: .reference, format: .dockerCompose)
                default:
                    value = jsString(rawValue)
                    origin = Origin(filePath: filePath, line: lineForNameMapOrList(content, key), kind: .definition, format: .dockerCompose)
                }
                variables.append(createVariable(key, value, [origin]))
            }
        case .array(let items):
            // List form: - KEY=value | - KEY
            for item in items {
                guard case .string(let s) = item else { continue }
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if let eq = trimmed.firstIndex(of: "=") {
                    let key = String(trimmed[..<eq])
                    let value = String(trimmed[trimmed.index(after: eq)...])
                    let origin = Origin(filePath: filePath, line: lineForNameMapOrList(content, key), kind: .definition, format: .dockerCompose)
                    variables.append(createVariable(key, value, [origin]))
                } else {
                    let origin = Origin(filePath: filePath, line: lineForNameMapOrList(content, trimmed), kind: .reference, format: .dockerCompose)
                    variables.append(createVariable(trimmed, nil, [origin]))
                }
            }
        default:
            break
        }

        return variables
    }
}
