import XCTest
@testable import CaveOS

final class MenuMatchingTests: XCTestCase {
    func testNormalizeStripsAccentsAndCase() {
        XCTAssertEqual(MenuMatching.normalize("Château Margaux"), "chateau margaux")
    }

    func testMatchesIgnoresAccentsAndCase() {
        XCTAssertTrue(MenuMatching.matches(
            candidateProducer: "clos la coutale", candidateName: "Cahors",
            wineProducer: "Clos La Coutale", wineName: "CAHORS"))
    }

    func testDoesNotMatchDifferentWine() {
        XCTAssertFalse(MenuMatching.matches(
            candidateProducer: "Domaine A", candidateName: "Chinon",
            wineProducer: "Domaine B", wineName: "Sancerre"))
    }
}
