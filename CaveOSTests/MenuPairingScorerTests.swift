import XCTest
@testable import CaveOS

final class MenuPairingScorerTests: XCTestCase {
    func testRedWineMatchesRedMeatSuggestion() {
        let s = PairingEngine.suggest(forDish: "magret de canard")
        let score = MenuPairingScorer.score(wineColor: .red, suggestion: s)
        XCTAssertGreaterThanOrEqual(score.rawValue, PairingScore.good.rawValue)
    }

    func testUnknownColorIsPoor() {
        let s = PairingEngine.suggest(forDish: "magret de canard")
        XCTAssertEqual(MenuPairingScorer.score(wineColor: nil, suggestion: s), .poor)
    }
}
