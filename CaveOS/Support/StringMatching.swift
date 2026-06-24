import Foundation

extension String {
    /// Normalisation pour comparer deux libellés (producteur, appellation, cépage)
    /// indépendamment de la casse, des accents et des espaces superflus.
    var foldedForMatch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
