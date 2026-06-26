import XCTest
@testable import CaveOS

/// Tests unitaires de `MenuDeviceFallback.groupLines(_:)`.
/// Cette fonction pure est extraite pour être testée indépendamment de Vision/OCR.
final class MenuDeviceFallbackTests: XCTestCase {

    // MARK: - groupLines

    func testEmptyInputReturnsEmpty() {
        let groups = MenuDeviceFallback.groupLines([])
        XCTAssertTrue(groups.isEmpty)
    }

    func testNoSeparatorReturnsSingleGroup() {
        let lines = ["Château Margaux", "2019", "Pauillac"]
        let groups = MenuDeviceFallback.groupLines(lines)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0], ["Château Margaux", "2019", "Pauillac"])
    }

    func testEmptyLineBetweenProducesTwoGroups() {
        let lines = ["Château Margaux", "2019", "", "Domaine Leflaive", "Puligny-Montrachet"]
        let groups = MenuDeviceFallback.groupLines(lines)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0], ["Château Margaux", "2019"])
        XCTAssertEqual(groups[1], ["Domaine Leflaive", "Puligny-Montrachet"])
    }

    func testLeadingAndTrailingEmptyLinesAreIgnored() {
        let lines = ["", "  ", "Château Latour", "2018", "", "  "]
        let groups = MenuDeviceFallback.groupLines(lines)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0], ["Château Latour", "2018"])
    }

    func testMultipleSeparatingEmptyLinesCountAsOneSeparator() {
        let lines = ["Vin A", "", "", "Vin B"]
        let groups = MenuDeviceFallback.groupLines(lines)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0], ["Vin A"])
        XCTAssertEqual(groups[1], ["Vin B"])
    }

    func testWhitespaceOnlyLinesActAsSeparators() {
        let lines = ["Producteur X", "   ", "Cuvée Y"]
        let groups = MenuDeviceFallback.groupLines(lines)
        XCTAssertEqual(groups.count, 2)
    }

    func testAllEmptyLinesReturnEmpty() {
        let lines = ["", "  ", "\t"]
        let groups = MenuDeviceFallback.groupLines(lines)
        XCTAssertTrue(groups.isEmpty)
    }
}
