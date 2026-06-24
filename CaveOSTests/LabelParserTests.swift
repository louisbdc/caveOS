import XCTest
@testable import CaveOS

/// Tests de l'analyseur d'étiquettes (OCR → champs structurés).
final class LabelParserTests: XCTestCase {

    private func parse(_ lines: [String],
                       appellations: [String] = [],
                       grapes: [String] = []) -> ScannedLabel {
        LabelParser.parse(lines: lines, knownAppellations: appellations, knownGrapes: grapes)
    }

    // MARK: - Millésime

    func testVintageMostRecentPlausible() {
        let label = parse(["Château Test", "2015", "Mis en bouteille 2017"])
        XCTAssertEqual(label.vintage, 2017)
    }

    func testVintageIgnoresImplausible() {
        let label = parse(["Lot 1234", "Réf 9999"])
        XCTAssertNil(label.vintage)
    }

    // MARK: - Producteur

    func testProducerPrefersDomaineKeyword() {
        let label = parse(["Appellation Bordeaux Contrôlée", "Château Margaux", "2015"])
        XCTAssertEqual(label.producer, "Château Margaux")
    }

    func testProducerExcludesLegalMentions() {
        // La ligne « Appellation… » est plus longue mais ne doit pas être prise.
        let label = parse(["Le Petit Cheval", "Appellation d'Origine Contrôlée Saint-Émilion"])
        XCTAssertEqual(label.producer, "Le Petit Cheval")
    }

    // MARK: - Format

    func testFormatNamedMagnum() {
        XCTAssertEqual(parse(["Magnum", "Château X"]).format, "Magnum (1,5 L)")
    }

    func testFormatVolumeCl() {
        XCTAssertEqual(parse(["Contenance 75 cl"]).format, "Bouteille (75 cl)")
    }

    func testFormatVolumeMlUppercase() {
        XCTAssertEqual(parse(["750 ML"]).format, "Bouteille (75 cl)")
    }

    func testFormatVolumeLitres() {
        XCTAssertEqual(parse(["1,5 L"]).format, "Magnum (1,5 L)")
    }

    // MARK: - Degré d'alcool

    func testABVRealistic() {
        XCTAssertEqual(parse(["Vin rouge", "13,5 % vol"]).abv, "13,5 %")
    }

    func testABVRejectsImplausible() {
        // « 1% » (promo) ne doit pas être pris pour un degré d'alcool.
        XCTAssertNil(parse(["Promotion 1% de remise"]).abv)
    }

    // MARK: - Appellation

    func testAppellationAcronym() {
        let label = parse(["AOC Pauillac", "Grand Vin"])
        XCTAssertEqual(label.appellation?.contains("Pauillac"), true)
    }

    // MARK: - Cépages

    func testGrapesMatchKnown() {
        let label = parse(
            ["Assemblage Merlot et Cabernet Sauvignon"],
            grapes: ["Merlot", "Cabernet Sauvignon", "Syrah"]
        )
        XCTAssertEqual(Set(label.grapes), Set(["Merlot", "Cabernet Sauvignon"]))
    }
}
