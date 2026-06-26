import Foundation

enum MenuMatching {
    static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Égalité floue : autorise la sous-chaîne uniquement si les deux chaînes
    /// normalisées font au moins 4 caractères ; sinon exige l'égalité stricte.
    /// Évite les faux positifs sur tokens courts (« or » ⊂ « cahors »).
    private static func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 4, b.count >= 4 else { return false }
        return a.contains(b) || b.contains(a)
    }

    /// Match si le nom correspond (égalité ou inclusion normalisée bornée) et,
    /// quand les deux producteurs sont présents, qu'ils correspondent aussi.
    static func matches(candidateProducer: String?, candidateName: String?,
                        wineProducer: String?, wineName: String?) -> Bool {
        guard let cName = candidateName.map(normalize), !cName.isEmpty,
              let wName = wineName.map(normalize), !wName.isEmpty else { return false }
        guard fuzzyEqual(cName, wName) else { return false }
        if let cp = candidateProducer.map(normalize), !cp.isEmpty,
           let wp = wineProducer.map(normalize), !wp.isEmpty {
            return fuzzyEqual(cp, wp)
        }
        return true
    }
}
