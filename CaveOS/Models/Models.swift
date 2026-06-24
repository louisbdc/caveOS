import Foundation
import SwiftData

// MARK: - Cépage (issu de Wikidata CC0)
@Model
final class Grape {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String?
    var wikidataId: String?
    // Profil de garde de base (années depuis le millésime)
    var apogeeMin: Int = 3
    var apogeePeak: Int = 8
    var apogeeMax: Int = 15

    init(id: UUID = UUID(), name: String = "", colorRaw: String? = nil, wikidataId: String? = nil,
         apogeeMin: Int = 3, apogeePeak: Int = 8, apogeeMax: Int = 15) {
        self.id = id
        self.name = name
        self.colorRaw = colorRaw
        self.wikidataId = wikidataId
        self.apogeeMin = apogeeMin
        self.apogeePeak = apogeePeak
        self.apogeeMax = apogeeMax
    }
}

// MARK: - Région viticole
@Model
final class Region {
    var id: UUID = UUID()
    var name: String = ""
    var country: String = "France"
    var qualityTierRaw: String = QualityTier.mid.rawValue

    var qualityTier: QualityTier {
        get { QualityTier(rawValue: qualityTierRaw) ?? .mid }
        set { qualityTierRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String = "", country: String = "France",
         qualityTier: QualityTier = .mid) {
        self.id = id
        self.name = name
        self.country = country
        self.qualityTierRaw = qualityTier.rawValue
    }
}

// MARK: - Appellation (INAO Licence Ouverte v1.0)
@Model
final class Appellation {
    var id: UUID = UUID()
    var name: String = ""
    var regionName: String?
    var inaoCode: String?
    var allowedGrapeNames: [String] = []   // mapping AOC→cépages autorisés (CDC 6.4)

    init(id: UUID = UUID(), name: String = "", regionName: String? = nil, inaoCode: String? = nil,
         allowedGrapeNames: [String] = []) {
        self.id = id
        self.name = name
        self.regionName = regionName
        self.inaoCode = inaoCode
        self.allowedGrapeNames = allowedGrapeNames
    }
}

// MARK: - Producteur (domaine / château)
@Model
final class Producer {
    var id: UUID = UUID()
    var name: String = ""

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

// MARK: - Vin abstrait (le « vin », indépendant d'une bouteille physique)
@Model
final class Wine {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String = WineColor.red.rawValue
    var typeRaw: String = WineType.still.rawValue
    var lwin: String?
    var barcode: String?   // code-barres EAN (v2)

    var producer: Producer?
    var region: Region?
    var appellation: Appellation?
    @Relationship var grapes: [Grape] = []

    // Override du profil de garde de base (sinon dérivé des cépages)
    var baseApogeeMin: Int?
    var baseApogeePeak: Int?
    var baseApogeeMax: Int?

    var isFavorite: Bool = false          // vin favori (alerte stock bas, CDC 9)
    var lowStockThreshold: Int?           // seuil d'alerte de stock bas

    @Relationship(deleteRule: .cascade, inverse: \Bottle.wine)
    var bottles: [Bottle] = []

    var color: WineColor {
        get { WineColor(rawValue: colorRaw) ?? .red }
        set { colorRaw = newValue.rawValue }
    }
    var type: WineType {
        get { WineType(rawValue: typeRaw) ?? .still }
        set { typeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String = "", color: WineColor = .red, type: WineType = .still,
         lwin: String? = nil, producer: Producer? = nil, region: Region? = nil,
         appellation: Appellation? = nil, grapes: [Grape] = []) {
        self.id = id
        self.name = name
        self.colorRaw = color.rawValue
        self.typeRaw = type.rawValue
        self.lwin = lwin
        self.producer = producer
        self.region = region
        self.appellation = appellation
        self.grapes = grapes
    }
}

// MARK: - Bouteille physique (instance en cave)
@Model
final class Bottle {
    var id: UUID = UUID()
    var wine: Wine?
    var vintage: Int?            // nil ou 0 = sans millésime (NV)
    var formatRaw: String = BottleFormat.bottle.rawValue
    var quantity: Int = 1
    var purchasePrice: Double?
    var purchaseDate: Date?
    var supplier: String?
    var location: Location?

    // Override manuel de la fenêtre d'apogée (années depuis le millésime)
    var apogeeMinOverride: Int?
    var apogeePeakOverride: Int?
    var apogeeMaxOverride: Int?
    var storageQualityRaw: String = StorageQuality.good.rawValue

    var stateRaw: String = BottleState.inCellar.rawValue
    var openedDate: Date?
    var remainingServings: Int?
    var conservationRaw: String?

