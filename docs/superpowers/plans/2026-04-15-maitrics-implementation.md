# Maitrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that reads Claude Code CLI usage data from `~/.claude/` and displays it in a modern dark popover dashboard.

**Architecture:** Swift Package Manager project with a `MaitricsCore` library (all testable business logic: JSON parsing, cost calculation, data management) and a `Maitrics` executable (AppKit menu bar controller + SwiftUI views). A build script wraps the executable in a `.app` bundle with Info.plist for `LSUIElement`.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSStatusItem/NSPopover), Swift Charts, CoreServices (FSEvents), macOS 13+

---

## File Structure

```
Maitrics/
├── Package.swift
├── Sources/
│   ├── MaitricsCore/
│   │   ├── Models/
│   │   │   ├── StatsCache.swift          — Codable structs for stats-cache.json
│   │   │   ├── SessionIndex.swift        — Codable structs for sessions-index.json
│   │   │   ├── SessionTokenUsage.swift   — Per-session token aggregation from JSONL
│   │   │   └── AppSettings.swift         — UserDefaults-backed settings
│   │   ├── Services/
│   │   │   ├── CostCalculator.swift      — Token→cost estimation
│   │   │   ├── StatsCacheParser.swift    — Parse stats-cache.json
│   │   │   ├── SessionDiscovery.swift    — Scan projects, discover sessions
│   │   │   ├── SessionParser.swift       — Parse session JSONL for token usage
│   │   │   └── ClaudeDataManager.swift   — Orchestrate all data, @Observable
│   │   └── Utilities/
│   │       ├── FileWatcher.swift         — DispatchSource file monitoring
│   │       └── Formatting.swift          — Token count & cost formatting helpers
│   └── Maitrics/
│       ├── MaitricsApp.swift             — @main App entry, LSUIElement
│       ├── StatusBarController.swift     — NSStatusItem + NSPopover
│       └── Views/
│           ├── PopoverContentView.swift  — Root popover view
│           ├── HeaderView.swift          — App title + settings gear
│           ├── TodaySummaryView.swift    — Three stat cards
│           ├── ModelBreakdownView.swift  — Horizontal bars per model
│           ├── UsageTrendChartView.swift — Swift Charts bar chart
│           ├── RecentSessionsView.swift  — Session list with cost
│           ├── FooterView.swift          — Live status + last refresh
│           ├── SettingsView.swift        — Preferences panel
│           └── EmptyStateView.swift      — No data found message
├── Tests/
│   └── MaitricsCoreTests/
│       ├── Fixtures/
│       │   ├── stats-cache-sample.json
│       │   ├── sessions-index-sample.json
│       │   └── session-sample.jsonl
│       ├── StatsCacheParserTests.swift
│       ├── SessionDiscoveryTests.swift
│       ├── SessionParserTests.swift
│       └── CostCalculatorTests.swift
├── Resources/
│   └── Info.plist
├── Scripts/
│   ├── build-app.sh
│   └── create-dmg.sh
├── CLAUDE.md
└── .gitignore
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/MaitricsCore/Models/.gitkeep` (placeholder so package compiles)
- Create: `Sources/Maitrics/MaitricsApp.swift` (minimal stub)
- Create: `Tests/MaitricsCoreTests/MaitricsCoreTests.swift` (placeholder test)
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`

- [ ] **Step 1: Create Package.swift**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Maitrics",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MaitricsCore",
            path: "Sources/MaitricsCore"
        ),
        .executableTarget(
            name: "Maitrics",
            dependencies: ["MaitricsCore"],
            path: "Sources/Maitrics"
        ),
        .testTarget(
            name: "MaitricsCoreTests",
            dependencies: ["MaitricsCore"],
            resources: [.copy("Fixtures")],
            path: "Tests/MaitricsCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal source files so the package compiles**

`Sources/MaitricsCore/MaitricsCore.swift`:
```swift
// MaitricsCore — business logic library
public enum MaitricsCore {
    public static let version = "0.1.0"
}
```

`Sources/Maitrics/MaitricsApp.swift`:
```swift
import SwiftUI

@main
struct MaitricsApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

`Tests/MaitricsCoreTests/MaitricsCoreTests.swift`:
```swift
import XCTest
@testable import MaitricsCore

final class MaitricsCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(MaitricsCore.version, "0.1.0")
    }
}
```

- [ ] **Step 3: Create Info.plist**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Maitrics</string>
    <key>CFBundleDisplayName</key>
    <string>Maitrics</string>
    <key>CFBundleIdentifier</key>
    <string>com.balpa.maitrics</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Maitrics</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Create build-app.sh**

`Scripts/build-app.sh`:
```bash
#!/bin/bash
set -euo pipefail

CONFIG="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Maitrics"

echo "Building $APP_NAME ($CONFIG)..."
cd "$ROOT_DIR"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "Error: binary not found at $BIN_PATH"
    exit 1
fi

APP_DIR="$ROOT_DIR/dist/$APP_NAME.app/Contents"
rm -rf "$ROOT_DIR/dist/$APP_NAME.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp "$BIN_PATH" "$APP_DIR/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Info.plist"

echo "Built: $ROOT_DIR/dist/$APP_NAME.app"
```

- [ ] **Step 5: Create test fixtures directory**

Create empty directory: `Tests/MaitricsCoreTests/Fixtures/.gitkeep`

- [ ] **Step 6: Verify everything builds and tests pass**

Run: `cd /Users/berke.altiparmak/Documents/maitrics && swift build 2>&1`
Expected: Build succeeds

Run: `swift test 2>&1`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ Tests/ Resources/ Scripts/
git commit -m "scaffold swift package with core library and app targets"
```

---

### Task 2: Stats Cache JSON Parsing

**Files:**
- Create: `Sources/MaitricsCore/Models/StatsCache.swift`
- Create: `Sources/MaitricsCore/Services/StatsCacheParser.swift`
- Create: `Tests/MaitricsCoreTests/Fixtures/stats-cache-sample.json`
- Create: `Tests/MaitricsCoreTests/StatsCacheParserTests.swift`

- [ ] **Step 1: Create test fixture**

`Tests/MaitricsCoreTests/Fixtures/stats-cache-sample.json`:
```json
{
  "version": 3,
  "lastComputedDate": "2026-04-02",
  "dailyActivity": [
    {
      "date": "2026-04-01",
      "messageCount": 1933,
      "sessionCount": 10,
      "toolCallCount": 1517
    },
    {
      "date": "2026-04-02",
      "messageCount": 561,
      "sessionCount": 6,
      "toolCallCount": 267
    }
  ],
  "dailyModelTokens": [
    {
      "date": "2026-04-01",
      "tokensByModel": {
        "claude-opus-4-6": 476675,
        "claude-haiku-4-5-20251001": 37935,
        "claude-sonnet-4-6": 3124
      }
    },
    {
      "date": "2026-04-02",
      "tokensByModel": {
        "claude-opus-4-6": 111654,
        "claude-haiku-4-5-20251001": 8400
      }
    }
  ],
  "modelUsage": {
    "claude-opus-4-6": {
      "inputTokens": 120336,
      "outputTokens": 1840890,
      "cacheReadInputTokens": 576163042,
      "cacheCreationInputTokens": 19075958,
      "webSearchRequests": 0,
      "costUSD": 0,
      "contextWindow": 0,
      "maxOutputTokens": 0
    },
    "claude-sonnet-4-6": {
      "inputTokens": 140001,
      "outputTokens": 918073,
      "cacheReadInputTokens": 432996931,
      "cacheCreationInputTokens": 12989932,
      "webSearchRequests": 0,
      "costUSD": 0,
      "contextWindow": 0,
      "maxOutputTokens": 0
    },
    "claude-haiku-4-5-20251001": {
      "inputTokens": 260663,
      "outputTokens": 449526,
      "cacheReadInputTokens": 146671351,
      "cacheCreationInputTokens": 12888052,
      "webSearchRequests": 0,
      "costUSD": 0,
      "contextWindow": 0,
      "maxOutputTokens": 0
    }
  },
  "totalSessions": 82,
  "totalMessages": 14523,
  "longestSession": {
    "sessionId": "be6fc71f-3f67-4c0f-b6b3-5c42169ea4fe",
    "duration": 1061798321,
    "messageCount": 309,
    "timestamp": "2026-02-04T08:19:04.872Z"
  },
  "firstSessionDate": "2026-01-30T08:46:24.450Z",
  "hourCounts": {
    "9": 3,
    "10": 10,
    "11": 20,
    "12": 24,
    "13": 5
  },
  "totalSpeculationTimeSavedMs": 0
}
```

- [ ] **Step 2: Write failing tests**

`Tests/MaitricsCoreTests/StatsCacheParserTests.swift`:
```swift
import XCTest
@testable import MaitricsCore

