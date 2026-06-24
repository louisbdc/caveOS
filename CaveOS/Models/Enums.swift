import SwiftUI

// MARK: - Couleur du vin
enum WineColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case red, white, rose, sparkling, sweet, fortified, orange
    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Rouge"
        case .white: return "Blanc"
        case .rose: return "Rosé"
        case .sparkling: return "Effervescent"
        case .sweet: return "Liquoreux"
        case .fortified: return "Fortifié"
        case .orange: return "Orange"
        }
    }

    /// Teinte adaptative (sombre en mode clair, claire en mode sombre) pour viser
    /// un contraste WCAG AA, tout en gardant l'identité de chaque couleur de vin.
    var tint: Color {
        switch self {
        case .red:
            return .adaptive(light: (0.45, 0.07, 0.13), dark: (0.95, 0.45, 0.50))
        case .white:
            return .adaptive(light: (0.42, 0.33, 0.05), dark: (0.92, 0.83, 0.48))
        case .rose:
            return .adaptive(light: (0.62, 0.18, 0.28), dark: (0.97, 0.64, 0.70))
        case .sparkling:
            return .adaptive(light: (0.44, 0.34, 0.06), dark: (0.95, 0.85, 0.55))
        case .sweet:
            return .adaptive(light: (0.46, 0.31, 0.03), dark: (0.93, 0.74, 0.34))
        case .fortified:
            return .adaptive(light: (0.40, 0.20, 0.18), dark: (0.85, 0.52, 0.46))
        case .orange:
            return .adaptive(light: (0.54, 0.27, 0.04), dark: (0.97, 0.63, 0.33))
        }
    }
}

// MARK: - Type de vin
enum WineType: String, CaseIterable, Codable, Identifiable, Sendable {
    case still, sparkling, fortified, sweet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .still: return "Tranquille"
        case .sparkling: return "Effervescent"
        case .fortified: return "Fortifié"
        case .sweet: return "Liquoreux"
        }
    }
}

// MARK: - Format de bouteille (contenance en centilitres)
enum BottleFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case piccolo, demi, bottle, magnum, doubleMagnum, jeroboam, rehoboam, mathusalem, salmanazar, balthazar, nabuchodonosor
    var id: String { rawValue }

    var centiliters: Int {
        switch self {
        case .piccolo: return 20
        case .demi: return 37
        case .bottle: return 75
        case .magnum: return 150
        case .doubleMagnum: return 300
        case .jeroboam: return 300
        case .rehoboam: return 450
        case .mathusalem: return 600
        case .salmanazar: return 900
        case .balthazar: return 1200
        case .nabuchodonosor: return 1500
        }
    }

    var label: String {
        switch self {
        case .piccolo: return "Piccolo (20 cl)"
        case .demi: return "Demi (37,5 cl)"
        case .bottle: return "Bouteille (75 cl)"
        case .magnum: return "Magnum (1,5 L)"
        case .doubleMagnum: return "Double Magnum (3 L)"
        case .jeroboam: return "Jéroboam (3 L)"
        case .rehoboam: return "Réhoboam (4,5 L)"
        case .mathusalem: return "Mathusalem (6 L)"
        case .salmanazar: return "Salmanazar (9 L)"
        case .balthazar: return "Balthazar (12 L)"
        case .nabuchodonosor: return "Nabuchodonosor (15 L)"
        }
    }
}

// MARK: - État d'une bouteille
enum BottleState: String, CaseIterable, Codable, Identifiable, Sendable {
    case inCellar, opened, consumed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inCellar: return "En cave"
        case .opened: return "Entamée"
        case .consumed: return "Consommée"
        }
    }
    var symbol: String {
        switch self {
        case .inCellar: return "archivebox"
        case .opened: return "wineglass"
        case .consumed: return "checkmark.circle"
        }
    }
}

