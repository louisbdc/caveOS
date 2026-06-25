import SwiftUI

/// Calque « blueprint » posé au-dessus de la preview caméra : voile sombre percé
/// d'une fenêtre en forme de bouteille, contour doré pointillé, zone d'étiquette
/// suggérée et consigne de cadrage.
///
/// Entièrement décoratif : `allowsHitTesting(false)` pour laisser le shutter et la
/// preview recevoir les taps.
struct BlueprintOverlay: View {
    /// Opacité du voile sombre autour de la silhouette (0 = aucun voile).
    /// Élevée en capture IA (focalise le cadrage) ; faible en scan « Appareil »
    /// (OCR live) pour garder l'étiquette parfaitement lisible.
    var dimming: Double = 0.45

    var body: some View {
        GeometryReader { geo in
            // Rect bouteille : centré, ratio fixe (~0.34) pour ne pas déformer.
            let bottleH = geo.size.height * 0.74
            let bottleW = min(geo.size.width * 0.62, bottleH * 0.34)
            let bottleRect = CGRect(
                x: (geo.size.width - bottleW) / 2,
                y: (geo.size.height - bottleH) / 2 - geo.size.height * 0.04,
                width: bottleW,
                height: bottleH
            )

            ZStack {
                // Voile sombre + découpe bouteille (effet « fenêtre » via destinationOut).
                Rectangle()
                    .fill(.black.opacity(dimming))
                    .reverseMask {
                        BottleBlueprintShape().path(in: bottleRect).fill(.black)
                    }

                // Contour bouteille pointillé doré.
                BottleBlueprintShape().path(in: bottleRect)
                    .stroke(Theme.gold.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))

                // Zone étiquette suggérée.
                LabelZoneShape().path(in: bottleRect)
                    .stroke(Theme.gold.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))

                consigne(in: geo.size, bottleTopY: bottleRect.minY)
            }
            .allowsHitTesting(false) // ne capte pas les taps : shutter/preview restent actifs
        }
        .ignoresSafeArea()
    }

    /// Bandeau d'instruction positionné juste au-dessus de la silhouette.
    private func consigne(in size: CGSize, bottleTopY: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Label("Alignez la bouteille", systemImage: "wineglass")
                .font(.headline)
            Text("Étiquette bien à plat, lisible et nette")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.ultraThinMaterial, in: Capsule())
        .position(x: size.width / 2,
                  y: max(bottleTopY - Theme.Spacing.l, Theme.Spacing.xl))
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