final class StatsCacheParserTests: XCTestCase {
    var fixtureData: Data!

    override func setUp() {
        let url = Bundle.module.url(forResource: "stats-cache-sample", withExtension: "json", subdirectory: "Fixtures")!
        fixtureData = try! Data(contentsOf: url)
    }

    func testParsesTopLevelFields() throws {
        let cache = try StatsCacheParser.parse(data: fixtureData)
        XCTAssertEqual(cache.version, 3)
        XCTAssertEqual(cache.totalSessions, 82)
        XCTAssertEqual(cache.totalMessages, 14523)
        XCTAssertEqual(cache.lastComputedDate, "2026-04-02")
    }

    func testParsesDailyActivity() throws {
        let cache = try StatsCacheParser.parse(data: fixtureData)
        XCTAssertEqual(cache.dailyActivity.count, 2)
        let day1 = cache.dailyActivity[0]
        XCTAssertEqual(day1.date, "2026-04-01")
        XCTAssertEqual(day1.messageCount, 1933)
        XCTAssertEqual(day1.sessionCount, 10)
        XCTAssertEqual(day1.toolCallCount, 1517)
    }

    func testParsesDailyModelTokens() throws {
        let cache = try StatsCacheParser.parse(data: fixtureData)
        XCTAssertEqual(cache.dailyModelTokens.count, 2)
        let day1 = cache.dailyModelTokens[0]
        XCTAssertEqual(day1.tokensByModel["claude-opus-4-6"], 476675)
        XCTAssertEqual(day1.tokensByModel["claude-sonnet-4-6"], 3124)
    }

    func testParsesModelUsage() throws {
        let cache = try StatsCacheParser.parse(data: fixtureData)
        let opus = cache.modelUsage["claude-opus-4-6"]!
        XCTAssertEqual(opus.inputTokens, 120336)
        XCTAssertEqual(opus.outputTokens, 1840890)
        XCTAssertEqual(opus.cacheReadInputTokens, 576163042)
        XCTAssertEqual(opus.cacheCreationInputTokens, 19075958)
    }

    func testParsesFromFilePath() throws {
        let url = Bundle.module.url(forResource: "stats-cache-sample", withExtension: "json", subdirectory: "Fixtures")!
        let cache = try StatsCacheParser.parse(fileURL: url)
        XCTAssertEqual(cache.totalSessions, 82)
    }

    func testReturnsNilForMissingFile() {
        let result = try? StatsCacheParser.parse(fileURL: URL(fileURLWithPath: "/nonexistent/path.json"))
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter StatsCacheParserTests 2>&1`
Expected: compilation error — `StatsCacheParser` not defined

- [ ] **Step 4: Implement StatsCache models**

`Sources/MaitricsCore/Models/StatsCache.swift`:
```swift
import Foundation

public struct StatsCache: Codable, Sendable {
    public let version: Int
    public let lastComputedDate: String
    public let dailyActivity: [DailyActivity]
    public let dailyModelTokens: [DailyModelTokens]
    public let modelUsage: [String: ModelUsage]
    public let totalSessions: Int
    public let totalMessages: Int
    public let longestSession: LongestSession?
    public let firstSessionDate: String?
    public let hourCounts: [String: Int]?
}

public struct DailyActivity: Codable, Sendable {
    public let date: String
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int
}

public struct DailyModelTokens: Codable, Sendable {
    public let date: String
    public let tokensByModel: [String: Int]
}

public struct ModelUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int
    public let webSearchRequests: Int?
    public let costUSD: Double?

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }
}

public struct LongestSession: Codable, Sendable {
    public let sessionId: String
    public let duration: Int
    public let messageCount: Int
    public let timestamp: String
}
```

- [ ] **Step 5: Implement StatsCacheParser**

`Sources/MaitricsCore/Services/StatsCacheParser.swift`:
```swift
import Foundation

public enum StatsCacheParser {
    public static func parse(data: Data) throws -> StatsCache {
        let decoder = JSONDecoder()
        return try decoder.decode(StatsCache.self, from: data)
    }

    public static func parse(fileURL: URL) throws -> StatsCache {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter StatsCacheParserTests 2>&1`
Expected: `Test Suite 'StatsCacheParserTests' passed`

- [ ] **Step 7: Remove placeholder MaitricsCore.swift and commit**

Delete `Sources/MaitricsCore/MaitricsCore.swift` (no longer needed). Update placeholder test in `MaitricsCoreTests.swift` to remove the version test since we deleted that file.

```bash
git add Sources/MaitricsCore/ Tests/MaitricsCoreTests/
git commit -m "add stats cache JSON parsing with tests"
```

---

### Task 3: Session Discovery & Index Parsing

**Files:**
- Create: `Sources/MaitricsCore/Models/SessionIndex.swift`
- Create: `Sources/MaitricsCore/Services/SessionDiscovery.swift`
- Create: `Tests/MaitricsCoreTests/Fixtures/sessions-index-sample.json`
- Create: `Tests/MaitricsCoreTests/SessionDiscoveryTests.swift`

- [ ] **Step 1: Create test fixture**

`Tests/MaitricsCoreTests/Fixtures/sessions-index-sample.json`:
```json
{
  "version": 1,
  "entries": [
    {
      "sessionId": "96176827-8c1f-4081-ba5e-137450a7e4f9",
      "fullPath": "/Users/test/.claude/projects/-test-project/96176827.jsonl",
      "fileMtime": 1769766980209,
      "firstPrompt": "Fix authentication bug in login flow",
      "messageCount": 42,
      "created": "2026-04-01T09:55:16.704Z",
      "modified": "2026-04-01T10:56:20.184Z",
      "gitBranch": "main",
      "projectPath": "/Users/test/project",
      "isSidechain": false
    },
    {
      "sessionId": "aaaa1111-2222-3333-4444-555566667777",
      "fullPath": "/Users/test/.claude/projects/-test-project/aaaa1111.jsonl",
      "fileMtime": 1769766000000,
      "firstPrompt": "Add dark mode support to dashboard",
      "messageCount": 15,
      "created": "2026-04-01T14:00:00.000Z",
      "modified": "2026-04-01T14:30:00.000Z",
      "gitBranch": "feat/dark-mode",
      "projectPath": "/Users/test/project",
      "isSidechain": false
    }
  ],
  "originalPath": "/Users/test/project"
}
```

- [ ] **Step 2: Write failing tests**

`Tests/MaitricsCoreTests/SessionDiscoveryTests.swift`:
```swift
import XCTest
@testable import MaitricsCore

final class SessionDiscoveryTests: XCTestCase {
    func testParsesSessionIndex() throws {
        let url = Bundle.module.url(forResource: "sessions-index-sample", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let index = try SessionDiscovery.parseIndex(data: data)
        XCTAssertEqual(index.entries.count, 2)

        let first = index.entries[0]
        XCTAssertEqual(first.sessionId, "96176827-8c1f-4081-ba5e-137450a7e4f9")
        XCTAssertEqual(first.firstPrompt, "Fix authentication bug in login flow")
        XCTAssertEqual(first.messageCount, 42)
        XCTAssertEqual(first.gitBranch, "main")
        XCTAssertEqual(first.projectPath, "/Users/test/project")
    }

    func testDecodeProjectNameFromPath() {
        let encoded = "-Users-berke-Documents-my-project"
        let name = SessionDiscovery.projectName(fromEncodedPath: encoded)
        XCTAssertEqual(name, "my-project")
    }

    func testDecodeProjectNameFallback() {
        let simple = "some-project"
        let name = SessionDiscovery.projectName(fromEncodedPath: simple)
        XCTAssertEqual(name, "some-project")
    }

    func testDiscoverSessionsFromTempDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectDir = tmpDir.appendingPathComponent("-Users-test-Documents-myapp")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Write a sessions-index.json
        let indexJSON = """
        {
          "version": 1,
          "entries": [{
            "sessionId": "abc-123",
            "fullPath": "\(projectDir.path)/abc-123.jsonl",
            "fileMtime": 1700000000000,
            "firstPrompt": "test prompt",
            "messageCount": 5,
            "created": "2026-04-01T10:00:00.000Z",
            "modified": "2026-04-01T10:30:00.000Z",
            "gitBranch": "main",
            "projectPath": "/Users/test/Documents/myapp",
            "isSidechain": false
          }],
          "originalPath": "/Users/test/Documents/myapp"
        }
        """
        try indexJSON.write(to: projectDir.appendingPathComponent("sessions-index.json"), atomically: true, encoding: .utf8)

        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: tmpDir)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].firstPrompt, "test prompt")
        XCTAssertEqual(sessions[0].projectName, "myapp")

