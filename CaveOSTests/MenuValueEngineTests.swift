import XCTest
@testable import CaveOS

final class MenuValueEngineTests: XCTestCase {
    func testUnknownWhenTierMissing() {
        XCTAssertEqual(MenuValueEngine.verdict(tier: nil, price: 40), .unknown)
    }
    func testUnknownWhenPriceMissing() {
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: nil), .unknown)
    }
    func testMidBands() {
        // bande mid attendue : 28–45 €
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 24), .goodValue)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 35), .fair)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 60), .expensive)
    }
}
