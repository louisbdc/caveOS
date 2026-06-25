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

    // MARK: - Passe 2 (déductions)

    func testDecodesDeducedFields() throws {
        let json = Data("""
        {"producer":"Château Margaux","color":"red","wineType":"still",
         "region":"Bordeaux","country":"France","peakFrom":2022,"peak":2031,"peakTo":2040,
         "provider":"mistral+gemini"}
        """.utf8)

        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        XCTAssertEqual(label.color, .red)
        XCTAssertEqual(label.wineType, .still)
        XCTAssertEqual(label.region, "Bordeaux")
        XCTAssertEqual(label.country, "France")
        XCTAssertEqual(label.peakFrom, 2022)
        XCTAssertEqual(label.peakTo, 2040)
    }

    func testInferredSetFiltersUnknownKeys() throws {
        let json = Data(#"{"color":"red","inferredFields":["color","bogus","region"]}"#.utf8)
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        // La clé inconnue "bogus" est écartée ; seules les clés connues subsistent.
        XCTAssertEqual(label.inferredFields, ["color", "region"])
        XCTAssertTrue(label.isInferred(ScannedLabel.Field.color))
        XCTAssertFalse(label.isInferred("bogus"))
    }

    func testUnknownColorBecomesNil() throws {
        let json = Data(#"{"color":"mauve","wineType":"frizzante"}"#.utf8)
        // Décodage tolérant : une rawValue d'enum inconnue ne lève pas, elle vaut nil.
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        XCTAssertNil(label.color)
        XCTAssertNil(label.wineType)
    }

    func testZeroPeakBecomesNil() throws {
        let json = Data(#"{"peakFrom":0,"peakTo":0}"#.utf8)
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        XCTAssertNil(label.peakFrom)
        XCTAssertNil(label.peakTo)
    }

    func testFallsBackToGuessedGrapesWhenNoneRead() throws {
        // Le serveur marque la déduction sous la clé "grapesGuess" : le mapping doit
        // la traduire en "grapes" (clé surveillée par l'UI) pour afficher le badge.
        let json = Data(#"{"grapes":[],"grapesGuess":["Pinot Noir"],"inferredFields":["grapesGuess"]}"#.utf8)
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        XCTAssertEqual(label.grapes, ["Pinot Noir"])
        XCTAssertTrue(label.isInferred(ScannedLabel.Field.grapes))
    }

    func testReadGrapesTakePrecedenceOverGuess() throws {
        let json = Data(#"{"grapes":["Merlot"],"grapesGuess":["Pinot Noir"]}"#.utf8)
        let label = try JSONDecoder().decode(ScanResponse.self, from: json).toScannedLabel()

        // Les cépages lus sur l'étiquette priment sur la déduction.
        XCTAssertEqual(label.grapes, ["Merlot"])
    }
}
