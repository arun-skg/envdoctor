import Foundation

/// Public-prefix leak: variables whose names match the secret heuristic but
/// use a framework prefix that exposes them to client-side bundles.
public struct PublicPrefixDetector: Detector {
    public let id = "public-prefix"
    public let name = "public-prefix"
    public let description = "A secret-looking variable uses a public framework prefix and will be exposed to client bundles."

    private static let publicPrefixes = [
        "NEXT_PUBLIC_",
        "VITE_",
        "PUBLIC_",
        "REACT_APP_",
        "GATSBY_",
        "EXPO_PUBLIC_",
        "NUXT_PUBLIC_",
        "ASTRO_PUBLIC_",
    ]

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        for (name, defs) in index.envDefinitions {
            guard let prefix = PublicPrefixDetector.publicPrefixes.first(where: { name.hasPrefix($0) }) else { continue }
            if !isSecretName(name) { continue }
            findings.append(makeFinding(
                "public-prefix", .error, name,
                "\(name) uses public prefix \"\(prefix)\"; secret-looking variables with this prefix are exposed to client bundles",
                defs.map(\.origin)
            ))
        }
        return findings
    }
}