    var notes: String?
    var isLyingDown: Bool = true   // bouteille couchée (true) ou debout (false) — CDC 5.2
    var ean: String?       // code-barres scanné (v2)
    @Attribute(.externalStorage) var labelPhotoData: Data?  // photo d'étiquette (matching visuel v3)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var format: BottleFormat {
        get { BottleFormat(rawValue: formatRaw) ?? .bottle }
        set { formatRaw = newValue.rawValue }
    }
    var state: BottleState {
        get { BottleState(rawValue: stateRaw) ?? .inCellar }
        set { stateRaw = newValue.rawValue }
    }
    var storageQuality: StorageQuality {
        get { StorageQuality(rawValue: storageQualityRaw) ?? .good }
        set { storageQualityRaw = newValue.rawValue }
    }
    var conservation: ConservationMethod {
        get { ConservationMethod(rawValue: conservationRaw ?? "") ?? .none }
        set { conservationRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), wine: Wine? = nil, vintage: Int? = nil,
         format: BottleFormat = .bottle, quantity: Int = 1, location: Location? = nil,
         state: BottleState = .inCellar) {
        self.id = id
        self.wine = wine
        self.vintage = vintage
        self.formatRaw = format.rawValue
        self.quantity = quantity
        self.location = location
        self.stateRaw = state.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Cave (contenant physique)
@Model
final class Cellar {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = CellarType.electric.rawValue
    var brand: String?
    var model: String?
    var rows: Int = 6
    var columns: Int = 8
    var levels: Int = 1
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Location.cellar)
    var locations: [Location] = []

    @Relationship(deleteRule: .cascade, inverse: \TemperatureReading.cellar)
    var temperatureReadings: [TemperatureReading] = []

    var type: CellarType {
        get { CellarType(rawValue: typeRaw) ?? .electric }
        set { typeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String = "", type: CellarType = .electric,
         rows: Int = 6, columns: Int = 8, levels: Int = 1) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.rows = rows
        self.columns = columns
        self.levels = levels
        self.createdAt = Date()
    }
}

// MARK: - Emplacement (clayette / zone / position)
@Model
final class Location {
    var id: UUID = UUID()
    var kindRaw: String = LocationKind.shelf.rawValue
    var label: String = ""
    var levelIndex: Int = 0
    var column: Int = 0
    var isFront: Bool = true
    var capacity: Int = 0
    var cellar: Cellar?

    @Relationship(inverse: \Bottle.location)
    var bottles: [Bottle] = []

    var kind: LocationKind {
        get { LocationKind(rawValue: kindRaw) ?? .shelf }
        set { kindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), kind: LocationKind = .shelf, label: String = "",
         levelIndex: Int = 0, column: Int = 0, isFront: Bool = true,
         capacity: Int = 0, cellar: Cellar? = nil) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.label = label
        self.levelIndex = levelIndex
        self.column = column
        self.isFront = isFront
        self.capacity = capacity
        self.cellar = cellar
    }
}

// MARK: - Note de dégustation
@Model
final class TastingNote {
    var id: UUID = UUID()
    var bottle: Bottle?
    var wine: Wine?
    var date: Date = Date()
    var score: Int?         // /100
    var eye: String?
    var nose: String?
    var palate: String?
    var text: String?
    var pairing: String?
    // Grille WSET avancée (v3)
    var sweetness: String?
    var acidity: String?
    var tannin: String?
    var body: String?
    var finish: String?
    @Attribute(.externalStorage) var photoData: Data?

    init(id: UUID = UUID(), bottle: Bottle? = nil, wine: Wine? = nil,
         date: Date = Date(), score: Int? = nil) {
        self.id = id
        self.bottle = bottle
        self.wine = wine
        self.date = date
        self.score = score
    }
}

// MARK: - Relevé de température (v2 — codes erreur matériel HH/LL/EE & alertes)
@Model
final class TemperatureReading {
    var id: UUID = UUID()
    var cellar: Cellar?
    var date: Date = Date()
    var celsius: Double = 12.0
    var note: String?

    init(id: UUID = UUID(), cellar: Cellar? = nil, date: Date = Date(),
         celsius: Double = 12.0, note: String? = nil) {
        self.id = id
        self.cellar = cellar
        self.date = date
        self.celsius = celsius
        self.note = note
    }
}

// MARK: - Liste de tous les types persistés (pour le ModelContainer)
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Wine.self, Bottle.self, Producer.self, Region.self,
        Appellation.self, Grape.self, Location.self, Cellar.self, TastingNote.self,
        TemperatureReading.self
    ]
}
