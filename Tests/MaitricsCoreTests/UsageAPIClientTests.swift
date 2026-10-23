import XCTest
@testable import MaitricsCore

final class UsageAPIClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func credentials(token: String, expiresAt: Date?) -> Data {
        var oauth: [String: Any] = ["accessToken": token]
        if let expiresAt { oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000) }
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
    }

    func testSkipsExpiredEntryInFavourOfValidOne() {
        let stale = credentials(token: "stale", expiresAt: now.addingTimeInterval(-3600))
        let fresh = credentials(token: "fresh", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [stale, fresh], now: now), .valid("fresh"))
    }

    func testPicksLatestExpiryAmongValidEntries() {
        let soon = credentials(token: "soon", expiresAt: now.addingTimeInterval(60))
        let later = credentials(token: "later", expiresAt: now.addingTimeInterval(7200))
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [soon, later], now: now), .valid("later"))
    }

    func testAllEntriesExpiredReportsExpired() {
        let stale = credentials(token: "stale", expiresAt: now.addingTimeInterval(-1))
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [stale], now: now), .expired)
    }

    func testMissingExpiryIsTreatedAsValid() {
        let noExpiry = credentials(token: "token", expiresAt: nil)
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [noExpiry], now: now), .valid("token"))
    }

    func testUnparseableOrEmptyCredentialsReportMissing() {
        let garbage = Data("not json".utf8)
        let empty = credentials(token: "", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [garbage, empty], now: now), .missing)
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [], now: now), .missing)
    }

    func testTokenExpiringWithinMarginCountsAsExpired() {
        let expiring = credentials(token: "expiring", expiresAt: now.addingTimeInterval(30))
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [expiring], now: now), .expired)
    }

    func testTimedTokenBeatsEntryWithoutExpiry() {
        let noExpiry = credentials(token: "legacy", expiresAt: nil)
        let timed = credentials(token: "timed", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(UsageAPIClient.selectToken(fromCredentials: [noExpiry, timed], now: now), .valid("timed"))
    }

    func testExpiredTokenIsNeverSent() {
        XCTAssertEqual(UsageAPIClient.preflight(.expired, rateLimited: nil, now: now), .expired)
        XCTAssertEqual(UsageAPIClient.preflight(.missing, rateLimited: nil, now: now), .noCredentials)
        XCTAssertEqual(UsageAPIClient.preflight(.valid("t"), rateLimited: nil, now: now), .send(token: "t"))
    }

    func testRateLimitBackoffAppliesOnlyToTheTokenThatHitIt() {
        let until = now.addingTimeInterval(600)
        XCTAssertEqual(
            UsageAPIClient.preflight(.valid("old"), rateLimited: (until, "old"), now: now),
            .rateLimited(until: until)
        )
        XCTAssertEqual(
            UsageAPIClient.preflight(.valid("new"), rateLimited: (until, "old"), now: now),
            .send(token: "new")
        )
        XCTAssertEqual(
            UsageAPIClient.preflight(.valid("old"), rateLimited: (now.addingTimeInterval(-1), "old"), now: now),
            .send(token: "old")
        )
    }

    func testExpiredCredentialsStillCountAsConnected() {
        XCTAssertTrue(UsageAPIClient.hasCredentials(.expired))
        XCTAssertTrue(UsageAPIClient.hasCredentials(.valid("t")))
        XCTAssertFalse(UsageAPIClient.hasCredentials(.missing))
    }

    func testLoginScriptQuotesExecutablePath() {
        XCTAssertEqual(
            ClaudeCLI.loginScript(executablePath: "/Users/o'neil/bin/claude"),
            "#!/bin/zsh -l\nexec '/Users/o'\\''neil/bin/claude' auth login\n"
        )
    }

    func testOpenLoginWithoutExecutableThrowsCliNotFound() {
        XCTAssertThrowsError(try ClaudeCLI.openLogin(executablePath: nil, scriptURL: URL(fileURLWithPath: "/unused"))) { error in
            XCTAssertEqual(error as? ClaudeCLI.LoginError, .cliNotFound)
        }
    }

    func testOpenLoginReportsLaunchFailedWhenScriptCannotBeWritten() {
        let unwritable = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/login.command")
        XCTAssertThrowsError(try ClaudeCLI.openLogin(executablePath: "/usr/bin/true", scriptURL: unwritable)) { error in
            XCTAssertEqual(error as? ClaudeCLI.LoginError, .launchFailed)
        }
    }

    func testLocatesFirstExecutableClaudeCandidate() {
        let path = ClaudeCLI.locate(
            candidates: ["/a/claude", "/b/claude", "/c/claude"],
            isExecutable: { $0 != "/a/claude" }
        )
        XCTAssertEqual(path, "/b/claude")
        XCTAssertNil(ClaudeCLI.locate(candidates: ["/a/claude"], isExecutable: { _ in false }))
    }
}
