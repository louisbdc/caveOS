import XCTest
@testable import CaveOS

final class MenuScanDecodingTests: XCTestCase {
    func testDecodeListResponse() throws {
        let json = """
        {"wines":[
          {"producer":"Clos La Coutale","wineName":"Cahors","vintage":2018,
           "color":"red","region":"Sud-Ouest","price":38,"currency":"EUR","lineIndex":0},
          {"wineName":"Chinon","vintage":2020,"byGlass":true,"priceGlass":8,"lineIndex":1}
        ],"count":2,"provider":"mistral+gemini","truncated":false}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(MenuScanResult.self, from: json)
        XCTAssertEqual(result.wines.count, 2)
        XCTAssertFalse(result.notWineList)
        XCTAssertEqual(result.wines[0].producer, "Clos La Coutale")
        XCTAssertEqual(result.wines[0].price, 38)
        XCTAssertEqual(result.wines[0].color, .red)
        XCTAssertTrue(result.wines[1].byGlass)
        XCTAssertEqual(result.wines[1].priceGlass, 8)
    }

    func testDecodeNotWineList() throws {
        let json = #"{"wines":[],"count":0,"provider":"gemini","notWineList":true}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(MenuScanResult.self, from: json)
        XCTAssertTrue(result.notWineList)
        XCTAssertTrue(result.wines.isEmpty)
    }
}
