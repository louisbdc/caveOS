import Foundation

/// Résultat structuré de l'analyse d'une étiquette de vin.
struct ScannedLabel {
    var producer: String?
    var wineName: String?
    var vintage: Int?
    var appellation: String?
    var grapes: [String]
    var rawLines: [String]

    init() {
        self.producer = nil
        self.wineName = nil
        self.vintage = nil
        self.appellation = nil
        self.grapes = []
        self.rawLines = []
    }
}
