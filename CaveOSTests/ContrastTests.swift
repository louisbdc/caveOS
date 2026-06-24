import XCTest
import SwiftUI
import UIKit
@testable import CaveOS

/// Vérifie que les teintes des badges atteignent le contraste WCAG AA (4.5:1)
/// dans les deux thèmes, en tenant compte du rendu réel : le texte est la teinte
/// pleine, posée sur une capsule de la même teinte à 18 % au-dessus du fond.
final class ContrastTests: XCTestCase {

    /// Contraste minimal exigé (WCAG AA, texte normal).
    private let threshold = 4.5

    /// Opacité de fond de `StatusBadge`.
    private let badgeAlpha = 0.18

    /// Fonds adaptatifs réels (cf. `Theme.surface`).
    private let surfaceLight = (0.96, 0.94, 0.89)
    private let surfaceDark = (0.10, 0.07, 0.08)

    // MARK: - Tests

    func testApogeeStatusBadgeContrast() {
        for status in ApogeeStatus.allCases {
            assertBadgeContrast(status.tint, label: "Apogée « \(status.label) »")
        }
    }

    func testWineColorBadgeContrast() {
        for color in WineColor.allCases {
            assertBadgeContrast(color.tint, label: "Couleur « \(color.label) »")
        }
    }

    func testWarningAmberContrast() {
        assertBadgeContrast(Theme.amber, label: "Ambre d'avertissement")
    }

    // MARK: - Helpers

    private func assertBadgeContrast(
        _ tint: Color,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cases: [(String, UIUserInterfaceStyle, (Double, Double, Double))] = [
            ("clair", .light, surfaceLight),
            ("sombre", .dark, surfaceDark)
        ]
        for (name, style, surface) in cases {
            let text = rgb(tint, style: style)
            let background = blend(text, over: surface, alpha: badgeAlpha)
            let ratio = contrast(text, background)
            XCTAssertGreaterThanOrEqual(
                ratio, threshold,
                "\(label) en mode \(name) : \(String(format: "%.2f", ratio)):1 < \(threshold):1",
                file: file, line: line
            )
        }
    }

    /// Résout une `Color` (potentiellement adaptative) en composantes sRGB pour un thème donné.
    private func rgb(_ color: Color, style: UIUserInterfaceStyle) -> (Double, Double, Double) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// Mélange alpha en espace sRGB (rendu d'une capsule semi-transparente sur un fond opaque).
    private func blend(
        _ top: (Double, Double, Double),
        over bottom: (Double, Double, Double),
        alpha: Double
    ) -> (Double, Double, Double) {
        (
            top.0 * alpha + bottom.0 * (1 - alpha),
            top.1 * alpha + bottom.1 * (1 - alpha),
            top.2 * alpha + bottom.2 * (1 - alpha)
        )
    }

    /// Luminance relative WCAG.
    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }

    /// Ratio de contraste WCAG entre deux couleurs.
    private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
