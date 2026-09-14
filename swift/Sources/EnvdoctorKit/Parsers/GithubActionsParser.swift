import Foundation

/// Parser for GitHub Actions workflow files (`.github/workflows/*.{yml,yaml}`).
///
/// Definitions come from `env:` blocks at the workflow, job, and step level.
/// `${{ secrets.NAME }}` / `${{ vars.NAME }}` and `$VAR` / `${VAR}`
/// interpolations anywhere in the file become usages.
public struct GithubActionsParser: Parser {
    public let id = "github-actions"

    private static let secretRefRe = try! NSRegularExpression(pattern: #"\$\{\{\s*(secrets|vars)\.([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}"#)

    public init() {}

    public func match(_ filePath: String) -> Bool {
        let base = (filePath as NSString).lastPathComponent
        let isWorkflow = filePath.contains("/.github/workflows/")
        guard isWorkflow else { return false }
        guard let re = try? NSRegularExpression(pattern: #"\.(ya?ml)$"#) else { return false }
        let range = NSRange(base.startIndex..<base.endIndex, in: base)
        return re.firstMatch(in: base, range: range) != nil
    }

    public func parse(_ content: String, _ filePath: String) -> EnvironmentFile {
        let doc = YamlFacade.loadFirst(content)
        var variables: [EnvironmentVariable] = []
        if let doc {
            collectEnvBlocks(doc, content, filePath, &variables)
        }

        var usages: [EnvironmentVariable] = []

        // ${{ secrets.X }} / ${{ vars.X }} → usages.
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        GithubActionsParser.secretRefRe.enumerateMatches(in: content, range: nsRange) { match, _, _ in
            guard let match,
                  let subkindRange = Range(match.range(at: 1), in: content),
                  let nameRange = Range(match.range(at: 2), in: content) else { return }
            let name = String(content[nameRange])
            let subkind = String(content[subkindRange])
            let offset = content.distance(from: content.startIndex, to: Range(match.range, in: content)!.lowerBound)
            let origin = Origin(
                filePath: filePath,
                line: lineForOffset(content, offset),
                kind: .usage,
                format: .githubActions,
                subkind: subkind == "vars" ? "vars" : "secrets"
            )
            usages.append(createVariable(name, nil, [origin]))
        }

        // $VAR / ${VAR} → usages.
        for interp in scanInterpolations(content) {
            usages.append(createVariable(
                interp.name,
                nil,
                [Origin(filePath: filePath, line: interp.line, kind: .usage, format: .githubActions)]
            ))
        }

        return EnvironmentFile(
            filePath: filePath,
            format: .githubActions,
            variables: mergeVariables(variables),
            usages: mergeVariables(usages)
        )
    }

    /// Recursively collect every `env:` block as definition variables.
    private func collectEnvBlocks(_ node: YamlValue, _ content: String, _ filePath: String, _ out: inout [EnvironmentVariable]) {
        switch node {
        case .array(let items):
            for item in items {
                collectEnvBlocks(item, content, filePath, &out)
            }
        case .map(let map):
            if let env = map["env"], case .map(let envMap) = env {
                for (key, rawValue) in envMap.entries {
                    let value: String?
                    let origin: Origin
                    switch rawValue {
                    case .null:
                        value = nil
                        origin = Origin(filePath: filePath, line: lineForNameMap(content, key), kind: .reference, format: .githubActions)
                    default:
                        value = jsString(rawValue)
                        origin = Origin(filePath: filePath, line: lineForNameMap(content, key), kind: .definition, format: .githubActions)
                    }
                    out.append(createVariable(key, value, [origin]))
                }
            }
            for (_, value) in map.entries {
                collectEnvBlocks(value, content, filePath, &out)
            }
        default:
            break
        }
    }
}