// MARK: - Méthode de conservation (bouteille entamée)
enum ConservationMethod: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, coravin, stopper, pump, vacuum, inertGas
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Aucune"
        case .coravin: return "Coravin"
        case .stopper: return "Bouchon"
        case .pump: return "Pompe à vide"
        case .vacuum: return "Sous vide"
        case .inertGas: return "Gaz inerte"
        }
    }
}

// MARK: - Type de cave
enum CellarType: String, CaseIterable, Codable, Identifiable, Sendable {
    case electric, natural, cabinet, rack, bulk
    var id: String { rawValue }
    var label: String {
        switch self {
        case .electric: return "Cave électrique"
        case .natural: return "Cave naturelle"
        case .cabinet: return "Armoire"
        case .rack: return "Casier"
        case .bulk: return "Stockage en vrac"
        }
    }
    var symbol: String {
        switch self {
        case .electric: return "refrigerator"
        case .natural: return "mountain.2"
        case .cabinet: return "cabinet"
        case .rack: return "square.grid.3x3"
        case .bulk: return "shippingbox"
        }
    }
}

// MARK: - Type d'emplacement
enum LocationKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case shelf, zone, bulk
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shelf: return "Clayette"
        case .zone: return "Zone"
        case .bulk: return "Vrac"
        }
    }
}

// MARK: - Niveau de qualité d'une région (multiplicateur apogée)
enum QualityTier: String, CaseIterable, Codable, Identifiable, Sendable {
    case premium, mid, entry
    var id: String { rawValue }
    var label: String {
        switch self {
        case .premium: return "Premium"
        case .mid: return "Milieu de gamme"
        case .entry: return "Entrée de gamme"
        }
    }
    var multiplier: Double {
        switch self {
        case .premium: return 1.4
        case .mid: return 1.0
        case .entry: return 0.6
        }
    }
}

// MARK: - Qualité de stockage (multiplicateur apogée)
enum StorageQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    case ideal, good, average, poor
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ideal: return "Idéal"
        case .good: return "Bon"
        case .average: return "Moyen"
        case .poor: return "Mauvais"
        }
    }
    var multiplier: Double {
        switch self {
        case .ideal: return 1.0
        case .good: return 0.85
        case .average: return 0.6
        case .poor: return 0.4
        }
    }
}

// MARK: - Statut d'apogée (fenêtre de consommation)
enum ApogeeStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case tooYoung, ready, peak, drinkSoon, past, unknown
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tooYoung: return "Trop jeune"
        case .ready: return "Prêt à boire"
        case .peak: return "À l'apogée"
        case .drinkSoon: return "À boire vite"
        case .past: return "Passé"
        case .unknown: return "Inconnu"
        }
    }
    /// Teinte adaptative (sombre en mode clair, claire en mode sombre) pour viser
    /// un contraste WCAG AA dans les deux thèmes.
    var tint: Color {
        switch self {
        case .tooYoung:
            return .adaptive(light: (0.12, 0.32, 0.72), dark: (0.55, 0.74, 1.00))
        case .ready:
            return .adaptive(light: (0.12, 0.34, 0.18), dark: (0.52, 0.86, 0.64))
        case .peak:
            return .adaptive(light: (0.06, 0.36, 0.24), dark: (0.46, 0.88, 0.55))
        case .drinkSoon:
            return .adaptive(light: (0.48, 0.29, 0.02), dark: (0.98, 0.72, 0.32))
        case .past:
            return .adaptive(light: (0.62, 0.16, 0.12), dark: (0.95, 0.50, 0.43))
        case .unknown:
            return .adaptive(light: (0.34, 0.34, 0.36), dark: (0.70, 0.70, 0.74))
        }
    }
    var symbol: String {
        switch self {
        case .tooYoung: return "hourglass.bottomhalf.filled"
        case .ready: return "checkmark.seal"
        case .peak: return "star.fill"
        case .drinkSoon: return "exclamationmark.triangle"
        case .past: return "xmark.seal"
        case .unknown: return "questionmark.circle"
        }
    }
}
