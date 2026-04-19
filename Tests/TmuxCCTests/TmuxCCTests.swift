import XCTest
@testable import TmuxCC

final class TmuxCCTests: XCTestCase {
	func testControlModeFlag() {
		XCTAssertEqual(TmuxCC.controlModeFlag, "-CC")
	}
}
