import Foundation

struct ScannedMenuWine: Identifiable, Decodable {
    var id: Int { lineIndex }

    let producer: String?
    let wineName: String?
    let vintage: Int?
    let appellation: String?
    let grapes: [String]?
    let color: WineColor?
    let wineType: WineType?
    let region: String?
    let country: String?
    let peakFrom: Int?
    let peakTo: Int?
    let price: Double?
    let currency: String?
    let byGlass: Bool
    let priceGlass: Double?
    let lineIndex: Int

    private enum CodingKeys: String, CodingKey {
        case producer, wineName, vintage, appellation, grapes, color, wineType
        case region, country, peakFrom, peakTo, price, currency, byGlass, priceGlass, lineIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        producer = try c.decodeIfPresent(String.self, forKey: .producer)
        wineName = try c.decodeIfPresent(String.self, forKey: .wineName)
        vintage = try c.decodeIfPresent(Int.self, forKey: .vintage)
        appellation = try c.decodeIfPresent(String.self, forKey: .appellation)
        grapes = try c.decodeIfPresent([String].self, forKey: .grapes)
        color = (try c.decodeIfPresent(String.self, forKey: .color)).flatMap(WineColor.init(rawValue:))
        wineType = (try c.decodeIfPresent(String.self, forKey: .wineType)).flatMap(WineType.init(rawValue:))
        region = try c.decodeIfPresent(String.self, forKey: .region)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        peakFrom = try c.decodeIfPresent(Int.self, forKey: .peakFrom)
        peakTo = try c.decodeIfPresent(Int.self, forKey: .peakTo)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        byGlass = (try c.decodeIfPresent(Bool.self, forKey: .byGlass)) ?? false
        priceGlass = try c.decodeIfPresent(Double.self, forKey: .priceGlass)
        lineIndex = (try c.decodeIfPresent(Int.self, forKey: .lineIndex)) ?? 0
    }
}

struct MenuScanResult: Decodable {
    let wines: [ScannedMenuWine]
    let truncated: Bool
    let notWineList: Bool

    private enum CodingKeys: String, CodingKey {
        case wines, truncated, notWineList
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wines = (try c.decodeIfPresent([ScannedMenuWine].self, forKey: .wines)) ?? []
        truncated = (try c.decodeIfPresent(Bool.self, forKey: .truncated)) ?? false
        notWineList = (try c.decodeIfPresent(Bool.self, forKey: .notWineList)) ?? false
    }
}
