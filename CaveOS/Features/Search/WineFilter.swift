import Foundation

/// Critères de recherche/filtrage appliqués en mémoire sur les bouteilles.
/// Struct conçue pour un usage immuable : on en crée toujours une nouvelle copie.
struct WineFilter: Equatable {
    var text: String = ""
    var colors: Set<WineColor> = []
    var statuses: Set<ApogeeStatus> = []
    var minPrice: Double? = nil
    var maxPrice: Double? = nil
    var regionName: String? = nil
    var grapeName: String? = nil
    var appellationName: String? = nil
    var vintageMin: Int? = nil
    var vintageMax: Int? = nil
    var locationName: String? = nil

    /// Aucun critère actif (hors texte vide).
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && colors.isEmpty
            && statuses.isEmpty
            && minPrice == nil
            && maxPrice == nil
            && regionName == nil
            && grapeName == nil
            && appellationName == nil
            && vintageMin == nil
            && vintageMax == nil
            && locationName == nil
    }

    /// Indique si une bouteille satisfait l'ensemble des critères.
    func matches(_ bottle: Bottle, now: Date) -> Bool {
        matchesText(bottle)
            && matchesColor(bottle)
            && matchesStatus(bottle, now: now)
            && matchesPrice(bottle)
            && matchesRegion(bottle)
            && matchesGrape(bottle)
            && matchesAppellation(bottle)
            && matchesVintage(bottle)
            && matchesLocation(bottle)
    }

    // MARK: - Sous-critères

    private func matchesText(_ bottle: Bottle) -> Bool {
        let needle = text.folded
        guard !needle.isEmpty else { return true }

        let wine = bottle.wine
        let haystacks: [String?] = [
            wine?.name,
            wine?.producer?.name,
            wine?.appellation?.name,
            wine?.region?.name
        ]
        return haystacks.contains { ($0?.folded ?? "").contains(needle) }
    }

    private func matchesColor(_ bottle: Bottle) -> Bool {
        guard !colors.isEmpty else { return true }
        guard let color = bottle.wine?.color else { return false }
        return colors.contains(color)
    }

    private func matchesStatus(_ bottle: Bottle, now: Date) -> Bool {
        guard !statuses.isEmpty else { return true }
        return statuses.contains(ApogeeEngine.status(for: bottle, now: now))
    }

    private func matchesPrice(_ bottle: Bottle) -> Bool {
        guard minPrice != nil || maxPrice != nil else { return true }
        guard let price = bottle.purchasePrice else { return false }
        if let min = minPrice, price < min { return false }
        if let max = maxPrice, price > max { return false }
        return true
    }

    private func matchesRegion(_ bottle: Bottle) -> Bool {
        guard let regionName else { return true }
        return bottle.wine?.region?.name == regionName
    }

    private func matchesGrape(_ bottle: Bottle) -> Bool {
        guard let grapeName else { return true }
        let grapes = bottle.wine?.grapes ?? []
        return grapes.contains { $0.name == grapeName }
    }

    private func matchesAppellation(_ bottle: Bottle) -> Bool {
        guard let appellationName else { return true }
        return bottle.wine?.appellation?.name == appellationName
    }

    private func matchesVintage(_ bottle: Bottle) -> Bool {
        guard vintageMin != nil || vintageMax != nil else { return true }
        guard let vintage = bottle.vintage, vintage > 0 else { return false }
        if let min = vintageMin, vintage < min { return false }
        if let max = vintageMax, vintage > max { return false }
        return true
    }

    private func matchesLocation(_ bottle: Bottle) -> Bool {
        guard let locationName else { return true }
        guard let location = bottle.location else { return false }
        return location.cellar?.name == locationName || location.label == locationName
    }
}

private extension String {
    /// Normalisation pour une comparaison insensible à la casse et aux accents.
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
