import Foundation

/// A parser turns the raw text of one supported file format into envdoctor's
/// normalized `EnvironmentFile`.
public protocol Parser {
    var id: String { get }
    func match(_ filePath: String) -> Bool
    func parse(_ content: String, _ filePath: String) -> EnvironmentFile
}

/// Match a path against a registry; returns the first parser that claims it.
public func parserForPath(_ registry: [Parser], _ filePath: String) -> Parser? {
    registry.first { $0.match(filePath) }
}
