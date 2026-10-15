import XCTest
@testable import Bichitos

final class SmokeTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(BichitosApp.self)
    }
}
