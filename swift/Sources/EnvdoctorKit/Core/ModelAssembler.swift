import Foundation

/// Read every discovered file and parse it into envdoctor's normalized model.
/// Unreadable or unparseable files are recorded in `parseErrors` rather than
/// aborting the whole scan.
public func assembleModel(
    _ rootDir: String,
    _ config: EnvdoctorConfig,
    _ discovered: [DiscoveredFile]
) -> ProjectModel {
    var envFiles: [EnvironmentFile] = []
    var composeFiles: [EnvironmentFile] = []
    var actionFiles: [EnvironmentFile] = []
    var k8sFiles: [EnvironmentFile] = []
    var sourceFiles: [EnvironmentFile] = []
    var parseErrors: [(filePath: String, error: String)] = []

    for item in discovered {
        let content: String
        do {
            content = try String(contentsOfFile: item.filePath, encoding: .utf8)
        } catch {
            parseErrors.append((item.filePath, "cannot read: \(error.localizedDescription)"))
            continue
        }

        let parsed = item.parser.parse(content, item.filePath)

        switch parsed.format {
        case .dotenv: envFiles.append(parsed)
        case .dockerCompose: composeFiles.append(parsed)
        case .githubActions: actionFiles.append(parsed)
        case .kubernetes: k8sFiles.append(parsed)
        case .source: sourceFiles.append(parsed)
        }
    }

    applyIgnoreVariables(&envFiles, config)
    applyIgnoreVariables(&composeFiles, config)
    applyIgnoreVariables(&actionFiles, config)
    applyIgnoreVariables(&k8sFiles, config)
    applyIgnoreVariables(&sourceFiles, config)

    applyEnvironmentOverrides(&envFiles, rootDir, config)

    let allFiles = envFiles + composeFiles + actionFiles + k8sFiles + sourceFiles

    return ProjectModel(
        rootDir: rootDir,
        config: config,
        envFiles: envFiles,
        composeFiles: composeFiles,
        actionFiles: actionFiles,
        k8sFiles: k8sFiles,
        sourceFiles: sourceFiles,
        allFiles: allFiles,
        parseErrors: parseErrors
    )
}

/// Drop variables whose names match `ignoreVariables` from a set of files.
private func applyIgnoreVariables(_ files: inout [EnvironmentFile], _ config: EnvdoctorConfig) {
    if config.ignoreVariables.isEmpty { return }
    for i in files.indices {
        files[i].variables = files[i].variables.filter { !Glob.matchesAnyGlob(config.ignoreVariables, $0.name) }
        files[i].usages = files[i].usages.filter { !Glob.matchesAnyGlob(config.ignoreVariables, $0.name) }
    }
}

/// Re-tag env files with explicit environment labels from the config.
private func applyEnvironmentOverrides(_ envFiles: inout [EnvironmentFile], _ rootDir: String, _ config: EnvdoctorConfig) {
    guard let environments = config.environments else { return }
    for i in envFiles.indices {
        let rel = relativePath(rootDir, envFiles[i].filePath)
        for (label, patterns) in environments {
            if Glob.matchesAnyGlob(patterns, rel) {
                envFiles[i].environment = label
                func retag(_ v: inout EnvironmentVariable) {
                    for j in v.origins.indices {
                        v.origins[j].environment = label
                    }
                }
                for j in envFiles[i].variables.indices { retag(&envFiles[i].variables[j]) }
                for j in envFiles[i].usages.indices { retag(&envFiles[i].usages[j]) }
                break
            }
        }
    }
}
