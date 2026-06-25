import Foundation

/// Résultat structuré de l'analyse d'une étiquette de vin.
///
/// Les champs de la « passe 2 » (déduction par IA) peuvent être marqués estimés
/// via `inferredFields` : l'UI les présente comme « estimé » et l'utilisateur peut
/// les corriger avant la création de la bouteille.
struct ScannedLabel {
    // Passe 1 — lus sur l'étiquette
    var producer: String?
    var wineName: String?
    var vintage: Int?
    var appellation: String?
    var grapes: [String]
    var ean: String?
    var format: String?
    var abv: String?

    // Passe 2 — déductions (affichées comme « estimé », corrigeables)
    var color: WineColor?
    var wineType: WineType?
    var region: String?
    var country: String?
    var peakFrom: Int?
    var peakTo: Int?

    var rawLines: [String]

    /// Clés des champs DÉDUITS par la passe 2 (à afficher comme « estimé »).
    var inferredFields: Set<String>

    init() {
        self.producer = nil
        self.wineName = nil
        self.vintage = nil
        self.appellation = nil
        self.grapes = []
        self.ean = nil
        self.format = nil
        self.abv = nil
        self.color = nil
        self.wineType = nil
        self.region = nil
        self.country = nil
        self.peakFrom = nil
        self.peakTo = nil
        self.rawLines = []
        self.inferredFields = []
    }

    /// Clés stables des champs estimables (alignées sur le champ `inferredFields`
    /// renvoyé par le serveur).
    enum Field {
        static let color    = "color"
        static let wineType = "wineType"
        static let region   = "region"
        static let country  = "country"
        static let grapes   = "grapes"
        static let peakFrom = "peakFrom"
        static let peakTo   = "peakTo"
        static let allKeys: Set<String> = [color, wineType, region, country, grapes, peakFrom, peakTo]
    }

    /// `true` si le champ provient d'une déduction (passe 2) et non de l'étiquette.
    func isInferred(_ field: String) -> Bool { inferredFields.contains(field) }
}
