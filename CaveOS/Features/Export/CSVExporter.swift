import Foundation

/// Exporte les bouteilles de la cave au format CSV.
enum CSVExporter {

    private static let headers = [
        "Vin", "Domaine", "Millésime", "Couleur", "Région", "Appellation",
        "Cépages", "Format", "Quantité", "Prix", "DateAchat", "Emplacement",
        "Statut", "Apogée", "Notes"
    ]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Génère le contenu CSV complet à partir d'une liste de bouteilles.
    static func csv(from bottles: [Bottle]) -> String {
        let headerLine = headers.map(escape).joined(separator: ",")
        let rows = bottles.map(row(for:))
        return ([headerLine] + rows).joined(separator: "\n")
    }

    /// Construit une ligne CSV pour une bouteille donnée.
    private static func row(for bottle: Bottle) -> String {
        let wine = bottle.wine

        let fields: [String] = [
            wine?.name ?? "",
            wine?.producer?.name ?? "",
            bottle.vintage.map(String.init) ?? "",
            wine?.color.label ?? "",
            wine?.region?.name ?? "",
            wine?.appellation?.name ?? "",
            (wine?.grapes ?? []).map(\.name).joined(separator: " / "),
            bottle.format.label,
            String(bottle.quantity),
            bottle.purchasePrice.map { String(format: "%.2f", $0) } ?? "",
            bottle.purchaseDate.map { dateFormatter.string(from: $0) } ?? "",
            bottle.location?.label ?? "",
            bottle.state.label,
            apogeeDescription(for: bottle),
            bottle.notes ?? ""
        ]

        return fields.map(escape).joined(separator: ",")
    }

    /// Décrit la fenêtre d'apogée d'une bouteille de façon lisible.
    private static func apogeeDescription(for bottle: Bottle) -> String {
        guard let window = ApogeeEngine.window(for: bottle) else {
            return ""
        }
        return "\(window.drinkFrom)–\(window.drinkBy)"
    }

    /// Échappe un champ CSV : entoure de guillemets si nécessaire, double les guillemets internes.
    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains(";")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")

        guard needsQuoting else { return field }

        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Écrit le CSV dans un fichier temporaire et retourne son URL (pour ShareLink).
    static func makeFile(from bottles: [Bottle]) throws -> URL {
        let content = csv(from: bottles)

        let fileName = "CaveOS-export-\(dateFormatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Log.export("Échec de l'écriture du fichier CSV : \(error.localizedDescription)")
            throw error
        }
    }
}
