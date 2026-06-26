import Foundation

/// Moteur de calcul de la fenêtre d'apogée d'une bouteille.
///
/// La fenêtre de base (en années depuis le millésime) est déterminée par ordre
/// de priorité :
/// 1. Override manuel sur la `Bottle` (`apogee*Override`)
/// 2. Override de base sur le `Wine` (`baseApogee*`)
/// 3. Valeur par défaut (3, 8, 15)
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

    private static let defaultProfile = (min: 3.0, peak: 8.0, max: 15.0)

    // MARK: - Fonction pure

    /// Calcule la fenêtre d'apogée (années absolues) à partir de champs bruts.
    /// Renvoie `nil` si le millésime est absent ou nul.
    ///
    /// Utilisé pour les entrées sans `Bottle` (ex. carte de restaurant scannée).
    /// Le profil de garde appliqué est le profil par défaut (3/8/15) car les
    /// données d'apogée propres à chaque cépage ne sont pas accessibles depuis
    /// leur seul nom.
    static func window(
        vintage: Int?,
        grapes: [String],
        regionTier: QualityTier?,
        storage: StorageQuality
    ) -> Window? {
        guard let vintage, vintage > 0 else { return nil }
        let factor = (regionTier?.multiplier ?? 1.0) * storage.multiplier
        return Window(
            drinkFrom: vintage + Int((defaultProfile.min * factor).rounded()),
            peak: vintage + Int((defaultProfile.peak * factor).rounded()),
            drinkBy: vintage + Int((defaultProfile.max * factor).rounded())
        )
    }

    // MARK: - Calcul depuis une Bottle

    /// Calcule la fenêtre d'apogée (années absolues) d'une bouteille.
    /// Renvoie `nil` si le millésime est absent ou nul (vin non millésimé).
    ///
    /// La fenêtre est en années absolues (millésime + années ajustées) : elle ne
    /// dépend donc pas de la date courante, contrairement à `status(for:now:)`.
    static func window(for bottle: Bottle) -> Window? {
        guard let vintage = bottle.vintage, vintage > 0 else { return nil }

        let regionTier = bottle.wine?.region?.qualityTier
        let storage = bottle.storageQuality

        // 1. Override manuel sur la bouteille (les trois doivent être présents).
        if let min = bottle.apogeeMinOverride,
           let peak = bottle.apogeePeakOverride,
           let max = bottle.apogeeMaxOverride {
            let factor = (regionTier?.multiplier ?? 1.0) * storage.multiplier
            return Window(
                drinkFrom: vintage + Int((Double(min) * factor).rounded()),
                peak: vintage + Int((Double(peak) * factor).rounded()),
                drinkBy: vintage + Int((Double(max) * factor).rounded())
            )
        }

        // 2. Override de base sur le vin.
        if let wine = bottle.wine,
           let min = wine.baseApogeeMin,
           let peak = wine.baseApogeePeak,
           let max = wine.baseApogeeMax {
            let factor = (regionTier?.multiplier ?? 1.0) * storage.multiplier
            return Window(
                drinkFrom: vintage + Int((Double(min) * factor).rounded()),
                peak: vintage + Int((Double(peak) * factor).rounded()),
                drinkBy: vintage + Int((Double(max) * factor).rounded())
            )
        }

        // 3. Branche calculée : délègue à la fonction pure (profil par défaut).
        return window(
            vintage: vintage,
            grapes: bottle.wine?.grapes.map(\.name) ?? [],
            regionTier: regionTier,
            storage: storage
        )
    }

    // MARK: - Statut

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
}
