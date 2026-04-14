import XCTest
@testable import MaitricsCore

final class SessionParserTests: XCTestCase {
    func testParsesSessionTokenUsage() throws {
        let url = Bundle.module.url(forResource: "session-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let usage = try SessionParser.parseTokenUsage(fileURL: url)
        XCTAssertEqual(usage.byModel.count, 2)

        let opus = usage.byModel["claude-opus-4-6"]!
        XCTAssertEqual(opus.inputTokens, 300)      // 100+200
        XCTAssertEqual(opus.outputTokens, 1300)     // 500+800
        XCTAssertEqual(opus.cacheCreationInputTokens, 3000) // 2000+1000
        XCTAssertEqual(opus.cacheReadInputTokens, 13000)    // 5000+8000

        let haiku = usage.byModel["claude-haiku-4-5-20251001"]!
        XCTAssertEqual(haiku.inputTokens, 50)
        XCTAssertEqual(haiku.outputTokens, 100)
    }

    func testTotalTokensAcrossModels() throws {
        let url = Bundle.module.url(forResource: "session-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let usage = try SessionParser.parseTokenUsage(fileURL: url)
        XCTAssertEqual(usage.totalInputTokens, 350)    // 300+50
        XCTAssertEqual(usage.totalOutputTokens, 1400)   // 1300+100
    }

    func testReturnsEmptyForMissingFile() {
        let usage = try? SessionParser.parseTokenUsage(fileURL: URL(fileURLWithPath: "/nonexistent.jsonl"))
        XCTAssertNil(usage)
    }
}
