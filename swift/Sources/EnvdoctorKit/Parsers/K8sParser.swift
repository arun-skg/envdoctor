import Foundation

/// Parser for Kubernetes manifests.
///
/// Matches YAML files that look like Kubernetes resources (have apiVersion and
/// kind). Extracts container environment definitions and `${VAR}` / `$VAR`
/// interpolations from command/args/env values.
public struct K8sParser: Parser {
    public let id = "kubernetes"

    public init() {}

    public func match(_ filePath: String) -> Bool {
        let ext = ((filePath as NSString).pathExtension).lowercased()
        return ext == "yaml" || ext == "yml"
    }

    public func parse(_ content: String, _ filePath: String) -> EnvironmentFile {
        let docs = YamlFacade.loadAll(content)

        var variables: [EnvironmentVariable] = []
        var usages: [EnvironmentVariable] = []

        for doc in docs {
            guard case .map(let map) = doc,
                  case .string? = map["apiVersion"],
                  case .string? = map["kind"] else {
                continue
            }
            walkResource(map, content, filePath, &variables, &usages)
        }

        return EnvironmentFile(
            filePath: filePath,
            format: .kubernetes,
            variables: mergeVariables(variables),
            usages: mergeVariables(usages)
        )
    }

    private func originAt(_ filePath: String, _ line: Int?, _ kind: Origin.Kind = .definition) -> Origin {
        Origin(filePath: filePath, line: line, kind: kind, format: .kubernetes)
    }

    private func walkResource(_ doc: YamlMap, _ content: String, _ filePath: String, _ variables: inout [EnvironmentVariable], _ usages: inout [EnvironmentVariable]) {
        guard case .string(let kind) = doc["kind"] else { return }

        // ConfigMap data keys become definitions.
        if kind == "ConfigMap" {
            if let data = getObject(doc, "data") {
                for (key, value) in data.entries {
                    guard case .string(let s) = value else { continue }
                    variables.append(createVariable(key, s, [originAt(filePath, nil)]))
                }
            }
            return
        }

        guard let spec = getObject(doc, "spec") else { return }

        let template = getObject(spec, "template")
        let podSpec = template.flatMap { getObject($0, "spec") } ?? spec

        let containers = getArray(podSpec, "containers") ?? []
        let initContainers = getArray(podSpec, "initContainers") ?? []

        for container in containers + initContainers {
            guard case .map(let containerMap) = container else { continue }

            let env = getArray(containerMap, "env") ?? []
            for raw in env {
                guard case .map(let entry) = raw else { continue }
                guard case .string(let name) = entry["name"] else { continue }

                if let value = entry["value"], case .string(let s) = value {
                    variables.append(createVariable(name, s, [originAt(filePath, nil)]))
                } else if entry.contains("valueFrom") {
                    // Referenced but value provided elsewhere (ConfigMap/Secret).
                    usages.append(createVariable(name, nil, [originAt(filePath, nil, .usage)]))
                }
            }

            for raw in getArray(containerMap, "envFrom") ?? [] {
                guard case .map(let entry) = raw else { continue }
                let prefix: String
                if case .string(let p)? = entry["prefix"] {
                    prefix = p
                } else {
                    prefix = ""
                }
                if let ref = entry["configMapRef"], case .map(let refMap) = ref,
                   case .string? = refMap["name"] {
                    usages.append(createVariable("\(prefix)*", nil, [originAt(filePath, nil, .usage)]))
                }
                if let ref = entry["secretRef"], case .map(let refMap) = ref,
                   case .string? = refMap["name"] {
                    usages.append(createVariable("\(prefix)*", nil, [originAt(filePath, nil, .usage)]))
                }
            }

            // Interpolations in command/args.
            for key in ["command", "args"] {
                guard let list = getArray(containerMap, key) else { continue }
                for item in list {
                    guard case .string(let s) = item else { continue }
                    for interp in scanInterpolations(s) {
                        usages.append(createVariable(interp.name, nil, [originAt(filePath, interp.line, .usage)]))
                    }
                }
            }
        }
    }

    private func getObject(_ obj: YamlMap, _ key: String) -> YamlMap? {
        guard let value = obj[key], case .map(let map) = value else { return nil }
        return map
    }

    private func getArray(_ obj: YamlMap, _ key: String) -> [YamlValue]? {
        guard let value = obj[key], case .array(let list) = value else { return nil }
        return list
    }
}
