import XCTest
@testable import MaitricsCore

final class JSONLUsageIndexTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JSONLUsageIndexTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeIndex(chunkSize: Int = 4 << 20, timeZone: TimeZone = .current) -> JSONLUsageIndex {
        JSONLUsageIndex(
            cacheURL: tempDir.appendingPathComponent("cache.json"),
            chunkSize: chunkSize,
            timeZone: timeZone
        )
    }

    private func assistantLine(model: String, input: Int, output: Int, cacheWrite: Int = 0, cacheRead: Int = 0, timestamp: String) -> String {
        """
        {"type":"assistant","message":{"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)}},"timestamp":"\(timestamp)"}
        """
    }

    private func write(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    // MARK: - Parity with the non-incremental parser

    func testMatchesSessionParserOnTheSameFile() throws {
        let fixture = Bundle.module.url(forResource: "session-sample", withExtension: "jsonl", subdirectory: "Fixtures")!
        let copy = tempDir.appendingPathComponent("session-sample.jsonl")
        try FileManager.default.copyItem(at: fixture, to: copy)

        let expected = try SessionParser.parseTokenUsage(fileURL: copy)
        let actual = makeIndex().tokenUsage(forPath: copy.path)

        XCTAssertEqual(actual?.byModel.count, expected.byModel.count)
        XCTAssertEqual(actual?.totalInputTokens, expected.totalInputTokens)
        XCTAssertEqual(actual?.totalOutputTokens, expected.totalOutputTokens)
        XCTAssertEqual(actual?.totalCacheReadTokens, expected.totalCacheReadTokens)
        XCTAssertEqual(actual?.totalCacheWriteTokens, expected.totalCacheWriteTokens)
    }

    // MARK: - Incremental behaviour

    func testAppendedLinesAreAddedToExistingTotals() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z")], to: file)

        let index = makeIndex()
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 20)

        try append([assistantLine(model: "opus", input: 5, output: 7, timestamp: "2026-04-01T11:00:00Z")], to: file)

        let usage = index.tokenUsage(forPath: file.path)
        XCTAssertEqual(usage?.totalInputTokens, 15)
        XCTAssertEqual(usage?.totalOutputTokens, 27)
    }

    func testRescanWithoutChangesDoesNotDoubleCount() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z")], to: file)

        let index = makeIndex()
        _ = index.tokenUsage(forPath: file.path)
        _ = index.tokenUsage(forPath: file.path)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 20)
    }

    func testTrailingPartialLineIsNotConsumedUntilComplete() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        let complete = assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z")
        let partial = assistantLine(model: "opus", input: 1, output: 2, timestamp: "2026-04-01T10:05:00Z")
        let half = String(partial.prefix(partial.count / 2))
        try (complete + "\n" + half).write(to: file, atomically: true, encoding: .utf8)

        let index = makeIndex()
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 20)

        // The writer finishes the line — it must now be counted exactly once.
        try append([String(partial.dropFirst(half.count))], to: file)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 22)
    }

    func testRewrittenSmallerFileIsRescannedFromScratch() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([
            assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z"),
            assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:01:00Z"),
        ], to: file)

        let index = makeIndex()
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 40)

        try write([assistantLine(model: "opus", input: 1, output: 2, timestamp: "2026-04-01T10:00:00Z")], to: file)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 2)
    }

    func testNonAssistantLinesAreIgnored() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([
            #"{"type":"user","message":{"content":"the words output_tokens appear here"},"timestamp":"2026-04-01T10:00:00Z"}"#,
            #"{"type":"summary","summary":"nope"}"#,
            assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z"),
        ], to: file)

        let usage = makeIndex().tokenUsage(forPath: file.path)
        XCTAssertEqual(usage?.byModel.count, 1)
        XCTAssertEqual(usage?.totalOutputTokens, 20)
    }

    /// Regression: with a chunked read the carried-over partial line must not be
    /// double-counted in the byte offset, or the next scan resumes too early and
    /// re-adds tokens it already counted.
    func testMultiChunkScanTracksOffsetExactly() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        let lines = (0..<200).map { i in
            assistantLine(model: "opus", input: 1, output: 1, timestamp: "2026-04-01T10:00:00Z")
                + String(repeating: " ", count: i % 7)  // vary length so lines straddle chunks
        }
        try write(lines, to: file)

        let index = makeIndex(chunkSize: 64)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 200)

        try append([assistantLine(model: "opus", input: 1, output: 1, timestamp: "2026-04-01T10:00:00Z")], to: file)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 201,
                       "an appended line must add exactly one message, not replay earlier chunks")
    }

    func testMultiChunkScanHandlesLinesLongerThanTheChunk() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([assistantLine(model: "opus", input: 4, output: 6, timestamp: "2026-04-01T10:00:00Z")], to: file)

        let index = makeIndex(chunkSize: 8)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 6)

        try append([assistantLine(model: "opus", input: 4, output: 6, timestamp: "2026-04-01T10:00:00Z")], to: file)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 12)
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(makeIndex().tokenUsage(forPath: tempDir.appendingPathComponent("nope.jsonl").path))
    }

    // MARK: - Daily aggregation

    func testDailyTokensGroupsByLocalDayAndFiltersByCutoff() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([
            assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T12:00:00Z"),
            assistantLine(model: "opus", input: 1, output: 2, timestamp: "2026-04-03T12:00:00Z"),
            assistantLine(model: "haiku", input: 3, output: 4, timestamp: "2026-04-03T13:00:00Z"),
        ], to: file)

        let cutoff = JSONLUsageIndex.makeDayFormatter().date(from: "2026-04-02")!
        let daily = makeIndex().dailyTokens(forPaths: [file.path], after: cutoff)

        XCTAssertNil(daily["2026-04-01"], "days at or before the cutoff come from the stats cache instead")
        XCTAssertEqual(daily["2026-04-03"]?["opus"], 3)
        XCTAssertEqual(daily["2026-04-03"]?["haiku"], 7)
    }

    func testDailyTokensMergesAcrossFiles() throws {
        let a = tempDir.appendingPathComponent("a.jsonl")
        let b = tempDir.appendingPathComponent("b.jsonl")
        try write([assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-03T12:00:00Z")], to: a)
        try write([assistantLine(model: "opus", input: 1, output: 2, timestamp: "2026-04-03T12:00:00Z")], to: b)

        let cutoff = JSONLUsageIndex.makeDayFormatter().date(from: "2026-04-01")!
        let daily = makeIndex().dailyTokens(forPaths: [a.path, b.path], after: cutoff)
        XCTAssertEqual(daily["2026-04-03"]?["opus"], 33)
    }

    /// Regression: the timestamp -> local-day memo must key on the UTC minute.
    /// A UTC *hour* key straddles local midnight wherever the offset is not a
    /// whole number of hours, booking post-midnight tokens to the previous day.
    func testFractionalOffsetTimeZoneSplitsAtLocalMidnight() throws {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!  // UTC+05:30
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([
            // 18:20Z = 23:50 local on the 1st; 18:40Z = 00:10 local on the 2nd.
            assistantLine(model: "opus", input: 1, output: 1, timestamp: "2026-04-01T18:20:00Z"),
            assistantLine(model: "opus", input: 2, output: 3, timestamp: "2026-04-01T18:40:00Z"),
        ], to: file)

        let cutoff = JSONLUsageIndex.makeDayFormatter(timeZone: kolkata).date(from: "2026-03-01")!
        let daily = makeIndex(timeZone: kolkata).dailyTokens(forPaths: [file.path], after: cutoff)

        XCTAssertEqual(daily["2026-04-01"]?["opus"], 2)
        XCTAssertEqual(daily["2026-04-02"]?["opus"], 5)
    }

    func testQuarterHourOffsetTimeZoneSplitsAtLocalMidnight() throws {
        let chatham = TimeZone(identifier: "Pacific/Chatham")!  // UTC+12:45 / +13:45
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([
            assistantLine(model: "opus", input: 1, output: 1, timestamp: "2026-04-01T10:10:00Z"),
            assistantLine(model: "opus", input: 2, output: 3, timestamp: "2026-04-01T10:30:00Z"),
        ], to: file)

        let formatter = JSONLUsageIndex.makeDayFormatter(timeZone: chatham)
        let cutoff = formatter.date(from: "2026-03-01")!
        let daily = makeIndex(timeZone: chatham).dailyTokens(forPaths: [file.path], after: cutoff)

        XCTAssertEqual(daily.count, 2, "one UTC hour straddling local midnight must produce two day keys")
    }

    // MARK: - Persistence

    func testTotalsSurviveARelaunchWithoutRereadingTheFile() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z")], to: file)

        let cacheURL = tempDir.appendingPathComponent("cache.json")
        let first = JSONLUsageIndex(cacheURL: cacheURL)
        _ = first.tokenUsage(forPath: file.path)
        first.save()

        // Make the file unreadable: a fresh index must still answer from the cache.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        let second = JSONLUsageIndex(cacheURL: cacheURL)
        XCTAssertEqual(second.tokenUsage(forPath: file.path)?.totalOutputTokens, 20)
    }

    /// A read failure must not be mistaken for end-of-file: recording the full
    /// size next to a partial offset would freeze the undercount forever.
    func testReadFailureLeavesTheStoredEntryUntouched() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z")], to: file)

        let index = makeIndex()
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 20)

        // Grow the file so a rescan is attempted, then make the read fail.
        try append([assistantLine(model: "opus", input: 1, output: 2, timestamp: "2026-04-01T10:01:00Z")], to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 20,
                       "an unreadable file keeps the last good tally rather than a truncated one")

        // Once readable again the appended line is picked up exactly once.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertEqual(index.tokenUsage(forPath: file.path)?.totalOutputTokens, 22)
    }

    func testPruneDropsEntriesForVanishedFiles() throws {
        let file = tempDir.appendingPathComponent("s.jsonl")
        try write([assistantLine(model: "opus", input: 10, output: 20, timestamp: "2026-04-01T10:00:00Z")], to: file)

        let cacheURL = tempDir.appendingPathComponent("cache.json")
        let index = JSONLUsageIndex(cacheURL: cacheURL)
        _ = index.tokenUsage(forPath: file.path)
        index.prune(keeping: [])
        index.save()

        try FileManager.default.removeItem(at: file)
        XCTAssertNil(JSONLUsageIndex(cacheURL: cacheURL).tokenUsage(forPath: file.path))
    }
}
