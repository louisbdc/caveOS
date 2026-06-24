import Foundation

/// Critère de tri composable pour la liste de bouteilles.
enum SortOption: String, CaseIterable, Identifiable {
    case name, vintage, price, dateAdded
    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Nom"
        case .vintage: return "Millésime"
        case .price: return "Prix"
        case .dateAdded: return "Date d'ajout"
        }
    }

    /// Ordre naturel ascendant, composable (permet le tri multi-critères).
    func order(_ a: Bottle, _ b: Bottle) -> ComparisonResult {
        switch self {
        case .name:
            return (a.wine?.name ?? "").localizedCaseInsensitiveCompare(b.wine?.name ?? "")
        case .vintage:
            return compare(a.vintage ?? 0, b.vintage ?? 0)
        case .price:
            return compare(a.purchasePrice ?? 0, b.purchasePrice ?? 0)
        case .dateAdded:
            return compare(a.createdAt, b.createdAt)
        }
    }

    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}

/// Fourchettes de prix prédéfinies pour le filtre.
enum PriceRange: String, CaseIterable, Identifiable {
    case under15, from15to30, from30to60, from60to120, over120
    var id: String { rawValue }

    var label: String {
        switch self {
        case .under15: return "Moins de 15 €"
        case .from15to30: return "15 – 30 €"
        case .from30to60: return "30 – 60 €"
        case .from60to120: return "60 – 120 €"
        case .over120: return "Plus de 120 €"
        }
    }

    var min: Double? {
        switch self {
        case .under15: return nil
        case .from15to30: return 15
        case .from30to60: return 30
        case .from60to120: return 60
        case .over120: return 120
        }
    }

    var max: Double? {
        switch self {
        case .under15: return 15
        case .from15to30: return 30
        case .from30to60: return 60
        case .from60to120: return 120
        case .over120: return nil
        }
    }
}

extension ComparisonResult {
    var inverted: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

extension Set {
    /// Bascule la présence d'un élément (utile pour les filtres multi-sélection).
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}
