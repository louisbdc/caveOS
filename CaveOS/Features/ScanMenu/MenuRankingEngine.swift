import Foundation

struct RankedMenuWine: Identifiable {
    let wine: ScannedMenuWine
    let value: ValueVerdict
    let pairing: PairingScore?
    let drinkNow: Bool
    let cellarCount: Int
    let personalScore: Int?
    var id: Int { wine.lineIndex }
}

enum MenuSort { case pairing, value, price }

enum MenuRankingEngine {
    static func rank(
        _ wines: [ScannedMenuWine],
        dish: String?,
        tierLookup: (String?) -> QualityTier?,
        cellarLookup: (ScannedMenuWine) -> (count: Int, score: Int?),
        now: Int
    ) -> [RankedMenuWine] {
        let suggestion: PairingSuggestion? = dish.flatMap { d in
            d.isEmpty ? nil : PairingEngine.suggest(forDish: d)
        }
        return wines.map { w in
            let tier = tierLookup(w.region)
            let value = MenuValueEngine.verdict(tier: tier, price: w.price)
            let pairing = suggestion.map { MenuPairingScorer.score(wineColor: w.color, suggestion: $0) }
            let window = ApogeeEngine.window(
                vintage: w.vintage,
                grapes: w.grapes ?? [],
                regionTier: tier,
                storage: .good
            )
            let drinkNow = window.map { now >= $0.drinkFrom && now <= $0.drinkBy } ?? false
            let cellar = cellarLookup(w)
            return RankedMenuWine(
                wine: w,
                value: value,
                pairing: pairing,
                drinkNow: drinkNow,
                cellarCount: cellar.count,
                personalScore: cellar.score
            )
        }
    }

    static func sort(_ ranked: [RankedMenuWine], by: MenuSort) -> [RankedMenuWine] {
        switch by {
        case .pairing:
            return ranked.sorted { ($0.pairing?.rawValue ?? -1) > ($1.pairing?.rawValue ?? -1) }
        case .value:
            return ranked.sorted { valueRank($0.value) > valueRank($1.value) }
        case .price:
            return ranked.sorted {
                ($0.wine.price ?? .greatestFiniteMagnitude) < ($1.wine.price ?? .greatestFiniteMagnitude)
            }
        }
    }

    private static func valueRank(_ v: ValueVerdict) -> Int {
        switch v {
        case .goodValue: return 3
        case .fair:      return 2
        case .expensive: return 1
        case .unknown:   return 0
        }
    }
}