        try FileManager.default.removeItem(at: tmpDir)
    }

    func testDiscoverSessionsFromJSONLFiles() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectDir = tmpDir.appendingPathComponent("-Users-test-Documents-another")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // No sessions-index.json, just a JSONL file
        let jsonl = """
        {"type":"user","message":{"content":"help me with tests"},"uuid":"1","timestamp":"2026-04-02T08:00:00Z"}
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"uuid":"2","timestamp":"2026-04-02T08:01:00Z"}
        """
        let jsonlPath = projectDir.appendingPathComponent("def-456.jsonl")
        try jsonl.write(to: jsonlPath, atomically: true, encoding: .utf8)

        let sessions = try SessionDiscovery.discoverSessions(claudeProjectsDir: tmpDir)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "def-456")
        XCTAssertEqual(sessions[0].projectName, "another")

        try FileManager.default.removeItem(at: tmpDir)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter SessionDiscoveryTests 2>&1`
Expected: compilation error — types not defined

- [ ] **Step 4: Implement SessionIndex models**

`Sources/MaitricsCore/Models/SessionIndex.swift`:
```swift
import Foundation

public struct SessionIndex: Codable, Sendable {
    public let version: Int
    public let entries: [SessionIndexEntry]
    public let originalPath: String?
}

public struct SessionIndexEntry: Codable, Sendable {
    public let sessionId: String
    public let fullPath: String
    public let fileMtime: Int64?
    public let firstPrompt: String
    public let messageCount: Int
    public let created: String
    public let modified: String
    public let gitBranch: String?
    public let projectPath: String?
    public let isSidechain: Bool?
}

/// Unified session info returned by discovery — from either index or JSONL scan
public struct DiscoveredSession: Sendable {
    public let sessionId: String
    public let firstPrompt: String
    public let messageCount: Int
    public let created: Date
    public let modified: Date
    public let gitBranch: String?
    public let projectPath: String?
    public let projectName: String
    public let jsonlPath: String?
}
```

- [ ] **Step 5: Implement SessionDiscovery**

`Sources/MaitricsCore/Services/SessionDiscovery.swift`:
```swift
import Foundation

public enum SessionDiscovery {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date {
        isoFormatter.date(from: string)
            ?? isoFormatterNoFrac.date(from: string)
            ?? Date.distantPast
    }

    public static func parseIndex(data: Data) throws -> SessionIndex {
        try JSONDecoder().decode(SessionIndex.self, from: data)
    }

    public static func projectName(fromEncodedPath encoded: String) -> String {
        // Encoded paths look like "-Users-berke-Documents-my-project"
        // We want the last path component: split by the OS path separators encoded as dashes
        // Strategy: the original path was something like /Users/berke/Documents/my-project
        // Encoded as -Users-berke-Documents-my-project
        // We take everything after the last known directory separator pattern
        let parts = encoded.split(separator: "-", omittingEmptySubsequences: true)
        // Find "Documents" or similar well-known dirs as anchor, take everything after
        if let docsIndex = parts.lastIndex(where: { $0 == "Documents" || $0 == "Desktop" || $0 == "repos" || $0 == "projects" || $0 == "code" || $0 == "src" || $0 == "dev" || $0 == "home" }) {
            let remaining = parts[(docsIndex + 1)...]
            if !remaining.isEmpty {
                return remaining.joined(separator: "-")
            }
        }
        // Fallback: return last component
        return parts.last.map(String.init) ?? encoded
    }

