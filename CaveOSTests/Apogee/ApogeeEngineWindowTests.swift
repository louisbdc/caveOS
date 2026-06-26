import XCTest
@testable import CaveOS

final class ApogeeEngineWindowTests: XCTestCase {
    func testWindowFromRawFieldsReturnsOrderedYears() {
        let w = ApogeeEngine.window(vintage: 2018, grapes: ["Malbec"], regionTier: .mid, storage: .good)
        XCTAssertNotNil(w)
        guard let w else { return }
        XCTAssertLessThanOrEqual(w.drinkFrom, w.peak)
        XCTAssertLessThanOrEqual(w.peak, w.drinkBy)
        XCTAssertGreaterThanOrEqual(w.drinkFrom, 2018)
    }

    func testWindowNilWhenNoVintage() {
        XCTAssertNil(ApogeeEngine.window(vintage: nil, grapes: ["Malbec"], regionTier: .mid, storage: .good))
    }
}
