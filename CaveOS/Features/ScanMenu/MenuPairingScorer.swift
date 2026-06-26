import Foundation

enum PairingScore: Int {
    case poor = 0
    case ok = 1
    case good = 2
    case perfect = 3
}

enum MenuPairingScorer {
    static func score(wineColor: WineColor?, suggestion: PairingSuggestion) -> PairingScore {
        guard let wineColor else { return .poor }
        guard suggestion.colors.contains(wineColor) else { return .poor }
        // Couleur dans les couleurs conseillées : perfect si unique conseil, sinon good.
        return suggestion.colors.count == 1 ? .perfect : .good
    }
}
