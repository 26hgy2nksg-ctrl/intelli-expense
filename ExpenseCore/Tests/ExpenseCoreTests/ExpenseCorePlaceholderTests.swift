import XCTest
@testable import ExpenseCore

final class ExpenseCorePlaceholderTests: XCTestCase {
    func testPackageIsWired() {
        XCTAssertEqual(ExpenseCoreBuild.version, "0.0.0")
    }
}
