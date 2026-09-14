import Foundation

/// A concrete definition of a variable in one file.
public struct Definition {
    public var name: String
    public var value: String?
    public var type: VariableType
    public var isSecret: Bool
    public var environment: String?
    public var origin: Origin
}

/// The format-agnostic view detectors operate on. Built once by
/// `buildIndex` so detectors never scan raw files and never repeat work.
///
/// Dictionaries preserve insertion order (like JS Maps) because finding order
/// is part of the observable output.
public struct IndexedModel {
    public var model: ProjectModel
    /// Every definition found in dotenv files, keyed by name (duplicates kept).
    public var envDefinitions: [(String, [Definition])]
    /// Definitions found in docker-compose files, keyed by name.
    public var composeDefinitions: [(String, [Definition])]
    /// Definitions found in GitHub Actions workflows, keyed by name.
    public var actionDefinitions: [(String, [Definition])]
    /// Definitions found in Kubernetes manifests, keyed by name.
    public var k8sDefinitions: [(String, [Definition])]
    /// Every usage (source, compose, actions, k8s), keyed by name.
    public var usages: [(String, [Origin])]
    /// Usages that come specifically from source code.
    public var sourceUsages: [(String, [Origin])]
    /// Names documented in `.env.example`, in first-seen order.
    public var exampleNames: [String]
    /// Distinct environment labels among dotenv files (excluding "example").
    public var envLabels: [String]

    public func envDefinitionsMap() -> [String: [Definition]] {
        Dictionary(uniqueKeysWithValues: envDefinitions)
    }

    public func composeDefinitionsMap() -> [String: [Definition]] {
        Dictionary(uniqueKeysWithValues: composeDefinitions)
    }

    public func actionDefinitionsMap() -> [String: [Definition]] {
        Dictionary(uniqueKeysWithValues: actionDefinitions)
    }

    public func k8sDefinitionsMap() -> [String: [Definition]] {
        Dictionary(uniqueKeysWithValues: k8sDefinitions)
    }

    public func usagesMap() -> [String: [Origin]] {
        Dictionary(uniqueKeysWithValues: usages)
    }

    public func sourceUsagesMap() -> [String: [Origin]] {
        Dictionary(uniqueKeysWithValues: sourceUsages)
    }
}

public protocol Detector {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    func detect(_ index: IndexedModel) -> [Finding]
}

/// Build the format-agnostic index detectors operate on.
public func buildIndex(_ model: ProjectModel) -> IndexedModel {
    var envDefinitions: [(String, [Definition])] = []
    var composeDefinitions: [(String, [Definition])] = []
    var actionDefinitions: [(String, [Definition])] = []
    var k8sDefinitions: [(String, [Definition])] = []
    var usages: [(String, [Origin])] = []
    var sourceUsages: [(String, [Origin])] = []
    var exampleNames: [String] = []
    var exampleNameSet = Set<String>()
    var envLabelSet = Set<String>()
    var envLabelOrder: [String] = []

    func push(_ list: inout [(String, [Definition])], _ def: Definition) {
        if let idx = list.firstIndex(where: { $0.0 == def.name }) {
            list[idx].1.append(def)
        } else {
            list.append((def.name, [def]))
        }
    }

    func pushOrigin(_ list: inout [(String, [Origin])], _ name: String, _ origin: Origin) {
        if let idx = list.firstIndex(where: { $0.0 == name }) {
            list[idx].1.append(origin)
        } else {
            list.append((name, [origin]))
        }
    }

    for file in model.envFiles {
        if file.environment == "example" {
            // .env.example documents what *should* exist but is not a runtime value.
            for v in file.variables where !exampleNameSet.contains(v.name) {
                exampleNameSet.insert(v.name)
                exampleNames.append(v.name)
            }
        } else {
            if let env = file.environment, !envLabelSet.contains(env) {
                envLabelSet.insert(env)
                envLabelOrder.append(env)
            }
            for v in file.variables {
                for origin in v.origins {
                    push(&envDefinitions, Definition(
                        name: v.name,
                        value: v.value,
                        type: v.type,
                        isSecret: v.isSecret,
                        environment: file.environment,
                        origin: origin
                    ))
                }
            }
        }
    }

    for file in model.composeFiles {
        for v in file.variables {
            for origin in v.origins {
                push(&composeDefinitions, Definition(
                    name: v.name, value: v.value, type: v.type, isSecret: v.isSecret,
                    environment: file.environment, origin: origin
                ))
            }
        }
        for v in file.usages {
            for origin in v.origins { pushOrigin(&usages, v.name, origin) }
        }
    }

    for file in model.actionFiles {
        for v in file.variables {
            for origin in v.origins {
                push(&actionDefinitions, Definition(
                    name: v.name, value: v.value, type: v.type, isSecret: v.isSecret,
                    environment: file.environment, origin: origin
                ))
            }
        }
        for v in file.usages {
            for origin in v.origins { pushOrigin(&usages, v.name, origin) }
        }
    }

    for file in model.k8sFiles {
        for v in file.variables {
            for origin in v.origins {
                push(&k8sDefinitions, Definition(
                    name: v.name, value: v.value, type: v.type, isSecret: v.isSecret,
                    environment: file.environment, origin: origin
                ))
            }
        }
        for v in file.usages {
            for origin in v.origins { pushOrigin(&usages, v.name, origin) }
        }
    }

    for file in model.sourceFiles {
        for v in file.usages {
            for origin in v.origins {
                pushOrigin(&usages, v.name, origin)
                pushOrigin(&sourceUsages, v.name, origin)
            }
        }
    }

    return IndexedModel(
        model: model,
        envDefinitions: envDefinitions,
        composeDefinitions: composeDefinitions,
        actionDefinitions: actionDefinitions,
        k8sDefinitions: k8sDefinitions,
        usages: usages,
        sourceUsages: sourceUsages,
        exampleNames: exampleNames,
        envLabels: envLabelOrder
    )
}
