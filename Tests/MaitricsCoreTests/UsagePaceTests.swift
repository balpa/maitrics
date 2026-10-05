import XCTest
@testable import MaitricsCore

final class UsagePaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let window = UsagePace.sessionWindow

    private func pace(_ utilization: Double, remaining: TimeInterval) -> UsagePace? {
        UsagePace.compute(utilization: utilization, resetsAt: now.addingTimeInterval(remaining), window: window, now: now)
    }

    func testExpectedPercentFollowsElapsedTime() throws {
        let p = try XCTUnwrap(pace(50, remaining: window / 2))
        XCTAssertEqual(p.expectedPercent, 50, accuracy: 0.001)
        XCTAssertEqual(p.delta, 0, accuracy: 0.001)
        XCTAssertNil(p.runsOutIn)
        XCTAssertEqual(p.summary, "On pace")
    }

    func testAheadOfPaceProjectsRunOut() throws {
        // 1h of 5h elapsed, 40% used: 40%/h, so the rest takes 1.5h
        let p = try XCTUnwrap(pace(40, remaining: 4 * 3600))
        XCTAssertEqual(p.delta, 20, accuracy: 0.001)
        XCTAssertTrue(p.isAhead)
        XCTAssertEqual(try XCTUnwrap(p.runsOutIn), 1.5 * 3600, accuracy: 1)
        XCTAssertEqual(p.summary, "20% ahead of pace · runs out in 1h 30m")
    }

    func testUnderPace() throws {
        let p = try XCTUnwrap(pace(10, remaining: window / 2))
        XCTAssertTrue(p.isBehind)
        XCTAssertNil(p.runsOutIn)
        XCTAssertEqual(p.summary, "40% under pace")
    }

    func testLimitReached() throws {
        let p = try XCTUnwrap(pace(100, remaining: 3600))
        XCTAssertEqual(p.runsOutIn, 0)
        XCTAssertTrue(p.summary.hasSuffix("limit reached"))
    }

    func testNoProjectionEarlyInWindow() throws {
        let p = try XCTUnwrap(pace(5, remaining: window - 60))
        XCTAssertNil(p.runsOutIn)
    }

    func testNilWithoutValidResetTime() {
        XCTAssertNil(UsagePace.compute(utilization: 50, resetsAt: nil, window: window, now: now))
        XCTAssertNil(pace(50, remaining: -10))
        XCTAssertNil(pace(50, remaining: window * 2))
    }
}
