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
