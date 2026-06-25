import XCTest
import SwiftUI
@testable import CaveOS

/// Tests géométriques de la silhouette de bouteille et de la zone d'étiquette :
/// le tracé doit être non vide et entièrement contenu dans le `rect` fourni
/// (sinon le blueprint déborderait de la fenêtre de capture).
final class BottleBlueprintShapeTests: XCTestCase {

    /// Tolérance pour les arrondis flottants des courbes de Bézier.
    private let epsilon: CGFloat = 0.5

    func testBottlePathIsNotEmpty() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 600)
        let path = BottleBlueprintShape().path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingRect.width, 0)
        XCTAssertGreaterThan(path.boundingRect.height, 0)
    }

    func testBottlePathStaysWithinRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 600)
        assertPathContained(BottleBlueprintShape().path(in: rect), in: rect)
    }

    /// Le tracé doit suivre l'origine du rect (positionnement proportionnel, pas absolu).
    func testBottlePathRespectsOffsetRect() {
        let rect = CGRect(x: 120, y: 80, width: 180, height: 520)
        let path = BottleBlueprintShape().path(in: rect)
        XCTAssertFalse(path.isEmpty)
        assertPathContained(path, in: rect)
        // Le tracé occupe une part significative de la largeur (corps ~0.92 w).
        XCTAssertGreaterThan(path.boundingRect.width, rect.width * 0.8)
    }

    func testLabelZoneIsNotEmptyAndWithinRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 600)
        let path = LabelZoneShape().path(in: rect)
        XCTAssertFalse(path.isEmpty)
        assertPathContained(path, in: rect)
    }

    // MARK: - Helpers

    private func assertPathContained(
        _ path: Path,
        in rect: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - epsilon, file: file, line: line)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - epsilon, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + epsilon, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + epsilon, file: file, line: line)
    }
}
