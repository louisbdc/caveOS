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

    var tint: Color {
        switch self {
        case .red: return Color(red: 0.45, green: 0.07, blue: 0.13)
        case .white: return Color(red: 0.85, green: 0.78, blue: 0.45)
        case .rose: return Color(red: 0.92, green: 0.55, blue: 0.60)
        case .sparkling: return Color(red: 0.90, green: 0.80, blue: 0.55)
        case .sweet: return Color(red: 0.80, green: 0.60, blue: 0.20)
        case .fortified: return Color(red: 0.40, green: 0.20, blue: 0.18)
        case .orange: return Color(red: 0.85, green: 0.50, blue: 0.20)
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
    var tint: Color {
        switch self {
        case .tooYoung: return Color(red: 0.30, green: 0.55, blue: 0.85)
        case .ready: return Color(red: 0.30, green: 0.70, blue: 0.45)
        case .peak: return Color(red: 0.20, green: 0.60, blue: 0.30)
        case .drinkSoon: return Color(red: 0.90, green: 0.65, blue: 0.20)
        case .past: return Color(red: 0.70, green: 0.25, blue: 0.20)
        case .unknown: return Color.gray
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
