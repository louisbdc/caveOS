import Foundation

/// Moteur d'analyse d'étiquette choisi par l'utilisateur.
///
/// `device` reste gratuit, hors-ligne et illimité (Apple Vision + `LabelParser`).
/// Le moteur `ai` délègue l'extraction structurée au serveur CaveOS qui orchestre
/// les deux passes (lecture Mistral + Gemini, puis déduction) ; il est soumis au
/// quota de scans IA gratuits puis réservé aux abonnés Pro.
enum ScanEngine: String, CaseIterable, Identifiable {
    case device
    case ai

    /// Clé `@AppStorage` partagée pour persister le choix.
    static let storageKey = "caveos.scanEngine"

    var id: String { rawValue }

    /// Libellé court affiché dans le sélecteur segmenté.
    var label: String {
        switch self {
        case .device: return "Appareil"
        case .ai: return "IA"
        }
    }

    var systemImage: String {
        switch self {
        case .device: return "iphone"
        case .ai: return "sparkles"
        }
    }

    /// Phrase affichée après analyse pour indiquer le moteur réellement utilisé.
    var analysisLabel: String {
        switch self {
        case .device: return "Analysé sur l'appareil"
        case .ai: return "Analysé par IA (Mistral + Gemini)"
        }
    }

    /// `true` si le moteur délègue aux fournisseurs distants (quota IA / Pro).
    var isAI: Bool { self == .ai }
}
