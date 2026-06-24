import SwiftUI

/// Jeton de design CaveOS — esthétique « cave premium » (bordeaux profond, or, ardoise).
enum Theme {
    static let wine = Color(red: 0.45, green: 0.07, blue: 0.13)
    static let wineDark = Color(red: 0.28, green: 0.05, blue: 0.09)
    static let gold = Color(red: 0.78, green: 0.62, blue: 0.30)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let slate = Color(red: 0.18, green: 0.18, blue: 0.20)

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
