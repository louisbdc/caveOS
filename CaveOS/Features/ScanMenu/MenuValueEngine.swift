import Foundation

enum ValueVerdict { case goodValue, fair, expensive, unknown }

enum MenuValueEngine {
    /// Bandes de prix resto attendues par tier (€). Calibrables ici, nulle part ailleurs.
    private struct Band { let low: Double; let high: Double }
    private static func band(for tier: QualityTier) -> Band {
        switch tier {
        case .entry:   return Band(low: 18, high: 30)
        case .mid:     return Band(low: 28, high: 45)
        case .premium: return Band(low: 50, high: 90)
        }
    }

    static func verdict(tier: QualityTier?, price: Double?) -> ValueVerdict {
        guard let tier, let price, price > 0 else { return .unknown }
        let b = band(for: tier)
        if price < b.low { return .goodValue }
        if price > b.high { return .expensive }
        return .fair
    }
}
