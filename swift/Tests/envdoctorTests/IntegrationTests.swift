import EnvdoctorKit
import Foundation
import XCTest

/// Scratch project on disk, mirroring dotnet's `TempProject` helper.
final class TempProject {
    let path: String

    init() {
        path = NSTemporaryDirectory() + "envdoctor-test-" + UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func write(_ rel: String, _ content: String) {
        let full = (path as NSString).appendingPathComponent(rel)
        let dir = (full as NSString).deletingLastPathComponent
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try! content.write(toFile: full, atomically: true, encoding: .utf8)
    }

    func read(_ rel: String) -> String {
        try! String(contentsOfFile: (path as NSString).appendingPathComponent(rel), encoding: .utf8)
    }

    func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(rel))
    }

    func dispose() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

final class IntegrationTests: XCTestCase {
    private func createTestProject(_ dir: TempProject) {
        dir.write(".env",
                  "DATABASE_URL=postgres://localhost:5432/myapp\nAPI_KEY=secret123\nDEBUG=true\nPORT=3000\n")
        dir.write(".env.example", "DATABASE_URL=\nAPI_KEY=\nDEBUG=false\nPORT=\n")
        dir.write("config.js",
                  "const db = process.env.DATABASE_URL;\nconst port = process.env.PORT;\nconst missing = process.env.MISSING_SECRET;\n")
        dir.write("docker-compose.yml",
                  "version: '3'\nservices:\n  app:\n    environment:\n      - DATABASE_URL\n      - API_KEY\n      - DEBUG\n")
    }

    private func scan(_ dir: TempProject, format: OutputFormat = .human) -> ScanArgs {
        var args = ScanArgs()
        args.root = dir.path
        args.format = format
        return args
    }

