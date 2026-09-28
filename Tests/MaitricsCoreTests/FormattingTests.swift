import XCTest
@testable import MaitricsCore

final class FormattingTests: XCTestCase {
    func testCostFormatting() {
        XCTAssertEqual(Formatting.cost(0), "$0.00")
        XCTAssertEqual(Formatting.cost(0.004), "<$0.01")
        XCTAssertEqual(Formatting.cost(6.93), "$6.93")
        XCTAssertEqual(Formatting.cost(412.4), "$412")
        XCTAssertEqual(Formatting.cost(1923.2), "$1,923")
    }

    func testDuration() {
        XCTAssertEqual(Formatting.duration(90 * 60), "1h 30m")
        XCTAssertEqual(Formatting.duration(45 * 60), "45m")
        XCTAssertEqual(Formatting.duration(5 * 86400 + 3 * 3600), "5d 3h")
    }
}
