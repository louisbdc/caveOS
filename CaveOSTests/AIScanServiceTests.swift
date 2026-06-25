import XCTest
@testable import CaveOS

/// Tests du décodage de la réponse serveur `/v1/scan` et de son mapping vers
/// `ScannedLabel` (champs vides ou millésime nul ramenés à `nil`).
final class AIScanServiceTests: XCTestCase {

    func testMapsFullResponseToScannedLabel() throws {
        let json = Data("""
        {"producer":"Château Margaux","wineName":"Pavillon Rouge","vintage":2015,
         "appellation":"Margaux","grapes":["Cabernet Sauvignon","Merlot"],
         "format":"75 cl","abv":"13,5 %","provider":"mistral"}
        """.utf8)

        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        XCTAssertEqual(label.producer, "Château Margaux")
        XCTAssertEqual(label.wineName, "Pavillon Rouge")
        XCTAssertEqual(label.vintage, 2015)
        XCTAssertEqual(label.appellation, "Margaux")
        XCTAssertEqual(label.grapes, ["Cabernet Sauvignon", "Merlot"])
        XCTAssertEqual(label.format, "75 cl")
        XCTAssertEqual(label.abv, "13,5 %")
    }

    func testZeroVintageBecomesNil() throws {
        let json = Data(#"{"provider":"gemini","vintage":0}"#.utf8)
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()
        XCTAssertNil(label.vintage)
    }

    func testMissingAndBlankFieldsBecomeNil() throws {
        let json = Data(#"{"provider":"gemini","producer":"   ","grapes":["","Syrah"]}"#.utf8)
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        XCTAssertNil(label.producer)
        XCTAssertNil(label.wineName)
        XCTAssertNil(label.appellation)
        // Les cépages vides sont filtrés.
        XCTAssertEqual(label.grapes, ["Syrah"])
    }
}
