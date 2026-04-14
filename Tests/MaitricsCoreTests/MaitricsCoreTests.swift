import XCTest
@testable import MaitricsCore

final class MaitricsCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(MaitricsCore.version, "0.1.0")
    }
}
