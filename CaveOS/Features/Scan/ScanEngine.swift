import Foundation

/// Moteur d'analyse d'étiquette choisi par l'utilisateur.
///
/// `device` reste gratuit et hors-ligne (Apple Vision + `LabelParser`). Les moteurs
/// d'IA délèguent l'extraction structurée à un fournisseur distant via le serveur
/// CaveOS et sont réservés aux abonnés Pro. Ajouter un fournisseur se limite à
/// ajouter un `case` ici (et son implémentation côté serveur).
enum ScanEngine: String, CaseIterable, Identifiable {
    case device
    case mistral
    case gemini

    /// Clé `@AppStorage` partagée pour persister le choix.
    static let storageKey = "caveos.scanEngine"

    var id: String { rawValue }

    /// Libellé court affiché dans le sélecteur segmenté.
    var label: String {
        switch self {
        case .device: return "Appareil"
        case .mistral: return "Mistral"
        case .gemini: return "Gemini"
        }
    }

    var systemImage: String {
        switch self {
        case .device: return "iphone"
        case .mistral, .gemini: return "sparkles"
        }
    }

    /// Phrase affichée après analyse pour indiquer le moteur réellement utilisé.
    var analysisLabel: String {
        switch self {
        case .device: return "Analysé sur l'appareil"
        case .mistral: return "Analysé par Mistral"
        case .gemini: return "Analysé par Gemini"
        }
    }

    /// `true` si le moteur délègue à un fournisseur d'IA distant (réservé Pro).
    var isAI: Bool { self != .device }

    /// Identifiant du fournisseur transmis au serveur, ou `nil` pour le moteur local.
    var providerKey: String? { isAI ? rawValue : nil }
}
