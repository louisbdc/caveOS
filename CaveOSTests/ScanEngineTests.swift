import XCTest
@testable import CaveOS

/// Tests de l'énumération `ScanEngine` : ordre des cas (affichage du sélecteur),
/// distinction local/IA et identifiant de fournisseur transmis au serveur.
final class ScanEngineTests: XCTestCase {

    func testAllCasesOrder() {
        XCTAssertEqual(ScanEngine.allCases, [.device, .mistral, .gemini])
    }

    func testDeviceIsLocalAndHasNoProvider() {
        XCTAssertFalse(ScanEngine.device.isAI)
        XCTAssertNil(ScanEngine.device.providerKey)
    }

    func testAIEnginesExposeProviderKey() {
        XCTAssertTrue(ScanEngine.mistral.isAI)
        XCTAssertTrue(ScanEngine.gemini.isAI)
        XCTAssertEqual(ScanEngine.mistral.providerKey, "mistral")
        XCTAssertEqual(ScanEngine.gemini.providerKey, "gemini")
    }

    /// Le `rawValue` sert de clé de persistance @AppStorage : il doit faire l'aller-retour.
    func testRawValueRoundTripForPersistence() {
        for engine in ScanEngine.allCases {
            XCTAssertEqual(ScanEngine(rawValue: engine.rawValue), engine)
        }
    }

    /// Chaque moteur expose un libellé d'analyse distinct et non vide, nommant l'IA.
    func testAnalysisLabelNamesTheEngine() {
        XCTAssertEqual(ScanEngine.device.analysisLabel, "Analysé sur l'appareil")
        XCTAssertTrue(ScanEngine.mistral.analysisLabel.contains("Mistral"))
        XCTAssertTrue(ScanEngine.gemini.analysisLabel.contains("Gemini"))
    }
}
