import XCTest
@testable import MaitricsCore

final class UsageAlertEvaluatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var resetsAt: Date { now.addingTimeInterval(3600) }

    private func session(_ utilization: Double, resetsAt: Date?) -> TrackedWindow {
        TrackedWindow(id: "session", name: "Session", utilization: utilization, resetsAt: resetsAt, duration: UsagePace.sessionWindow)
    }

    private func evaluate(_ window: TrackedWindow, _ state: inout UsageAlertState, notifyOnReset: Bool = true, now: Date? = nil) -> [UsageAlert] {
        UsageAlertEvaluator.evaluate([window], state: &state, thresholds: [80, 95], notifyOnReset: notifyOnReset, now: now ?? self.now)
    }

    func testBelowThresholdsFiresNothing() {
        var state = UsageAlertState()
        XCTAssertTrue(evaluate(session(50, resetsAt: resetsAt), &state).isEmpty)
    }

    func testThresholdFiresOncePerWindow() {
        var state = UsageAlertState()
        XCTAssertEqual(evaluate(session(82, resetsAt: resetsAt), &state).map(\.kind), [.threshold(80)])
        XCTAssertTrue(evaluate(session(85, resetsAt: resetsAt), &state).isEmpty)
        XCTAssertEqual(evaluate(session(96, resetsAt: resetsAt), &state).map(\.kind), [.threshold(95)])
    }

    func testJumpAcrossThresholdsReportsOnlyHighest() {
        var state = UsageAlertState()
        XCTAssertEqual(evaluate(session(97, resetsAt: resetsAt), &state).map(\.kind), [.threshold(95)])
        XCTAssertTrue(evaluate(session(97, resetsAt: resetsAt), &state).isEmpty)
    }

    func testSmallResetDriftIsSameWindow() {
        var state = UsageAlertState()
        _ = evaluate(session(82, resetsAt: resetsAt), &state)
        XCTAssertTrue(evaluate(session(83, resetsAt: resetsAt.addingTimeInterval(60)), &state).isEmpty)
    }

    func testRolloverAfterHighUsageNotifiesResetAndRearms() {
        var state = UsageAlertState()
        _ = evaluate(session(90, resetsAt: resetsAt), &state)

        let next = resetsAt.addingTimeInterval(UsagePace.sessionWindow)
        let later = resetsAt.addingTimeInterval(60)
        XCTAssertEqual(evaluate(session(2, resetsAt: next), &state, now: later).map(\.kind), [.reset(peak: 90)])
        XCTAssertEqual(evaluate(session(81, resetsAt: next), &state, now: later).map(\.kind), [.threshold(80)])
    }

    func testRolloverAfterLowUsageIsSilent() {
        var state = UsageAlertState()
        _ = evaluate(session(40, resetsAt: resetsAt), &state)
        XCTAssertTrue(evaluate(session(0, resetsAt: nil), &state).isEmpty)
    }

    func testResetNotificationCanBeDisabled() {
        var state = UsageAlertState()
        _ = evaluate(session(90, resetsAt: resetsAt), &state)
        XCTAssertTrue(evaluate(session(0, resetsAt: nil), &state, notifyOnReset: false).isEmpty)
    }

    func testStaleWindowIsIgnored() {
        var state = UsageAlertState()
        XCTAssertTrue(evaluate(session(99, resetsAt: now.addingTimeInterval(-60)), &state).isEmpty)
        XCTAssertTrue(state.windows.isEmpty)
    }

    func testAlertStatePersistsThroughSettings() {
        let defaults = UserDefaults(suiteName: "UsageAlertEvaluatorTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        var state = UsageAlertState()
        _ = evaluate(session(82, resetsAt: resetsAt), &state)
        settings.alertState = state
        XCTAssertEqual(settings.alertState, state)
    }
}
