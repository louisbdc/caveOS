import Foundation

enum MenuMatching {
    static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Match si le nom correspond (égalité ou inclusion normalisée) et,
    /// quand les deux producteurs sont présents, qu'ils correspondent aussi.
    static func matches(candidateProducer: String?, candidateName: String?,
                        wineProducer: String?, wineName: String?) -> Bool {
        guard let cName = candidateName.map(normalize), !cName.isEmpty,
              let wName = wineName.map(normalize), !wName.isEmpty else { return false }
        let nameOK = cName == wName || cName.contains(wName) || wName.contains(cName)
        guard nameOK else { return false }
        if let cp = candidateProducer.map(normalize), !cp.isEmpty,
           let wp = wineProducer.map(normalize), !wp.isEmpty {
            return cp == wp || cp.contains(wp) || wp.contains(cp)
        }
        return true
    }
}
