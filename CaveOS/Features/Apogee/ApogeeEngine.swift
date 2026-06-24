import Foundation

/// Moteur de calcul de la fenêtre d'apogée d'une bouteille.
///
/// La fenêtre de base (en années depuis le millésime) est déterminée par ordre
/// de priorité :
/// 1. Override manuel sur la `Bottle` (`apogee*Override`)
/// 2. Override de base sur le `Wine` (`baseApogee*`)
/// 3. Moyenne des profils de garde des cépages (`Grape.apogee*`)
/// 4. Valeur par défaut (3, 8, 15)
///
/// La fenêtre est ensuite ajustée par deux multiplicateurs :
/// - le niveau de qualité de la région (`QualityTier.multiplier`)
/// - la qualité de stockage de la bouteille (`StorageQuality.multiplier`)
///
/// Le résultat est exprimé en années absolues (millésime + années ajustées).
enum ApogeeEngine {

    /// Fenêtre de consommation, en années absolues.
    struct Window {
        let drinkFrom: Int
        let peak: Int
        let drinkBy: Int
    }

    /// Profil de garde de base, en années depuis le millésime.
    private struct BaseProfile {
        let min: Double
        let peak: Double
        let max: Double
    }

    private static let defaultProfile = BaseProfile(min: 3, peak: 8, max: 15)

    /// Calcule la fenêtre d'apogée (années absolues) d'une bouteille.
    /// Renvoie `nil` si le millésime est absent ou nul (vin non millésimé).
    ///
    /// La fenêtre est en années absolues (millésime + années ajustées) : elle ne
    /// dépend donc pas de la date courante, contrairement à `status(for:now:)`.
    static func window(for bottle: Bottle) -> Window? {
        guard let vintage = bottle.vintage, vintage > 0 else { return nil }

        let base = baseProfile(for: bottle)
        let region = bottle.wine?.region?.qualityTier.multiplier ?? 1.0
        let storage = bottle.storageQuality.multiplier
        let factor = region * storage

        let drinkFrom = vintage + Int((base.min * factor).rounded())
        let peak = vintage + Int((base.peak * factor).rounded())
        let drinkBy = vintage + Int((base.max * factor).rounded())

        return Window(drinkFrom: drinkFrom, peak: peak, drinkBy: drinkBy)
    }

    /// Détermine le statut d'apogée d'une bouteille à la date donnée.
    static func status(for bottle: Bottle, now: Date = .now) -> ApogeeStatus {
        guard let window = window(for: bottle) else { return .unknown }

        let year = Calendar.current.component(.year, from: now)

        if year < window.drinkFrom {
            return .tooYoung
        }
        // À l'apogée si l'on est à ±1 an du pic.
        if abs(year - window.peak) <= 1 {
            return .peak
        }
        if year < window.peak {
            return .ready
        }
        if year < window.drinkBy {
            return .drinkSoon
        }
        return .past
    }

    // MARK: - Profil de base

    private static func baseProfile(for bottle: Bottle) -> BaseProfile {
        // 1. Override manuel sur la bouteille (les trois doivent être présents).
        if let min = bottle.apogeeMinOverride,
           let peak = bottle.apogeePeakOverride,
           let max = bottle.apogeeMaxOverride {
            return BaseProfile(min: Double(min), peak: Double(peak), max: Double(max))
        }

        // 2. Override de base sur le vin.
        if let wine = bottle.wine,
           let min = wine.baseApogeeMin,
           let peak = wine.baseApogeePeak,
           let max = wine.baseApogeeMax {
            return BaseProfile(min: Double(min), peak: Double(peak), max: Double(max))
        }

        // 3. Moyenne des cépages.
        if let grapes = bottle.wine?.grapes, !grapes.isEmpty {
            let count = Double(grapes.count)
            let min = grapes.reduce(0) { $0 + $1.apogeeMin }
            let peak = grapes.reduce(0) { $0 + $1.apogeePeak }
            let max = grapes.reduce(0) { $0 + $1.apogeeMax }
            return BaseProfile(
                min: Double(min) / count,
                peak: Double(peak) / count,
                max: Double(max) / count
            )
        }

        // 4. Valeur par défaut.
        return defaultProfile
    }
}
