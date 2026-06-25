import XCTest
@testable import CaveOS

/// Tests de l'énumération `ScanEngine` : ordre des cas (affichage du sélecteur)
/// et distinction local/IA.
final class ScanEngineTests: XCTestCase {

    func testAllCasesOrder() {
        XCTAssertEqual(ScanEngine.allCases, [.device, .ai])
    }

    func testDeviceIsLocal() {
        XCTAssertFalse(ScanEngine.device.isAI)
    }

    func testAIEngineIsAI() {
        XCTAssertTrue(ScanEngine.ai.isAI)
    }

    /// Le `rawValue` sert de clé de persistance @AppStorage : il doit faire l'aller-retour.
    func testRawValueRoundTripForPersistence() {
        for engine in ScanEngine.allCases {
            XCTAssertEqual(ScanEngine(rawValue: engine.rawValue), engine)
        }
    }

    /// Chaque moteur expose un libellé d'analyse distinct et non vide ; l'IA nomme
    /// les deux fournisseurs fusionnés.
    func testAnalysisLabelNamesTheEngine() {
        XCTAssertEqual(ScanEngine.device.analysisLabel, "Analysé sur l'appareil")
        XCTAssertTrue(ScanEngine.ai.analysisLabel.contains("IA"))
        XCTAssertTrue(ScanEngine.ai.analysisLabel.contains("Mistral"))
        XCTAssertTrue(ScanEngine.ai.analysisLabel.contains("Gemini"))
    }
}
