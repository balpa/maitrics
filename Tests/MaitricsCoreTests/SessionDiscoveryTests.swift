import XCTest
@testable import MaitricsCore

final class SessionDiscoveryTests: XCTestCase {

    // MARK: - testParsesSessionIndex

    func testParsesSessionIndex() throws {
        let fixtureURL = Bundle.module.url(forResource: "sessions-index-sample", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: fixtureURL)
        let index = try SessionDiscovery.parseIndex(data: data)

        XCTAssertEqual(index.version, 1)
        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.originalPath, "/Users/test/project")

        let first = index.entries[0]
        XCTAssertEqual(first.sessionId, "96176827-8c1f-4081-ba5e-137450a7e4f9")
        XCTAssertEqual(first.firstPrompt, "Fix authentication bug in login flow")
        XCTAssertEqual(first.messageCount, 42)
        XCTAssertEqual(first.gitBranch, "main")
        XCTAssertEqual(first.projectPath, "/Users/test/project")
        XCTAssertEqual(first.isSidechain, false)

        let second = index.entries[1]
        XCTAssertEqual(second.sessionId, "aaaa1111-2222-3333-4444-555566667777")
        XCTAssertEqual(second.firstPrompt, "Add dark mode support to dashboard")
        XCTAssertEqual(second.messageCount, 15)
        XCTAssertEqual(second.gitBranch, "feat/dark-mode")
    }

    // MARK: - testDecodeProjectNameFromPath

    func testDecodeProjectNameFromPath() {
        let name = SessionDiscovery.projectName(fromEncodedPath: "-Users-berke-Documents-my-project")
        XCTAssertEqual(name, "my-project")
    }

    func testDecodeProjectNameDesktop() {
        let name = SessionDiscovery.projectName(fromEncodedPath: "-Users-berke-Desktop-cool-app")
        XCTAssertEqual(name, "cool-app")
    }

    func testDecodeProjectNameRepos() {
        let name = SessionDiscovery.projectName(fromEncodedPath: "-Users-berke-repos-my-lib")
        XCTAssertEqual(name, "my-lib")
    }

    // MARK: - testDecodeProjectNameFallback

    func testDecodeProjectNameFallback() {
        let name = SessionDiscovery.projectName(fromEncodedPath: "some-project")
        XCTAssertEqual(name, "project")
    }

    func testDecodeProjectNameSingleComponent() {
        let name = SessionDiscovery.projectName(fromEncodedPath: "myproject")
        XCTAssertEqual(name, "myproject")
    }

    // MARK: - testDiscoverSessionsFromTempDirectory

    func testDiscoverSessionsFromTempDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("maitrics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let projectDir = tmp.appendingPathComponent("-Users-test-Documents-my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let fixtureURL = Bundle.module.url(forResource: "sessions-index-sample", withExtension: "json", subdirectory: "Fixtures")!
        let indexDest = projectDir.appendingPathComponent("sessions-index.json")
        try FileManager.default.copyItem(at: fixtureURL, to: indexDest)

        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: tmp)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].projectName, "my-project")

        // Sorted by modified descending — second entry has later modified time
        XCTAssertEqual(sessions[0].sessionId, "aaaa1111-2222-3333-4444-555566667777")
        XCTAssertEqual(sessions[0].firstPrompt, "Add dark mode support to dashboard")
        XCTAssertEqual(sessions[0].messageCount, 15)
        XCTAssertEqual(sessions[0].gitBranch, "feat/dark-mode")

        XCTAssertEqual(sessions[1].sessionId, "96176827-8c1f-4081-ba5e-137450a7e4f9")
        XCTAssertEqual(sessions[1].firstPrompt, "Fix authentication bug in login flow")
        XCTAssertEqual(sessions[1].messageCount, 42)
    }

    func testDiscoverSessionsFiltersOutSidechains() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("maitrics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let projectDir = tmp.appendingPathComponent("-Users-test-Documents-my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let indexJSON = """
        {
          "version": 1,
          "entries": [
            {
              "sessionId": "main-session",
              "fullPath": "/tmp/main.jsonl",
              "firstPrompt": "Main session prompt",
              "messageCount": 5,
              "created": "2026-04-01T10:00:00.000Z",
              "modified": "2026-04-01T11:00:00.000Z",
              "isSidechain": false
            },
            {
              "sessionId": "side-session",
              "fullPath": "/tmp/side.jsonl",
              "firstPrompt": "Side session prompt",
              "messageCount": 3,
              "created": "2026-04-01T10:00:00.000Z",
              "modified": "2026-04-01T12:00:00.000Z",
              "isSidechain": true
            }
          ]
        }
        """
        let indexDest = projectDir.appendingPathComponent("sessions-index.json")
        try indexJSON.data(using: .utf8)!.write(to: indexDest)

        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: tmp)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "main-session")
    }

    // MARK: - testDiscoverSessionsFromJSONLFiles

    func testDiscoverSessionsFromJSONLFiles() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("maitrics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let projectDir = tmp.appendingPathComponent("-Users-test-Documents-jsonl-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // No sessions-index.json — only JSONL files
        let jsonlContent = """
        {"type":"system","message":{"content":"System init"}}
        {"type":"user","message":{"content":"Hello from JSONL file"}}
        {"type":"assistant","message":{"content":"Hi there"}}
        """

        let jsonlFile = projectDir.appendingPathComponent("abc12345-test-session.jsonl")
        try jsonlContent.data(using: .utf8)!.write(to: jsonlFile)

        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: tmp)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "abc12345-test-session")
        XCTAssertEqual(sessions[0].firstPrompt, "Hello from JSONL file")
        XCTAssertEqual(sessions[0].messageCount, 0)
        XCTAssertNil(sessions[0].gitBranch)
        XCTAssertEqual(sessions[0].projectName, "jsonl-project")
        XCTAssertEqual(
            sessions[0].jsonlPath.map { ($0 as NSString).resolvingSymlinksInPath },
            (jsonlFile.path as NSString).resolvingSymlinksInPath
        )
    }

    func testDiscoverSessionsEmptyDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("maitrics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: tmp)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testDiscoverSessionsNonexistentDirectory() throws {
        let nonexistent = FileManager.default.temporaryDirectory
            .appendingPathComponent("maitrics-nonexistent-\(UUID().uuidString)")
        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: nonexistent)
        XCTAssertTrue(sessions.isEmpty)
    }
}