    func testScanFindsIssues() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)
        XCTAssertEqual(try ScanCommand.run(scan(temp)), 1)
    }

    func testInitCreatesConfig() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        var args = InitArgs()
        args.root = temp.path
        args.force = true
        XCTAssertEqual(try InitCommand.run(args), 0)
        XCTAssertTrue(temp.exists("envdoctor.config.toml"))
        let content = temp.read("envdoctor.config.toml")
        XCTAssertTrue(content.contains("ignoreVariables"))
        XCTAssertTrue(content.contains("rules"))
    }

    func testGenerateEnvExample() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)
        var args = GenerateArgs(target: .envExample)
        args.root = temp.path
        args.output = ".env.example"
        XCTAssertEqual(try GenerateCommand.run(args), 0)
        let content = temp.read(".env.example")
        XCTAssertTrue(content.contains("DATABASE_URL"))
        XCTAssertTrue(content.contains("API_KEY"))
    }

    func testGenerateEnvDoc() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)
        var args = GenerateArgs(target: .envDoc)
        args.root = temp.path
        XCTAssertEqual(try GenerateCommand.run(args), 0)
    }

    func testGenerateEnvTypes() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)
        var args = GenerateArgs(target: .envTypes)
        args.root = temp.path
        XCTAssertEqual(try GenerateCommand.run(args), 0)
    }

    func testGenerateConfigSchema() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        var args = GenerateArgs(target: .configSchema)
        args.root = temp.path
        XCTAssertEqual(try GenerateCommand.run(args), 0)
    }

    func testGenerateConfigTemplate() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        var args = GenerateArgs(target: .configTemplate)
        args.root = temp.path
        XCTAssertEqual(try GenerateCommand.run(args), 0)
    }

    func testGenerateGithubActions() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        var args = GenerateArgs(target: .githubActions)
        args.root = temp.path
        XCTAssertEqual(try GenerateCommand.run(args), 0)
    }

    func testScanJsonOutput() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)
        XCTAssertEqual(try ScanCommand.run(scan(temp, format: .json)), 1)
    }

    func testScanSarifOutput() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)
        XCTAssertEqual(try ScanCommand.run(scan(temp, format: .sarif)), 1)
    }

    func testScanWithConfig() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        createTestProject(temp)

        let baseline = try ScanCommand.run(scan(temp))
        XCTAssertEqual(baseline, 1)

        temp.write("envdoctor.config.toml", "ignoreVariables = [\"MISSING_SECRET\"]\n")
        let exit = try ScanCommand.run(scan(temp))
        XCTAssertEqual(exit, 0)
    }

    func testDiffReportsMissingKeys() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        temp.write(".env", "DATABASE_URL=postgres://localhost/dev\nDEBUG=true\n")
        temp.write(".env.production", "DATABASE_URL=postgres://prod/db\n")

        var args = DiffArgs(envA: "development", envB: "production")
        args.root = temp.path
        XCTAssertEqual(try DiffCommand.run(args), 1)

        var jsonArgs = DiffArgs(envA: "development", envB: "production")
        jsonArgs.root = temp.path
        jsonArgs.json = true
        XCTAssertEqual(try DiffCommand.run(jsonArgs), 1)
    }

    func testSyncDryRunDoesNotModifyTarget() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        temp.write(".env", "DATABASE_URL=postgres://localhost/dev\nDEBUG=true\nEXTRA_KEY=value\n")
        temp.write(".env.production", "DATABASE_URL=postgres://prod/db\n")
        let before = temp.read(".env.production")

        var args = SyncArgs(from: "development", to: "production")
        args.root = temp.path
        args.dryRun = true
        XCTAssertEqual(try SyncCommand.run(args), 0)
        XCTAssertEqual(before, temp.read(".env.production"))
    }

    func testSnapshotDiffIdenticalAndDiffering() throws {
        let temp = TempProject()
        defer { temp.dispose() }
        var snapshot = Capture.captureSnapshot(globals: false)
        let json = Token.snapshotToJson(snapshot)

        temp.write("a.json", json)
        temp.write("b.json", json)

        var sameArgs = SnapshotDiffArgs(a: "a.json", b: "b.json")
        sameArgs.root = temp.path
        XCTAssertEqual(try SnapshotDiffCommand.run(sameArgs), 0)

        snapshot.tools.append(ToolVersion(tool: "zzz-fake-tool", version: "9.9.9", resolvedFrom: "PATH"))
        temp.write("b.json", Token.snapshotToJson(snapshot))

        var diffArgs = SnapshotDiffArgs(a: "a.json", b: "b.json")
        diffArgs.root = temp.path
        diffArgs.json = true
        XCTAssertEqual(try SnapshotDiffCommand.run(diffArgs), 1)
    }

    func testGlobMatching() {
        XCTAssertTrue(Glob.matchesGlob("AWS_*", "AWS_SECRET"))
        XCTAssertFalse(Glob.matchesGlob("AWS_*", "GCP_SECRET"))
        XCTAssertTrue(Glob.matchesGlob("FOO*", "FOO"))
        XCTAssertTrue(Glob.matchesGlob("FOO*", "FOOBAR"))
        XCTAssertFalse(Glob.matchesGlob("FOO*", "BAR"))

        XCTAssertTrue(Glob.matchesAnyGlob(["AWS_*", "GCP_*"], "AWS_KEY"))
        XCTAssertTrue(Glob.matchesAnyGlob(["AWS_*", "GCP_*"], "GCP_KEY"))
        XCTAssertFalse(Glob.matchesAnyGlob(["AWS_*", "GCP_*"], "AZURE_KEY"))
    }

    func testVariableTypeInference() {
        XCTAssertEqual(TypeInfer.inferType("42"), .integer)
        XCTAssertEqual(TypeInfer.inferType("3.14"), .float)
        XCTAssertEqual(TypeInfer.inferType("true"), .boolean)
        XCTAssertEqual(TypeInfer.inferType("false"), .boolean)
        XCTAssertEqual(TypeInfer.inferType("https://example.com"), .url)
        XCTAssertEqual(TypeInfer.inferType("http://localhost:3000"), .url)
        XCTAssertEqual(TypeInfer.inferType("{\"key\": \"value\"}"), .json)
        XCTAssertEqual(TypeInfer.inferType("hello"), .string)
        XCTAssertEqual(TypeInfer.inferType(nil), .unknown)
    }

    func testSecretDetection() {
        XCTAssertTrue(isSecretName("API_KEY"))
        XCTAssertTrue(isSecretName("SECRET"))
        XCTAssertTrue(isSecretName("PASSWORD"))
        XCTAssertTrue(isSecretName("TOKEN"))
        XCTAssertTrue(isSecretName("PRIVATE_KEY"))
        XCTAssertFalse(isSecretName("DEBUG"))
        XCTAssertFalse(isSecretName("PORT"))
        XCTAssertFalse(isSecretName("NODE_ENV"))
    }
}
