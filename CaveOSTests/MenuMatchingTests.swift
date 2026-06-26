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

    func testShortTokenDoesNotFalseMatch() {
        // « or » (2 chars) ne doit PAS matcher « cahors » : sous-chaîne autorisée seulement si les deux ≥ 4.
        XCTAssertFalse(MenuMatching.matches(
            candidateProducer: nil, candidateName: "Cahors",
            wineProducer: nil, wineName: "Or"))
    }

    func testShortProducerDoesNotFalseMatch() {
        // Noms égaux (« chinon »), mais producteur « cl » (2 chars) trop court vs « clos vougeot »
        // → égalité stricte exigée, donc pas de match malgré la sous-chaîne.
        XCTAssertFalse(MenuMatching.matches(
            candidateProducer: "cl", candidateName: "Chinon",
            wineProducer: "Clos Vougeot", wineName: "Chinon"))
    }
}
