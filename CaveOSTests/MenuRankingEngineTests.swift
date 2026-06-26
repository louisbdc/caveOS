import XCTest
@testable import CaveOS

final class MenuRankingEngineTests: XCTestCase {
    private func wine(_ name: String, color: WineColor?, region: String?, price: Double?, line: Int) -> ScannedMenuWine {
        let json = """
        {"wineName":"\(name)","color":\(color.map { "\"\($0.rawValue)\"" } ?? "null"),
         "region":\(region.map { "\"\($0)\"" } ?? "null"),
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
}
