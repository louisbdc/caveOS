import XCTest
@testable import CaveOS

final class MenuRankingEngineTests: XCTestCase {
    private func wine(_ name: String, color: WineColor?, region: String?, price: Double?, line: Int, vintage: Int? = nil) -> ScannedMenuWine {
        let json = """
        {"wineName":"\(name)","color":\(color.map { "\"\($0.rawValue)\"" } ?? "null"),
         "region":\(region.map { "\"\($0)\"" } ?? "null"),
         "vintage":\(vintage.map { "\($0)" } ?? "null"),
         "price":\(price.map { "\($0)" } ?? "null"),"lineIndex":\(line)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(ScannedMenuWine.self, from: json)
    }

    func testSortByValuePutsGoodValueFirst() {
        let wines = [
            wine("Cher", color: .red, region: "R", price: 120, line: 0),
            wine("BonQP", color: .red, region: "R", price: 20, line: 1),
        ]
        let ranked = MenuRankingEngine.rank(
            wines, dish: nil,
            tierLookup: { _ in .mid },
            cellarLookup: { _ in (0, nil) },
            now: 2026)
        let sorted = MenuRankingEngine.sort(ranked, by: .value)
        XCTAssertEqual(sorted.first?.wine.wineName, "BonQP")
    }

    func testSortByPriceAscending() {
        let wines = [
            wine("B", color: .red, region: "R", price: 50, line: 0),
            wine("A", color: .red, region: "R", price: 30, line: 1),
        ]
        let ranked = MenuRankingEngine.rank(wines, dish: nil, tierLookup: { _ in .mid },
                                            cellarLookup: { _ in (0, nil) }, now: 2026)
        let sorted = MenuRankingEngine.sort(ranked, by: .price)
        XCTAssertEqual(sorted.first?.wine.wineName, "A")
    }

    // MARK: - drinkNow reflète la fenêtre d'apogée
    //
    // `MenuRankingEngine.rank` appelle `ApogeeEngine.window(..., storage: .good)`.
    // Avec tier `.mid` (multiplier 1.0) et storage `.good` (multiplier 0.85),
    // facteur = 0.85 sur le profil défaut (min 3 / max 15) :
    //   drinkFrom = vintage + round(3 * 0.85)  = vintage + round(2.55)  = vintage + 3
    //   drinkBy   = vintage + round(15 * 0.85) = vintage + round(12.75) = vintage + 13
    // Donc fenêtre = [vintage + 3, vintage + 13].
    func testDrinkNowReflectsApogeeWindow() {
        // vintage 2015 -> fenêtre [2018, 2028]. now 2026 tombe DANS la fenêtre.
        let inWindow = [wine("Mûr", color: .red, region: "R", price: 40, line: 0, vintage: 2015)]
        let rankedIn = MenuRankingEngine.rank(inWindow, dish: nil,
                                              tierLookup: { _ in .mid },
                                              cellarLookup: { _ in (0, nil) }, now: 2026)
        XCTAssertTrue(rankedIn[0].drinkNow)

        // vintage 2026 -> fenêtre [2029, 2039]. now 2026 est AVANT drinkFrom.
        let beforeWindow = [wine("Jeune", color: .red, region: "R", price: 40, line: 0, vintage: 2026)]
        let rankedBefore = MenuRankingEngine.rank(beforeWindow, dish: nil,
                                                  tierLookup: { _ in .mid },
                                                  cellarLookup: { _ in (0, nil) }, now: 2026)
        XCTAssertFalse(rankedBefore[0].drinkNow)
    }

    // MARK: - Tri par accord met le meilleur match en tête
    //
    // "magret de canard" -> la règle "Viande rouge" (colors [.red]) l'emporte
    // dans `PairingEngine.suggest`. Le rouge obtient `.perfect`, le blanc `.poor`.
    func testSortByPairingPutsBestMatchFirst() {
        let wines = [
            wine("Blanc", color: .white, region: "R", price: 40, line: 0),
            wine("Rouge", color: .red, region: "R", price: 40, line: 1),
        ]
        let ranked = MenuRankingEngine.rank(wines, dish: "magret de canard",
                                            tierLookup: { _ in .mid },
                                            cellarLookup: { _ in (0, nil) }, now: 2026)
        let sorted = MenuRankingEngine.sort(ranked, by: .pairing)
        XCTAssertEqual(sorted.first?.wine.color, .red)
    }

    // MARK: - cellarLookup est reflété dans le résultat
    func testCellarLookupIsReflected() {
        let wines = [wine("EnCave", color: .red, region: "R", price: 40, line: 7)]
        let ranked = MenuRankingEngine.rank(wines, dish: nil,
                                            tierLookup: { _ in .mid },
                                            cellarLookup: { _ in (count: 3, score: 92) }, now: 2026)
        let entry = ranked.first { $0.wine.wineName == "EnCave" }
        XCTAssertEqual(entry?.cellarCount, 3)
        XCTAssertEqual(entry?.personalScore, 92)
    }
}
