import SwiftUI
import UIKit

/// Jeton de design CaveOS — esthétique « cave premium » (bordeaux profond, or, ardoise).
enum Theme {
    /// Construit une couleur adaptative clair/sombre.
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Bordeaux signature : profond en clair, lumineux (rosé soutenu) en sombre pour ressortir sur le noir.
    static let wine = adaptive(light: (0.45, 0.07, 0.13), dark: (0.85, 0.32, 0.40))
    /// Bordeaux foncé pour dégradés/ombres : reste sombre mais éclairci en mode sombre.
    static let wineDark = adaptive(light: (0.28, 0.05, 0.09), dark: (0.55, 0.14, 0.21))
    /// Or premium, légèrement éclairci en sombre pour un meilleur contraste.
    static let gold = adaptive(light: (0.78, 0.62, 0.30), dark: (0.88, 0.72, 0.42))
    /// Crème de marque (fond onboarding, textes sur bordeaux) — constante, indépendante du thème.
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.89)
    /// Bordeaux profonds *constants* (non adaptatifs), réservés aux fonds toujours sombres (onboarding).
    static let wineDeep = Color(red: 0.45, green: 0.07, blue: 0.13)
    static let wineDeepest = Color(red: 0.28, green: 0.05, blue: 0.09)
    /// Ardoise (texte/pastilles neutres) adaptative pour rester lisible dans les deux thèmes.
    static let slate = adaptive(light: (0.18, 0.18, 0.20), dark: (0.74, 0.74, 0.78))

    /// Fond d'écran « ambiance cave » adaptatif : crème en clair, ardoise vineuse profonde en sombre.
    static let surface = adaptive(light: (0.96, 0.94, 0.89), dark: (0.10, 0.07, 0.08))

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
    }
}

/// Carte standard réutilisable.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.m)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

/// Mode d'apparence choisi par l'utilisateur (suivre le système, clair ou sombre).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// Clé `@AppStorage` partagée pour persister le choix.
    static let storageKey = "caveos.appearanceMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }

    /// Schéma de couleurs à imposer, ou `nil` pour suivre le système.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Pastille de statut (apogée, couleur, etc.).
struct StatusBadge: View {
    let text: String
    let color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }
}
