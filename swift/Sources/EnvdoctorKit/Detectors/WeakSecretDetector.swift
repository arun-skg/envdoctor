import Foundation

/// Weak/placeholder secret detector. Only inspects definitions in actual
/// environment files, never `.env.example`.
public struct WeakSecretDetector: Detector {
    public let id = "weak-secret"
    public let name = "weak-secret"
    public let description = "A secret-looking variable in an environment file has a weak or placeholder value."

    private static let blocklist: Set<String> = [
        "", "changeme", "password", "password123", "secret", "secret123", "token",
        "key", "apikey", "api_key", "test", "testing", "12345678", "123456789",
        "1234567890", "your_secret", "your_token", "your_api_key", "your_password",
        "example", "dummy", "foo", "bar", "admin", "default", "null", "undefined",
    ]

    public init() {}

    private func isWeakSecret(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        if WeakSecretDetector.blocklist.contains(trimmed.lowercased()) { return true }
        if trimmed.count < 8 { return true }
        return false
    }

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        for (name, defs) in index.envDefinitions {
            for def in defs {
                if !def.isSecret { continue }
                if !isWeakSecret(def.value) { continue }
                let location = def.origin.line.map { "\(def.origin.filePath):\($0)" } ?? def.origin.filePath
                findings.append(makeFinding(
                    "weak-secret", .warning, name,
                    "\(name) has a weak or placeholder value in \(location)",
                    [def.origin]
                ))
            }
        }
        return findings
    }
}
