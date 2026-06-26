import SwiftUI

/// Forme du gabarit affiché par `BlueprintOverlay`.
///
/// - `bottle` : silhouette de bouteille (scan d'étiquette).
/// - `document` : cadre rectangulaire portrait (scan d'une carte des vins à plat).
enum BlueprintShapeKind {
    case bottle
    case document
}

/// Calque « blueprint » posé au-dessus de la preview caméra : voile sombre percé
/// d'une fenêtre (bouteille ou document), contour doré pointillé et consigne de
/// cadrage.
///
/// Le gabarit est positionné DANS le safe area (pas `.ignoresSafeArea()`) : il
/// reste sous la barre de navigation et au-dessus de l'indicateur home, donc ne
/// « remonte » plus sous la Dynamic Island.
///
/// Entièrement décoratif : `allowsHitTesting(false)` pour laisser le shutter et la
/// preview recevoir les taps.
struct BlueprintOverlay: View {
    /// Opacité du voile sombre autour de la silhouette (0 = aucun voile).
    /// Élevée en capture IA (focalise le cadrage) ; faible en scan « Appareil »
    /// (OCR live) pour garder l'étiquette parfaitement lisible.
    var dimming: Double = 0.45

    /// Forme du gabarit. Bouteille par défaut (scan d'étiquette).
    var kind: BlueprintShapeKind = .bottle

    var body: some View {
        GeometryReader { geo in
            let rect = blueprintRect(in: geo.size)

            ZStack {
                // Voile sombre + découpe (effet « fenêtre » via destinationOut).
                Rectangle()
                    .fill(.black.opacity(dimming))
                    .reverseMask {
                        blueprintPath(in: rect).fill(.black)
                    }

                // Contour pointillé doré.
                blueprintPath(in: rect)
                    .stroke(Theme.gold.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))

                // Zone étiquette suggérée (bouteille uniquement).
                if kind == .bottle {
                    LabelZoneShape().path(in: rect)
                        .stroke(Theme.gold.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                }

                consigne(in: geo.size, topY: rect.minY)
            }
            .allowsHitTesting(false) // ne capte pas les taps : shutter/preview restent actifs
        }
        // Volontairement SANS `.ignoresSafeArea()` : le gabarit se cale dans la zone
        // visible (sous la nav bar), corrigeant le décalage vers le haut.
    }

    // MARK: - Géométrie du gabarit

    /// Rect du gabarit, centré dans l'espace fourni avec une légère remontée pour
    /// laisser la place à l'obturateur en bas.
    private func blueprintRect(in size: CGSize) -> CGRect {
        switch kind {
        case .bottle:
            let h = size.height * 0.70
            let w = min(size.width * 0.60, h * 0.34)
            return centered(width: w, height: h, in: size, raise: 0.03)
        case .document:
            // Carte des vins : page portrait (ratio ~A4 1.4), large et haute.
            let w = size.width * 0.80
            let h = min(size.height * 0.82, w * 1.4)
            return centered(width: w, height: h, in: size, raise: 0.02)
        }
    }

    /// Centre un rect de dimensions données dans `size`, remonté de `raise`×hauteur.
    private func centered(width w: CGFloat, height h: CGFloat, in size: CGSize, raise: CGFloat) -> CGRect {
        CGRect(
            x: (size.width - w) / 2,
            y: (size.height - h) / 2 - size.height * raise,
            width: w,
            height: h
        )
    }

    private func blueprintPath(in rect: CGRect) -> Path {
        switch kind {
        case .bottle:   return BottleBlueprintShape().path(in: rect)
        case .document: return DocumentBlueprintShape().path(in: rect)
        }
    }

    // MARK: - Consigne

    /// Bandeau d'instruction positionné juste au-dessus du gabarit.
    private func consigne(in size: CGSize, topY: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.ultraThinMaterial, in: Capsule())
        .position(x: size.width / 2,
                  y: max(topY - Theme.Spacing.l, Theme.Spacing.m))
    }

    private var title: String {
        switch kind {
        case .bottle:   return "Alignez la bouteille"
        case .document: return "Cadrez la carte des vins"
        }
    }

    private var icon: String {
        switch kind {
        case .bottle:   return "wineglass"
        case .document: return "doc.text"
        }
    }

    private var subtitle: String {
        switch kind {
        case .bottle:   return "Étiquette bien à plat, lisible et nette"
        case .document: return "Carte à plat, lisible et bien éclairée"
        }
    }
}

// MARK: - Masque inversé

extension View {
    /// Découpe (« trou ») la vue selon le contenu fourni, via `destinationOut`.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
