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
    func testUnknownWhenPriceZero() {
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 0), .unknown)
    }
    func testEntryBands() {
        // bande entry attendue : 18–30 €
        XCTAssertEqual(MenuValueEngine.verdict(tier: .entry, price: 12), .goodValue)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .entry, price: 24), .fair)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .entry, price: 40), .expensive)
    }
    func testPremiumBands() {
        // bande premium attendue : 50–90 €
        XCTAssertEqual(MenuValueEngine.verdict(tier: .premium, price: 35), .goodValue)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .premium, price: 70), .fair)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .premium, price: 150), .expensive)
    }
}