    public static func discoverSessions(claudeProjectsDir: URL) throws -> [DiscoveredSession] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeProjectsDir.path) else { return [] }

        let projectDirs = try fm.contentsOfDirectory(at: claudeProjectsDir, includingPropertiesForKeys: nil)
            .filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }

        var sessions: [DiscoveredSession] = []

        for projectDir in projectDirs {
            let encodedName = projectDir.lastPathComponent
            let name = projectName(fromEncodedPath: encodedName)
            let indexFile = projectDir.appendingPathComponent("sessions-index.json")

            if fm.fileExists(atPath: indexFile.path),
               let data = try? Data(contentsOf: indexFile),
               let index = try? parseIndex(data: data) {
                // Use sessions-index.json
                for entry in index.entries where entry.isSidechain != true {
                    sessions.append(DiscoveredSession(
                        sessionId: entry.sessionId,
                        firstPrompt: cleanPrompt(entry.firstPrompt),
                        messageCount: entry.messageCount,
                        created: parseDate(entry.created),
                        modified: parseDate(entry.modified),
                        gitBranch: entry.gitBranch,
                        projectPath: entry.projectPath,
                        projectName: name,
                        jsonlPath: entry.fullPath
                    ))
                }
            } else {
                // Fallback: scan for JSONL files directly in the project dir
                let jsonlFiles = (try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]))?.filter { $0.pathExtension == "jsonl" } ?? []

                for jsonlFile in jsonlFiles {
                    let sessionId = jsonlFile.deletingPathExtension().lastPathComponent
                    let attrs = try? fm.attributesOfItem(atPath: jsonlFile.path)
                    let modified = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                    let created = (attrs?[.creationDate] as? Date) ?? modified
                    let prompt = extractFirstPrompt(from: jsonlFile)

                    sessions.append(DiscoveredSession(
                        sessionId: sessionId,
                        firstPrompt: prompt ?? sessionId,
                        messageCount: 0,
                        created: created,
                        modified: modified,
                        gitBranch: nil,
                        projectPath: nil,
                        projectName: name,
                        jsonlPath: jsonlFile.path
                    ))
                }
            }
        }

        sessions.sort { $0.modified > $1.modified }
        return sessions
    }

    private static func cleanPrompt(_ prompt: String) -> String {
        // Remove IDE-injected prefixes like "<ide_opened_file>..."
        if prompt.hasPrefix("<") {
            // Find the end of the tag content and use the actual user text
            if let range = prompt.range(of: "This may or may not be related to the current") {
                let afterTag = prompt[range.upperBound...]
                let trimmed = afterTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "…"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "IDE session" : trimmed
            }
            return "IDE session"
        }
        // Truncate long prompts
        if prompt.count > 100 {
            return String(prompt.prefix(100))
        }
        return prompt
    }

    private static func extractFirstPrompt(from jsonlFile: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: jsonlFile) else { return nil }
        defer { handle.closeFile() }

        // Read first 8KB to find the first user message
        let chunk = handle.readData(ofLength: 8192)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }

        for line in text.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "user",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                continue
            }
            return cleanPrompt(content)
        }
        return nil
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter SessionDiscoveryTests 2>&1`
Expected: `Test Suite 'SessionDiscoveryTests' passed`

- [ ] **Step 7: Commit**

```bash
git add Sources/MaitricsCore/Models/SessionIndex.swift Sources/MaitricsCore/Services/SessionDiscovery.swift Tests/MaitricsCoreTests/
git commit -m "add session discovery with index parsing and JSONL fallback"
```

---

### Task 4: Session JSONL Parsing for Token Usage

**Files:**
- Create: `Sources/MaitricsCore/Models/SessionTokenUsage.swift`
- Create: `Sources/MaitricsCore/Services/SessionParser.swift`
- Create: `Tests/MaitricsCoreTests/Fixtures/session-sample.jsonl`
- Create: `Tests/MaitricsCoreTests/SessionParserTests.swift`

- [ ] **Step 1: Create test fixture**

`Tests/MaitricsCoreTests/Fixtures/session-sample.jsonl`:
```
{"type":"permission-mode","permissionMode":"default","sessionId":"test-session"}
{"type":"user","message":{"content":"Fix the login bug"},"uuid":"u1","timestamp":"2026-04-01T10:00:00Z"}
{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":100,"output_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":5000,"server_tool_use":{"web_search_requests":0},"service_tier":"standard"}},"uuid":"a1","timestamp":"2026-04-01T10:00:05Z"}
{"type":"user","message":{"content":"Now add tests"},"uuid":"u2","timestamp":"2026-04-01T10:01:00Z"}
{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":200,"output_tokens":800,"cache_creation_input_tokens":1000,"cache_read_input_tokens":8000,"server_tool_use":{"web_search_requests":0},"service_tier":"standard"}},"uuid":"a2","timestamp":"2026-04-01T10:01:10Z"}
{"type":"user","message":{"content":"Looks good, thanks"},"uuid":"u3","timestamp":"2026-04-01T10:02:00Z"}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","usage":{"input_tokens":50,"output_tokens":100,"cache_creation_input_tokens":500,"cache_read_input_tokens":3000,"server_tool_use":{"web_search_requests":0},"service_tier":"standard"}},"uuid":"a3","timestamp":"2026-04-01T10:02:05Z"}
```

- [ ] **Step 2: Write failing tests**

`Tests/MaitricsCoreTests/SessionParserTests.swift`:
```swift
import XCTest
@testable import MaitricsCore

final class SessionParserTests: XCTestCase {
    func testParsesSessionTokenUsage() throws {
        let url = Bundle.module.url(forResource: "session-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let usage = try SessionParser.parseTokenUsage(fileURL: url)

        // Two opus messages: (100+200) input, (500+800) output, (2000+1000) cacheWrite, (5000+8000) cacheRead
        // One haiku message: 50 input, 100 output, 500 cacheWrite, 3000 cacheRead
        XCTAssertEqual(usage.byModel.count, 2)

        let opus = usage.byModel["claude-opus-4-6"]!
        XCTAssertEqual(opus.inputTokens, 300)
        XCTAssertEqual(opus.outputTokens, 1300)
        XCTAssertEqual(opus.cacheCreationInputTokens, 3000)
        XCTAssertEqual(opus.cacheReadInputTokens, 13000)

        let haiku = usage.byModel["claude-haiku-4-5-20251001"]!
        XCTAssertEqual(haiku.inputTokens, 50)
        XCTAssertEqual(haiku.outputTokens, 100)
    }

    func testTotalTokensAcrossModels() throws {
        let url = Bundle.module.url(forResource: "session-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let usage = try SessionParser.parseTokenUsage(fileURL: url)

        // Total input: 300 + 50 = 350
        // Total output: 1300 + 100 = 1400
        XCTAssertEqual(usage.totalInputTokens, 350)
        XCTAssertEqual(usage.totalOutputTokens, 1400)
    }

    func testReturnsEmptyForMissingFile() {
        let usage = try? SessionParser.parseTokenUsage(fileURL: URL(fileURLWithPath: "/nonexistent.jsonl"))
        XCTAssertNil(usage)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter SessionParserTests 2>&1`
Expected: compilation error — types not defined

- [ ] **Step 4: Implement models and parser**

`Sources/MaitricsCore/Models/SessionTokenUsage.swift`:
```swift
import Foundation

public struct SessionTokenUsage: Sendable {
    public let byModel: [String: ModelTokens]

    public var totalInputTokens: Int {
        byModel.values.reduce(0) { $0 + $1.inputTokens }
    }
    public var totalOutputTokens: Int {
        byModel.values.reduce(0) { $0 + $1.outputTokens }
    }
    public var totalCacheReadTokens: Int {
        byModel.values.reduce(0) { $0 + $1.cacheReadInputTokens }
    }
    public var totalCacheWriteTokens: Int {
        byModel.values.reduce(0) { $0 + $1.cacheCreationInputTokens }
    }
    public var totalTokens: Int {
        byModel.values.reduce(0) { $0 + $1.totalTokens }
    }
}

public struct ModelTokens: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    public static let zero = ModelTokens(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
}
```

`Sources/MaitricsCore/Services/SessionParser.swift`:
```swift
import Foundation

public enum SessionParser {
    public static func parseTokenUsage(fileURL: URL) throws -> SessionTokenUsage {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            return SessionTokenUsage(byModel: [:])
        }

        var byModel: [String: ModelTokens] = [:]

        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }

            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

            var existing = byModel[model] ?? .zero
            existing.inputTokens += input
            existing.outputTokens += output
            existing.cacheCreationInputTokens += cacheWrite
            existing.cacheReadInputTokens += cacheRead
            byModel[model] = existing
        }

        return SessionTokenUsage(byModel: byModel)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionParserTests 2>&1`
Expected: `Test Suite 'SessionParserTests' passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/MaitricsCore/Models/SessionTokenUsage.swift Sources/MaitricsCore/Services/SessionParser.swift Tests/MaitricsCoreTests/
git commit -m "add session JSONL parser for per-session token usage"
```

---

### Task 5: Cost Calculator

**Files:**
- Create: `Sources/MaitricsCore/Services/CostCalculator.swift`
- Create: `Tests/MaitricsCoreTests/CostCalculatorTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/MaitricsCoreTests/CostCalculatorTests.swift`:
```swift
import XCTest
@testable import MaitricsCore

final class CostCalculatorTests: XCTestCase {
    func testOpusCostCalculation() {
        let usage = ModelUsage(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadInputTokens: 1_000_000,
            cacheCreationInputTokens: 1_000_000,
            webSearchRequests: 0,
            costUSD: 0
        )
        let cost = CostCalculator.cost(for: usage, model: "claude-opus-4-6")
        // $15 input + $75 output + $1.50 cache read + $18.75 cache write = $110.25
        XCTAssertEqual(cost, 110.25, accuracy: 0.01)
    }

    func testSonnetCostCalculation() {
        let usage = ModelUsage(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadInputTokens: 1_000_000,
            cacheCreationInputTokens: 1_000_000,
            webSearchRequests: 0,
            costUSD: 0
        )
        let cost = CostCalculator.cost(for: usage, model: "claude-sonnet-4-6")
        // $3 + $15 + $0.30 + $3.75 = $22.05
        XCTAssertEqual(cost, 22.05, accuracy: 0.01)
    }

    func testHaikuCostCalculation() {
        let usage = ModelUsage(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadInputTokens: 1_000_000,
            cacheCreationInputTokens: 1_000_000,
            webSearchRequests: 0,
            costUSD: 0
        )
        let cost = CostCalculator.cost(for: usage, model: "claude-haiku-4-5-20251001")
        // $0.80 + $4 + $0.08 + $1.00 = $5.88
        XCTAssertEqual(cost, 5.88, accuracy: 0.01)
    }

    func testUnknownModelUsesDefaultPricing() {
        let usage = ModelUsage(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            webSearchRequests: 0,
            costUSD: 0
        )
        let cost = CostCalculator.cost(for: usage, model: "claude-unknown-99")
        // Falls back to Sonnet pricing: $3 + $15 = $18
        XCTAssertEqual(cost, 18.0, accuracy: 0.01)
    }

    func testTotalCostFromModelUsageDict() {
        let usage: [String: ModelUsage] = [
            "claude-opus-4-6": ModelUsage(
                inputTokens: 100_000, outputTokens: 100_000,
                cacheReadInputTokens: 0, cacheCreationInputTokens: 0,
                webSearchRequests: 0, costUSD: 0
            ),
            "claude-haiku-4-5-20251001": ModelUsage(
                inputTokens: 100_000, outputTokens: 100_000,
                cacheReadInputTokens: 0, cacheCreationInputTokens: 0,
                webSearchRequests: 0, costUSD: 0
            ),
        ]
        let total = CostCalculator.totalCost(modelUsage: usage)
        // Opus: (0.1 * $15) + (0.1 * $75) = $1.50 + $7.50 = $9.00
        // Haiku: (0.1 * $0.80) + (0.1 * $4) = $0.08 + $0.40 = $0.48
        // Total: $9.48
        XCTAssertEqual(total, 9.48, accuracy: 0.01)
    }

    func testCostFromSessionTokenUsage() {
        let session = SessionTokenUsage(byModel: [
            "claude-opus-4-6": ModelTokens(
                inputTokens: 300, outputTokens: 1300,
                cacheReadInputTokens: 13000, cacheCreationInputTokens: 3000
            )
        ])
        let cost = CostCalculator.cost(for: session)
        // (300/1M * 15) + (1300/1M * 75) + (13000/1M * 1.5) + (3000/1M * 18.75)
        // = 0.0045 + 0.0975 + 0.0195 + 0.05625 = 0.17775
        XCTAssertEqual(cost, 0.17775, accuracy: 0.001)
    }

    func testCustomPricingOverride() {
        let pricing = PricingTier(inputPer1M: 100, outputPer1M: 200, cacheReadPer1M: 10, cacheWritePer1M: 50)
        let usage = ModelUsage(
            inputTokens: 1_000_000, outputTokens: 1_000_000,
            cacheReadInputTokens: 0, cacheCreationInputTokens: 0,
            webSearchRequests: 0, costUSD: 0
        )
        let cost = CostCalculator.cost(for: usage, pricing: pricing)
        XCTAssertEqual(cost, 300.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CostCalculatorTests 2>&1`
Expected: compilation error

- [ ] **Step 3: Implement CostCalculator**

`Sources/MaitricsCore/Services/CostCalculator.swift`:
```swift
import Foundation

public struct PricingTier: Codable, Sendable {
    public var inputPer1M: Double
    public var outputPer1M: Double
    public var cacheReadPer1M: Double
    public var cacheWritePer1M: Double

    public init(inputPer1M: Double, outputPer1M: Double, cacheReadPer1M: Double, cacheWritePer1M: Double) {
        self.inputPer1M = inputPer1M
        self.outputPer1M = outputPer1M
        self.cacheReadPer1M = cacheReadPer1M
        self.cacheWritePer1M = cacheWritePer1M
    }
}

public enum CostCalculator {
    public static let defaultPricing: [String: PricingTier] = [
        "opus": PricingTier(inputPer1M: 15, outputPer1M: 75, cacheReadPer1M: 1.5, cacheWritePer1M: 18.75),
        "sonnet": PricingTier(inputPer1M: 3, outputPer1M: 15, cacheReadPer1M: 0.3, cacheWritePer1M: 3.75),
        "haiku": PricingTier(inputPer1M: 0.8, outputPer1M: 4, cacheReadPer1M: 0.08, cacheWritePer1M: 1.0),
    ]

    public static func modelFamily(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower.contains("opus") { return "opus" }
        if lower.contains("haiku") { return "haiku" }
        return "sonnet" // default fallback
    }

    public static func pricing(for modelId: String, customPricing: [String: PricingTier]? = nil) -> PricingTier {
        let family = modelFamily(modelId)
        return customPricing?[family] ?? defaultPricing[family] ?? defaultPricing["sonnet"]!
    }

    public static func cost(for usage: ModelUsage, model: String, customPricing: [String: PricingTier]? = nil) -> Double {
        let p = pricing(for: model, customPricing: customPricing)
        return cost(for: usage, pricing: p)
    }

    public static func cost(for usage: ModelUsage, pricing p: PricingTier) -> Double {
        let scale = 1_000_000.0
        return (Double(usage.inputTokens) / scale * p.inputPer1M)
             + (Double(usage.outputTokens) / scale * p.outputPer1M)
             + (Double(usage.cacheReadInputTokens) / scale * p.cacheReadPer1M)
             + (Double(usage.cacheCreationInputTokens) / scale * p.cacheWritePer1M)
    }

    public static func totalCost(modelUsage: [String: ModelUsage], customPricing: [String: PricingTier]? = nil) -> Double {
        modelUsage.reduce(0.0) { total, pair in
            total + cost(for: pair.value, model: pair.key, customPricing: customPricing)
        }
    }

    public static func cost(for session: SessionTokenUsage, customPricing: [String: PricingTier]? = nil) -> Double {
        session.byModel.reduce(0.0) { total, pair in
            let p = pricing(for: pair.key, customPricing: customPricing)
            let tokens = pair.value
            let scale = 1_000_000.0
            return total
                + (Double(tokens.inputTokens) / scale * p.inputPer1M)
                + (Double(tokens.outputTokens) / scale * p.outputPer1M)
                + (Double(tokens.cacheReadInputTokens) / scale * p.cacheReadPer1M)
                + (Double(tokens.cacheCreationInputTokens) / scale * p.cacheWritePer1M)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CostCalculatorTests 2>&1`
Expected: `Test Suite 'CostCalculatorTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/MaitricsCore/Services/CostCalculator.swift Tests/MaitricsCoreTests/CostCalculatorTests.swift
git commit -m "add cost calculator with per-model pricing"
```

---

### Task 6: App Settings & Formatting Utilities

**Files:**
- Create: `Sources/MaitricsCore/Models/AppSettings.swift`
- Create: `Sources/MaitricsCore/Utilities/Formatting.swift`

- [ ] **Step 1: Implement AppSettings**

`Sources/MaitricsCore/Models/AppSettings.swift`:
```swift
import Foundation

public final class AppSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Thresholds (token counts)
    public var thresholdGreen: Int {
        get { defaults.object(forKey: "thresholdGreen") as? Int ?? 100_000 }
        set { defaults.set(newValue, forKey: "thresholdGreen") }
    }

    public var thresholdYellow: Int {
        get { defaults.object(forKey: "thresholdYellow") as? Int ?? 500_000 }
        set { defaults.set(newValue, forKey: "thresholdYellow") }
    }

    // MARK: - Claude data path
    public var claudeDataPath: String {
        get { defaults.string(forKey: "claudeDataPath") ?? defaultClaudePath }
        set { defaults.set(newValue, forKey: "claudeDataPath") }
    }

    public var claudeDataURL: URL {
        URL(fileURLWithPath: (claudeDataPath as NSString).expandingTildeInPath)
    }

    public var statsCachePath: URL {
        claudeDataURL.appendingPathComponent("stats-cache.json")
    }

    public var projectsPath: URL {
        claudeDataURL.appendingPathComponent("projects")
    }

    // MARK: - Custom Pricing (stored as JSON in UserDefaults)
    public var customPricing: [String: PricingTier]? {
        get {
            guard let data = defaults.data(forKey: "customPricing") else { return nil }
            return try? JSONDecoder().decode([String: PricingTier].self, from: data)
        }
        set {
            if let newValue {
                let data = try? JSONEncoder().encode(newValue)
                defaults.set(data, forKey: "customPricing")
            } else {
                defaults.removeObject(forKey: "customPricing")
            }
        }
    }

    // MARK: - Launch at Login
    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    private var defaultClaudePath: String {
        NSHomeDirectory() + "/.claude"
    }
}
```

- [ ] **Step 2: Implement Formatting utilities**

`Sources/MaitricsCore/Utilities/Formatting.swift`:
```swift
import Foundation

public enum Formatting {
    public static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000.0
            return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        } else if count >= 1_000 {
            let k = Double(count) / 1_000.0
            return k >= 10 ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
        }
        return "\(count)"
    }

    public static func cost(_ amount: Double) -> String {
        if amount >= 100 {
            return String(format: "$%.0f", amount)
        } else if amount >= 1 {
            return String(format: "$%.2f", amount)
        } else if amount >= 0.01 {
            return String(format: "$%.2f", amount)
        } else if amount > 0 {
            return "<$0.01"
        }
        return "$0.00"
    }

    public static func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    public static func shortModelName(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return modelId
    }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/MaitricsCore/Models/AppSettings.swift Sources/MaitricsCore/Utilities/Formatting.swift
git commit -m "add app settings and formatting utilities"
```

---

### Task 7: ClaudeDataManager

**Files:**
- Create: `Sources/MaitricsCore/Services/ClaudeDataManager.swift`

- [ ] **Step 1: Implement ClaudeDataManager**

`Sources/MaitricsCore/Services/ClaudeDataManager.swift`:
```swift
import Foundation

@Observable
public final class ClaudeDataManager {
    // MARK: - Published State
    public private(set) var statsCache: StatsCache?
    public private(set) var recentSessions: [RecentSession] = []
    public private(set) var lastRefresh: Date?
    public private(set) var isLoading = false
    public private(set) var error: String?

    private let settings: AppSettings

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    // MARK: - Computed Properties

    public var todayTokens: Int {
        todayModelTokens.values.reduce(0, +)
    }

    public var todayModelTokens: [String: Int] {
        guard let statsCache else { return [:] }
        let todayStr = Self.dateString(for: Date())
        return statsCache.dailyModelTokens.first { $0.date == todayStr }?.tokensByModel ?? [:]
    }

    public var todayActivity: DailyActivity? {
        guard let statsCache else { return nil }
        let todayStr = Self.dateString(for: Date())
        return statsCache.dailyActivity.first { $0.date == todayStr }
    }

    public var todayEstimatedCost: Double {
        guard let statsCache else { return 0 }
        // Use overall model usage ratios to estimate daily cost from daily token totals
        return estimateDailyCost(dailyTokens: todayModelTokens, modelUsage: statsCache.modelUsage)
    }

    public var modelBreakdown: [(name: String, tokens: Int, color: String)] {
        let grouped = groupByFamily(todayModelTokens)
        return grouped.sorted { $0.value > $1.value }.map { family, tokens in
            let color: String
            switch family {
            case "Opus": color = "orange"
            case "Haiku": color = "purple"
            default: color = "blue"
            }
            return (name: family, tokens: tokens, color: color)
        }
    }

    /// Returns daily token totals for the given range, sorted by date ascending
    public func dailyTotals(days: Int?) -> [(date: Date, tokens: Int)] {
        guard let statsCache else { return [] }
        let formatter = Self.dateFormatter

        var results: [(date: Date, tokens: Int)] = statsCache.dailyModelTokens.compactMap { day in
            guard let date = formatter.date(from: day.date) else { return nil }
            let total = day.tokensByModel.values.reduce(0, +)
            return (date: date, tokens: total)
        }
        results.sort { $0.date < $1.date }

        if let days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
            results = results.filter { $0.date >= cutoff }
        }
        return results
    }

    public var iconThresholdLevel: ThresholdLevel {
        let tokens = todayTokens
        if tokens >= settings.thresholdYellow { return .red }
        if tokens >= settings.thresholdGreen { return .yellow }
        return .green
    }

    // MARK: - Refresh

    public func refresh() {
        isLoading = true
        error = nil

        // Parse stats cache
        do {
            statsCache = try StatsCacheParser.parse(fileURL: settings.statsCachePath)
        } catch {
            if FileManager.default.fileExists(atPath: settings.statsCachePath.path) {
                self.error = "Failed to parse stats: \(error.localizedDescription)"
            }
            // If file doesn't exist, statsCache stays nil — empty state
        }

        // Discover recent sessions
        do {
            let discovered = try SessionDiscovery.discoverSessions(claudeProjectsDir: settings.projectsPath)
            let topSessions = Array(discovered.prefix(5))

            recentSessions = topSessions.map { session in
                var tokenUsage: SessionTokenUsage?
                if let path = session.jsonlPath {
                    tokenUsage = try? SessionParser.parseTokenUsage(fileURL: URL(fileURLWithPath: path))
                }
                let cost = tokenUsage.map { CostCalculator.cost(for: $0, customPricing: settings.customPricing) } ?? 0
                let totalTokens = tokenUsage?.totalTokens ?? 0

                return RecentSession(
                    sessionId: session.sessionId,
                    firstPrompt: session.firstPrompt,
                    projectName: session.projectName,
                    gitBranch: session.gitBranch,
                    modified: session.modified,
                    totalTokens: totalTokens,
                    estimatedCost: cost
                )
            }
        } catch {
            // Non-fatal — sessions list stays empty
        }

        lastRefresh = Date()
        isLoading = false
    }

    // MARK: - Helpers

    private func estimateDailyCost(dailyTokens: [String: Int], modelUsage: [String: ModelUsage]) -> Double {
        // For each model in daily tokens, compute cost using the aggregate usage ratios
        dailyTokens.reduce(0.0) { total, pair in
            let (modelId, dailyTotal) = pair
            guard dailyTotal > 0 else { return total }

            // If we have detailed usage for this model, use the ratios
            if let usage = modelUsage[modelId], usage.totalTokens > 0 {
                let scale = Double(dailyTotal) / Double(usage.totalTokens)
                return total + CostCalculator.cost(for: usage, model: modelId, customPricing: settings.customPricing) * scale
            }

            // Fallback: treat all as output tokens (worst-case estimate)
            let pricing = CostCalculator.pricing(for: modelId, customPricing: settings.customPricing)
            return total + Double(dailyTotal) / 1_000_000.0 * pricing.outputPer1M
        }
    }

    private func groupByFamily(_ tokensByModel: [String: Int]) -> [String: Int] {
        var grouped: [String: Int] = [:]
        for (modelId, tokens) in tokensByModel {
            let family = Formatting.shortModelName(modelId)
            grouped[family, default: 0] += tokens
        }
        return grouped
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

public enum ThresholdLevel: Sendable {
    case green, yellow, red
}

public struct RecentSession: Identifiable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let firstPrompt: String
    public let projectName: String
    public let gitBranch: String?
    public let modified: Date
    public let totalTokens: Int
    public let estimatedCost: Double
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/MaitricsCore/Services/ClaudeDataManager.swift
git commit -m "add claude data manager with refresh and computed stats"
```

---

### Task 8: FileWatcher

**Files:**
- Create: `Sources/MaitricsCore/Utilities/FileWatcher.swift`

- [ ] **Step 1: Implement FileWatcher**

`Sources/MaitricsCore/Utilities/FileWatcher.swift`:
```swift
import Foundation

public final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let onChange: () -> Void

    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        stop()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            // File doesn't exist yet — try parent directory
            startWatchingParent()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onChange()
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func startWatchingParent() {
        let parentPath = (path as NSString).deletingLastPathComponent
        fileDescriptor = open(parentPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Check if the target file appeared
            if FileManager.default.fileExists(atPath: self.path) {
                self.stop()
                self.start() // Restart watching the actual file
                self.onChange()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        self.source = source
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/MaitricsCore/Utilities/FileWatcher.swift
git commit -m "add file watcher using DispatchSource"
```

---

### Task 9: StatusBarController & App Entry Point

**Files:**
- Modify: `Sources/Maitrics/MaitricsApp.swift`
- Create: `Sources/Maitrics/StatusBarController.swift`

- [ ] **Step 1: Implement StatusBarController**

`Sources/Maitrics/StatusBarController.swift`:
```swift
import AppKit
import SwiftUI
import MaitricsCore

final class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var fileWatcher: FileWatcher?
    private var eventMonitor: Any?
    let dataManager: ClaudeDataManager
    let settings: AppSettings

    init() {
        self.settings = AppSettings()
        self.dataManager = ClaudeDataManager(settings: settings)

        setupStatusItem()
        setupPopover()
        setupFileWatcher()
        dataManager.refresh()
        updateIcon()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Maitrics")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 580)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                dataManager: dataManager,
                settings: settings,
                onSettingsOpen: { [weak self] in self?.openSettings() }
            )
        )
    }

    private func setupFileWatcher() {
        fileWatcher = FileWatcher(path: settings.statsCachePath.path) { [weak self] in
            self?.dataManager.refresh()
            self?.updateIcon()
        }
        fileWatcher?.start()
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }

        let color: NSColor
        switch dataManager.iconThresholdLevel {
        case .green: color = NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1) // #4ade80
        case .yellow: color = NSColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1) // #facc15
        case .red: color = NSColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1) // #f87171
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        var image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Maitrics")
        image = image?.withSymbolConfiguration(config)
        image?.isTemplate = false

        // Create tinted version
        let tinted = NSImage(size: image?.size ?? NSSize(width: 18, height: 18), flipped: false) { rect in
            image?.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        button.image = tinted
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            dataManager.refresh()
            updateIcon()
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            // Close popover when clicking outside
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Maitrics Settings"
        settingsWindow.center()
        settingsWindow.contentViewController = NSHostingController(
            rootView: SettingsView(settings: settings)
        )
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Update MaitricsApp**

Replace `Sources/Maitrics/MaitricsApp.swift`:
```swift
import SwiftUI
import AppKit

@main
struct MaitricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}
```

- [ ] **Step 3: Create stub views so it compiles**

Create `Sources/Maitrics/Views/PopoverContentView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct PopoverContentView: View {
    let dataManager: ClaudeDataManager
    let settings: AppSettings
    var onSettingsOpen: () -> Void

    var body: some View {
        Text("Maitrics — loading...")
            .frame(width: 420, height: 580)
    }
}
```

Create `Sources/Maitrics/Views/SettingsView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        Text("Settings — coming soon")
            .frame(width: 450, height: 500)
    }
}
```

- [ ] **Step 4: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/Maitrics/
git commit -m "add status bar controller and app entry point"
```

---

### Task 10: Popup Views — Header, Today, Model Breakdown

**Files:**
- Modify: `Sources/Maitrics/Views/PopoverContentView.swift`
- Create: `Sources/Maitrics/Views/HeaderView.swift`
- Create: `Sources/Maitrics/Views/TodaySummaryView.swift`
- Create: `Sources/Maitrics/Views/ModelBreakdownView.swift`
- Create: `Sources/Maitrics/Views/EmptyStateView.swift`

- [ ] **Step 1: Create HeaderView**

`Sources/Maitrics/Views/HeaderView.swift`:
```swift
import SwiftUI

struct HeaderView: View {
    var onSettingsOpen: () -> Void

    var body: some View {
        HStack {
            Text("MAITRICS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .tracking(0.5)

            Spacer()

            Button(action: onSettingsOpen) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
```

- [ ] **Step 2: Create TodaySummaryView**

`Sources/Maitrics/Views/TodaySummaryView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct TodaySummaryView: View {
    let cost: Double
    let tokens: Int
    let sessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Today")

            HStack(spacing: 10) {
                StatCard(
                    value: Formatting.cost(cost),
                    label: "EST. COST",
                    accentColor: Color(red: 74/255, green: 222/255, blue: 128/255) // #4ade80
                )
                StatCard(
                    value: Formatting.tokens(tokens),
                    label: "TOKENS",
                    accentColor: Color(red: 96/255, green: 165/255, blue: 250/255) // #60a5fa
                )
                StatCard(
                    value: "\(sessions)",
                    label: "SESSIONS",
                    accentColor: Color(red: 192/255, green: 132/255, blue: 252/255) // #c084fc
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(white: 0.5))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(white: 0.35))
            .tracking(1)
    }
}
```

- [ ] **Step 3: Create ModelBreakdownView**

`Sources/Maitrics/Views/ModelBreakdownView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct ModelBreakdownView: View {
    let models: [(name: String, tokens: Int, color: String)]

    private var maxTokens: Int {
        models.map(\.tokens).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "By Model")
                .padding(.bottom, 4)

            ForEach(models, id: \.name) { model in
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.65))
                        .frame(width: 48, alignment: .trailing)

                    GeometryReader { geo in
                        let fraction = maxTokens > 0 ? CGFloat(model.tokens) / CGFloat(maxTokens) : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: gradientColors(for: model.color),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(height: 5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(3)

                    Text(Formatting.tokens(model.tokens))
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func gradientColors(for color: String) -> [Color] {
        switch color {
        case "orange": return [Color(red: 249/255, green: 115/255, blue: 22/255), Color(red: 251/255, green: 146/255, blue: 60/255)]
        case "blue": return [Color(red: 59/255, green: 130/255, blue: 246/255), Color(red: 96/255, green: 165/255, blue: 250/255)]
        case "purple": return [Color(red: 168/255, green: 85/255, blue: 247/255), Color(red: 192/255, green: 132/255, blue: 252/255)]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
}
```

- [ ] **Step 4: Create EmptyStateView**

`Sources/Maitrics/Views/EmptyStateView.swift`:
```swift
import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.3))

            Text("No Claude Code data found")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.6))

            Text("Start a Claude Code session to see your usage stats here.")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Update PopoverContentView to compose sections**

Replace `Sources/Maitrics/Views/PopoverContentView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct PopoverContentView: View {
    @Bindable var dataManager: ClaudeDataManager
    let settings: AppSettings
    var onSettingsOpen: () -> Void

    var body: some View {
        ZStack {
            // Dark background with subtle vibrancy
            VisualEffectBackground()

            if dataManager.statsCache == nil && !dataManager.isLoading {
                EmptyStateView()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HeaderView(onSettingsOpen: onSettingsOpen)

                        Divider().opacity(0.06)

                        TodaySummaryView(
                            cost: dataManager.todayEstimatedCost,
                            tokens: dataManager.todayTokens,
                            sessions: dataManager.todayActivity?.sessionCount ?? 0
                        )

                        ModelBreakdownView(models: dataManager.modelBreakdown)

                        Divider().opacity(0.06)

                        // Chart and sessions added in next tasks
                        UsageTrendChartView(
                            dailyTotals: dataManager.dailyTotals(days: 7),
                            allDailyTotals: dataManager.dailyTotals(days: nil)
                        )

                        Divider().opacity(0.06)

                        RecentSessionsView(sessions: dataManager.recentSessions)

                        Divider().opacity(0.06)

                        FooterView(lastRefresh: dataManager.lastRefresh, isWatching: true)
                    }
                }
            }
        }
        .frame(width: 420, height: 580)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

- [ ] **Step 6: Create stub views for chart and sessions so it compiles**

`Sources/Maitrics/Views/UsageTrendChartView.swift`:
```swift
import SwiftUI

struct UsageTrendChartView: View {
    let dailyTotals: [(date: Date, tokens: Int)]
    let allDailyTotals: [(date: Date, tokens: Int)]

    var body: some View {
        Text("Chart placeholder")
            .padding(20)
    }
}
```

`Sources/Maitrics/Views/RecentSessionsView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct RecentSessionsView: View {
    let sessions: [RecentSession]

    var body: some View {
        Text("Sessions placeholder")
            .padding(20)
    }
}
```

`Sources/Maitrics/Views/FooterView.swift`:
```swift
import SwiftUI

struct FooterView: View {
    let lastRefresh: Date?
    let isWatching: Bool

    var body: some View {
        Text("Footer placeholder")
            .padding(10)
    }
}
```

- [ ] **Step 7: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 8: Commit**

```bash
git add Sources/Maitrics/Views/
git commit -m "add popup views: header, today summary, model breakdown, empty state"
```

---

### Task 11: Popup Views — Chart, Sessions, Footer

**Files:**
- Modify: `Sources/Maitrics/Views/UsageTrendChartView.swift`
- Modify: `Sources/Maitrics/Views/RecentSessionsView.swift`
- Modify: `Sources/Maitrics/Views/FooterView.swift`

- [ ] **Step 1: Implement UsageTrendChartView**

Replace `Sources/Maitrics/Views/UsageTrendChartView.swift`:
```swift
import SwiftUI
import Charts
import MaitricsCore

struct UsageTrendChartView: View {
    let dailyTotals: [(date: Date, tokens: Int)]
    let allDailyTotals: [(date: Date, tokens: Int)]

    @State private var selectedRange = 0 // 0=7d, 1=30d, 2=all

    private var displayData: [(date: Date, tokens: Int)] {
        switch selectedRange {
        case 0:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
            return allDailyTotals.filter { $0.date >= cutoff }
        case 1:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
            return allDailyTotals.filter { $0.date >= cutoff }
        default:
            return allDailyTotals
        }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Usage Trend")
                Spacer()
                Picker("", selection: $selectedRange) {
                    Text("7d").tag(0)
                    Text("30d").tag(1)
                    Text("All").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .scaleEffect(0.85)
            }

            Chart(displayData, id: \.date) { item in
                let f = DateFormatter()
                let _ = f.dateFormat = "yyyy-MM-dd"
                let isToday = f.string(from: item.date) == todayString

                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Tokens", item.tokens)
                )
                .foregroundStyle(
                    isToday
                        ? Color(red: 74/255, green: 222/255, blue: 128/255) // green
                        : Color(red: 59/255, green: 130/255, blue: 246/255) // blue
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(Color(white: 0.35))
                        .font(.system(size: 8))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text(Formatting.tokens(intVal))
                                .font(.system(size: 8))
                                .foregroundColor(Color(white: 0.35))
                        }
                    }
                }
            }
            .frame(height: 100)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
```

- [ ] **Step 2: Implement RecentSessionsView**

Replace `Sources/Maitrics/Views/RecentSessionsView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct RecentSessionsView: View {
    let sessions: [RecentSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Recent Sessions")
                .padding(.bottom, 4)

            if sessions.isEmpty {
                Text("No recent sessions")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 8)
            } else {
                ForEach(sessions) { session in
                    SessionRow(session: session)
                    if session.id != sessions.last?.id {
                        Divider().opacity(0.03)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct SessionRow: View {
    let session: RecentSession

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.firstPrompt)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(session.projectName)
                    if let branch = session.gitBranch {
                        Text("·")
                        Text(branch)
                    }
                    Text("·")
                    Text(Formatting.timeAgo(session.modified))
                }
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.35))
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.tokens(session.totalTokens))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 96/255, green: 165/255, blue: 250/255))

                Text("~\(Formatting.cost(session.estimatedCost))")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.35))
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Implement FooterView**

Replace `Sources/Maitrics/Views/FooterView.swift`:
```swift
import SwiftUI
import MaitricsCore

struct FooterView: View {
    let lastRefresh: Date?
    let isWatching: Bool

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(isWatching ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(white: 0.3))
                    .frame(width: 5, height: 5)

                Text(isWatching ? "Live · watching ~/.claude" : "Paused")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.3))
            }

            Spacer()

            Text("Last: \(lastRefreshText)")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.3))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var lastRefreshText: String {
        guard let lastRefresh else { return "never" }
        let seconds = Date().timeIntervalSince(lastRefresh)
        if seconds < 5 { return "just now" }
        return Formatting.timeAgo(lastRefresh)
    }
}
```

- [ ] **Step 4: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 5: Build the .app bundle and test manually**

Run: `chmod +x Scripts/build-app.sh && Scripts/build-app.sh debug 2>&1`
Expected: `Built: /Users/berke.altiparmak/Documents/maitrics/dist/Maitrics.app`

Run: `open dist/Maitrics.app`
Expected: App launches, icon appears in menu bar. Click to see the popover.

- [ ] **Step 6: Commit**

```bash
git add Sources/Maitrics/Views/
git commit -m "add usage chart, recent sessions, and footer views"
```

---

### Task 12: Settings View

**Files:**
- Modify: `Sources/Maitrics/Views/SettingsView.swift`

- [ ] **Step 1: Implement full SettingsView**

Replace `Sources/Maitrics/Views/SettingsView.swift`:
```swift
import SwiftUI
import MaitricsCore
import ServiceManagement

struct SettingsView: View {
    let settings: AppSettings
    @State private var greenThreshold: String = ""
    @State private var yellowThreshold: String = ""
    @State private var claudePath: String = ""
    @State private var launchAtLogin: Bool = false

    // Pricing
    @State private var opusInput: String = ""
    @State private var opusOutput: String = ""
    @State private var opusCacheRead: String = ""
    @State private var opusCacheWrite: String = ""
    @State private var sonnetInput: String = ""
    @State private var sonnetOutput: String = ""
    @State private var sonnetCacheRead: String = ""
    @State private var sonnetCacheWrite: String = ""
    @State private var haikuInput: String = ""
    @State private var haikuOutput: String = ""
    @State private var haikuCacheRead: String = ""
    @State private var haikuCacheWrite: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Thresholds
                GroupBox(label: Label("Icon Thresholds", systemImage: "gauge.with.dots.needle.33percent")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Token count thresholds for the menu bar icon color.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("Green below:")
                            TextField("100000", text: $greenThreshold)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Text("tokens")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Circle().fill(.yellow).frame(width: 8, height: 8)
                            Text("Yellow below:")
                            TextField("500000", text: $yellowThreshold)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Text("tokens")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Red above yellow threshold")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Pricing
                GroupBox(label: Label("Model Pricing", systemImage: "dollarsign.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cost per 1M tokens (USD). Used for estimated costs.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        PricingRow(model: "Opus", input: $opusInput, output: $opusOutput, cacheRead: $opusCacheRead, cacheWrite: $opusCacheWrite)
                        PricingRow(model: "Sonnet", input: $sonnetInput, output: $sonnetOutput, cacheRead: $sonnetCacheRead, cacheWrite: $sonnetCacheWrite)
                        PricingRow(model: "Haiku", input: $haikuInput, output: $haikuOutput, cacheRead: $haikuCacheRead, cacheWrite: $haikuCacheWrite)
                    }
                    .padding(8)
                }

                // General
                GroupBox(label: Label("General", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch at login", isOn: $launchAtLogin)

                        HStack {
                            Text("Claude data path:")
                            TextField("~/.claude", text: $claudePath)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(8)
                }

                // Save button
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        loadDefaults()
                    }
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 450, height: 500)
        .onAppear { loadCurrent() }
    }

    private func loadCurrent() {
        greenThreshold = "\(settings.thresholdGreen)"
        yellowThreshold = "\(settings.thresholdYellow)"
        claudePath = settings.claudeDataPath
        launchAtLogin = settings.launchAtLogin

        let pricing = settings.customPricing ?? [:]
        let opus = pricing["opus"] ?? CostCalculator.defaultPricing["opus"]!
        let sonnet = pricing["sonnet"] ?? CostCalculator.defaultPricing["sonnet"]!
        let haiku = pricing["haiku"] ?? CostCalculator.defaultPricing["haiku"]!

        opusInput = "\(opus.inputPer1M)"
        opusOutput = "\(opus.outputPer1M)"
        opusCacheRead = "\(opus.cacheReadPer1M)"
        opusCacheWrite = "\(opus.cacheWritePer1M)"
        sonnetInput = "\(sonnet.inputPer1M)"
        sonnetOutput = "\(sonnet.outputPer1M)"
        sonnetCacheRead = "\(sonnet.cacheReadPer1M)"
        sonnetCacheWrite = "\(sonnet.cacheWritePer1M)"
        haikuInput = "\(haiku.inputPer1M)"
        haikuOutput = "\(haiku.outputPer1M)"
        haikuCacheRead = "\(haiku.cacheReadPer1M)"
        haikuCacheWrite = "\(haiku.cacheWritePer1M)"
    }

    private func loadDefaults() {
        greenThreshold = "100000"
        yellowThreshold = "500000"
        claudePath = NSHomeDirectory() + "/.claude"

        let opus = CostCalculator.defaultPricing["opus"]!
        let sonnet = CostCalculator.defaultPricing["sonnet"]!
        let haiku = CostCalculator.defaultPricing["haiku"]!

        opusInput = "\(opus.inputPer1M)"; opusOutput = "\(opus.outputPer1M)"
        opusCacheRead = "\(opus.cacheReadPer1M)"; opusCacheWrite = "\(opus.cacheWritePer1M)"
        sonnetInput = "\(sonnet.inputPer1M)"; sonnetOutput = "\(sonnet.outputPer1M)"
        sonnetCacheRead = "\(sonnet.cacheReadPer1M)"; sonnetCacheWrite = "\(sonnet.cacheWritePer1M)"
        haikuInput = "\(haiku.inputPer1M)"; haikuOutput = "\(haiku.outputPer1M)"
        haikuCacheRead = "\(haiku.cacheReadPer1M)"; haikuCacheWrite = "\(haiku.cacheWritePer1M)"
    }

    private func save() {
        settings.thresholdGreen = Int(greenThreshold) ?? 100_000
        settings.thresholdYellow = Int(yellowThreshold) ?? 500_000
        settings.claudeDataPath = claudePath
        settings.launchAtLogin = launchAtLogin

        settings.customPricing = [
            "opus": PricingTier(
                inputPer1M: Double(opusInput) ?? 15,
                outputPer1M: Double(opusOutput) ?? 75,
                cacheReadPer1M: Double(opusCacheRead) ?? 1.5,
                cacheWritePer1M: Double(opusCacheWrite) ?? 18.75
            ),
            "sonnet": PricingTier(
                inputPer1M: Double(sonnetInput) ?? 3,
                outputPer1M: Double(sonnetOutput) ?? 15,
                cacheReadPer1M: Double(sonnetCacheRead) ?? 0.3,
                cacheWritePer1M: Double(sonnetCacheWrite) ?? 3.75
            ),
            "haiku": PricingTier(
                inputPer1M: Double(haikuInput) ?? 0.8,
                outputPer1M: Double(haikuOutput) ?? 4,
                cacheReadPer1M: Double(haikuCacheRead) ?? 0.08,
                cacheWritePer1M: Double(haikuCacheWrite) ?? 1.0
            ),
        ]

        // Launch at login
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can set manually in System Settings
            }
        }
    }
}

struct PricingRow: View {
    let model: String
    @Binding var input: String
    @Binding var output: String
    @Binding var cacheRead: String
    @Binding var cacheWrite: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                PricingField(label: "Input", value: $input)
                PricingField(label: "Output", value: $output)
                PricingField(label: "Cache R", value: $cacheRead)
                PricingField(label: "Cache W", value: $cacheWrite)
            }
        }
    }
}

struct PricingField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            TextField("0", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .font(.system(size: 11))
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Test manually**

Run: `Scripts/build-app.sh debug && open dist/Maitrics.app`
Expected: Click gear icon in popover → settings window opens with thresholds, pricing, and general sections.

- [ ] **Step 4: Commit**

```bash
git add Sources/Maitrics/Views/SettingsView.swift
git commit -m "add settings view with thresholds, pricing, and launch at login"
```

---

### Task 13: DMG Packaging

**Files:**
- Create: `Scripts/create-dmg.sh`

- [ ] **Step 1: Create DMG script**

`Scripts/create-dmg.sh`:
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Maitrics"
VERSION="${1:-0.1.0}"

echo "Building release..."
"$SCRIPT_DIR/build-app.sh" release

APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/dist/dmg-staging"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found"
    exit 1
fi

echo "Creating DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create symlink to Applications
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean up
rm -rf "$STAGING_DIR"

echo "Created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
```

- [ ] **Step 2: Test DMG creation**

Run: `chmod +x Scripts/create-dmg.sh && Scripts/create-dmg.sh 0.1.0 2>&1`
Expected: `Created: /Users/berke.altiparmak/Documents/maitrics/dist/Maitrics-0.1.0.dmg`

- [ ] **Step 3: Verify DMG works**

Run: `open dist/Maitrics-0.1.0.dmg`
Expected: Finder opens the DMG volume showing Maitrics.app and an Applications shortcut.

- [ ] **Step 4: Update .gitignore to exclude dist/**

Add `dist/` to `.gitignore`.

- [ ] **Step 5: Commit**

```bash
git add Scripts/create-dmg.sh .gitignore
git commit -m "add DMG packaging script"
```

---

### Task 14: Final Integration & Polish

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1`
Expected: All tests pass

- [ ] **Step 2: Build and launch the full app**

Run: `Scripts/build-app.sh debug && open dist/Maitrics.app`
Expected: App appears in menu bar with colored icon. Click opens popover with real data from `~/.claude/`.

- [ ] **Step 3: Verify each popup section shows real data**

Check:
1. Header shows "MAITRICS" with gear icon
2. Today's summary shows cost, token count, session count
3. Model breakdown shows bars for each model family used today
4. Chart shows usage trend (try switching 7d/30d/All)
5. Recent sessions show prompt, project, branch, tokens, cost
6. Footer shows green "Live" indicator

- [ ] **Step 4: Verify settings**

Click gear → verify thresholds, pricing, and path fields load correctly. Change a threshold, save, and confirm the icon color updates.

- [ ] **Step 5: Verify file watcher**

Start a new Claude Code session in another terminal. Confirm the popover data updates when you reopen it.

- [ ] **Step 6: Final commit and push**

```bash
git add -A
git commit -m "finalize integration and polish"
git push origin main
```
