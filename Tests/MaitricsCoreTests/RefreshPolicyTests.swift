import XCTest
@testable import MaitricsCore

final class RefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAdaptiveIntervalDependsOnActivity() {
        XCTAssertEqual(RefreshMode.adaptive.interval(claudeActive: true), RefreshPolicy.activeInterval)
        XCTAssertEqual(RefreshMode.adaptive.interval(claudeActive: false), RefreshPolicy.idleInterval)
        XCTAssertEqual(RefreshMode.fiveMinutes.interval(claudeActive: true), 300)
        XCTAssertNil(RefreshMode.manual.interval(claudeActive: true))
    }

    func testDueWithinHalfTickOfInterval() {
        XCTAssertTrue(RefreshPolicy.isDue(interval: 60, lastRefresh: nil, now: now))
        XCTAssertTrue(RefreshPolicy.isDue(interval: 60, lastRefresh: now.addingTimeInterval(-58), now: now))
        XCTAssertFalse(RefreshPolicy.isDue(interval: 60, lastRefresh: now.addingTimeInterval(-30), now: now))
        XCTAssertFalse(RefreshPolicy.isDue(interval: nil, lastRefresh: nil, now: now))
    }

    func testRecentSessionWriteCountsAsActive() {
        XCTAssertTrue(RefreshPolicy.isClaudeActive(processRunning: true, lastSessionActivity: nil, now: now))
        XCTAssertTrue(RefreshPolicy.isClaudeActive(processRunning: false, lastSessionActivity: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(RefreshPolicy.isClaudeActive(processRunning: false, lastSessionActivity: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(RefreshPolicy.isClaudeActive(processRunning: false, lastSessionActivity: nil, now: now))
    }

    func testRefreshModeRoundTripsThroughSettings() {
        let defaults = UserDefaults(suiteName: "RefreshPolicyTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.refreshMode, .adaptive)
        settings.refreshMode = .fifteenMinutes
        XCTAssertEqual(settings.refreshMode, .fifteenMinutes)
    }
}
