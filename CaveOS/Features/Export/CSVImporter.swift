import Foundation
import SwiftData

/// Importe des bouteilles depuis un fichier CSV vers SwiftData.
///
/// Parseur CSV robuste (gère les guillemets, virgules et retours à la ligne
/// échappés). Les en-têtes sont tolérantes : plusieurs intitulés sont acceptés
/// par colonne afin de rester compatible avec les exports basiques de Vinotag,
/// OENO, CellarTracker et l'export natif de CaveOS. Seul un nom de vin est
/// requis ; toutes les autres colonnes sont optionnelles.
enum CSVImporter {

    // MARK: - Erreurs

    enum ImportError: LocalizedError {
        case unreadableFile
        case emptyFile
        case missingNameColumn

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Le fichier CSV n'a pas pu être lu."
            case .emptyFile:
                return "Le fichier CSV est vide."
            case .missingNameColumn:
                return "Aucune colonne de nom de vin n'a été trouvée (Vin, Wine, Name…)."
            }
        }
    }

    // MARK: - En-têtes flexibles

    /// Synonymes acceptés par champ logique (comparaison insensible à la casse/accents).
    private static let aliases: [Field: [String]] = [
        .name: ["vin", "wine", "name", "nom", "cuvee", "cuvée", "wine name", "vino"],
        .producer: ["domaine", "producer", "producteur", "chateau", "château", "winery", "domaine/château", "bottler"],
        .vintage: ["millesime", "millésime", "vintage", "annee", "année", "year"],
        .color: ["couleur", "color", "colour", "type", "wine type"],
        .region: ["region", "région", "appellation/region", "country", "pays"],
        .appellation: ["appellation", "aoc", "designation", "désignation", "aop"],
        .grapes: ["cepages", "cépages", "grapes", "varietal", "varietals", "cepage", "cépage", "grape"],
        .format: ["format", "size", "bottle size", "contenance"],
        .quantity: ["quantite", "quantité", "quantity", "qty", "count", "stock", "bottles"],
        .price: ["prix", "price", "cost", "purchase price", "valeur"],
        .purchaseDate: ["dateachat", "date achat", "date d'achat", "purchase date", "date", "bought"],
        .location: ["emplacement", "location", "bin", "rack", "casier", "position"],
        .notes: ["notes", "note", "commentaire", "comment", "comments", "remarks"]
    ]

    private enum Field: CaseIterable {
        case name, producer, vintage, color, region, appellation
        case grapes, format, quantity, price, purchaseDate, location, notes
    }

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy", "yyyy/MM/dd"].map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    // MARK: - Point d'entrée

    /// Lit le fichier CSV, crée les entités et retourne le nombre de bouteilles importées.
    @MainActor
    static func importBottles(from url: URL, into context: ModelContext) throws -> Int {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? readString(from: url) else {
            throw ImportError.unreadableFile
        }

        let rows = parse(raw)
        guard let header = rows.first, rows.count > 1 else {
            throw ImportError.emptyFile
        }

        let mapping = columnMapping(for: header)
        guard mapping[.name] != nil else {
            throw ImportError.missingNameColumn
        }

        var imported = 0
        for fields in rows.dropFirst() where !isBlank(fields) {
            if insertBottle(from: fields, mapping: mapping, into: context) {
                imported += 1
            }
        }

        do {
            try context.save()
        } catch {
            print("CSVImporter.save a échoué : \(error)")
            throw error
        }

        return imported
    }

    // MARK: - Construction des entités

    /// Crée Wine + Producer + Bottle pour une ligne. Retourne `false` si la ligne est ignorée.
    @MainActor
    private static func insertBottle(from fields: [String],
                                     mapping: [Field: Int],
                                     into context: ModelContext) -> Bool {
        let name = value(.name, in: fields, mapping: mapping)
        guard let name, !name.isEmpty else { return false }

        let wine = Wine(name: name)

        if let colorText = value(.color, in: fields, mapping: mapping) {
            wine.color = parseColor(colorText)
        }

        if let producerName = value(.producer, in: fields, mapping: mapping), !producerName.isEmpty {
            let producer = Producer(name: producerName)
            context.insert(producer)
            wine.producer = producer
        }

        if let regionName = value(.region, in: fields, mapping: mapping), !regionName.isEmpty {
            let region = Region(name: regionName)
            context.insert(region)
            wine.region = region
        }

        if let appellationName = value(.appellation, in: fields, mapping: mapping), !appellationName.isEmpty {
            let appellation = Appellation(name: appellationName)
            context.insert(appellation)
            wine.appellation = appellation
        }

        if let grapesText = value(.grapes, in: fields, mapping: mapping), !grapesText.isEmpty {
            wine.grapes = parseGrapes(grapesText).map { grapeName in
                let grape = Grape(name: grapeName)
                context.insert(grape)
                return grape
            }
        }

        context.insert(wine)

        let bottle = Bottle(wine: wine)

        if let vintageText = value(.vintage, in: fields, mapping: mapping) {
            bottle.vintage = parseVintage(vintageText)
        }
        if let formatText = value(.format, in: fields, mapping: mapping) {
            bottle.format = parseFormat(formatText)
        }
        if let quantityText = value(.quantity, in: fields, mapping: mapping),
           let quantity = parseInt(quantityText) {
            bottle.quantity = max(1, quantity)
        }
        if let priceText = value(.price, in: fields, mapping: mapping) {
            bottle.purchasePrice = parseDouble(priceText)
        }
        if let dateText = value(.purchaseDate, in: fields, mapping: mapping) {
            bottle.purchaseDate = parseDate(dateText)
        }
        if let notes = value(.notes, in: fields, mapping: mapping), !notes.isEmpty {
            bottle.notes = notes
        }

        context.insert(bottle)
        return true
    }

    // MARK: - Mapping des colonnes

    /// Associe chaque champ logique à l'index de colonne correspondant dans l'en-tête.
    private static func columnMapping(for header: [String]) -> [Field: Int] {
        var mapping: [Field: Int] = [:]
        let normalizedHeader = header.map(normalize)

        for field in Field.allCases {
            guard let synonyms = aliases[field] else { continue }
            let normalizedSynonyms = synonyms.map(normalize)
            if let index = normalizedHeader.firstIndex(where: { normalizedSynonyms.contains($0) }) {
                mapping[field] = index
            }
        }
        return mapping
    }

    /// Récupère la valeur nettoyée d'un champ pour une ligne donnée.
    private static func value(_ field: Field, in fields: [String], mapping: [Field: Int]) -> String? {
        guard let index = mapping[field], index < fields.count else { return nil }
        let trimmed = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Conversions

    private static func parseColor(_ text: String) -> WineColor {
        let normalized = normalize(text)
        switch normalized {
        case "rouge", "red", "rosso", "tinto": return .red
        case "blanc", "white", "bianco", "blanco": return .white
        case "rose", "rosé", "rosado": return .rose
        case "effervescent", "sparkling", "champagne", "cremant", "crémant", "mousseux": return .sparkling
        case "liquoreux", "sweet", "moelleux", "doux", "dessert": return .sweet
        case "fortifie", "fortifié", "fortified", "porto", "port": return .fortified
        case "orange": return .orange
        default: return .red
        }
    }

    private static func parseFormat(_ text: String) -> BottleFormat {
        let normalized = normalize(text)
        for format in BottleFormat.allCases {
            if normalized.contains(normalize(format.rawValue)) { return format }
        }
        switch normalized {
        case let value where value.contains("magnum") && value.contains("double"): return .doubleMagnum
        case let value where value.contains("magnum"): return .magnum
        case let value where value.contains("demi") || value.contains("half"): return .demi
        case let value where value.contains("jeroboam") || value.contains("jéroboam"): return .jeroboam
        case let value where value.contains("piccolo"): return .piccolo
        default: return .bottle
        }
    }

    private static func parseGrapes(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "/,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseVintage(_ text: String) -> Int? {
        guard let year = parseInt(text), year > 1800, year < 2200 else { return nil }
        return year
    }

    private static func parseInt(_ text: String) -> Int? {
        let digits = text.filter { $0.isNumber }
        return Int(digits)
    }

    private static func parseDouble(_ text: String) -> Double? {
        let cleaned = text
            .filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private static func parseDate(_ text: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    // MARK: - Utilitaires

    /// Lit le fichier en tentant UTF-8 puis Latin-1 (exports legacy).
    private static func readString(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    /// Normalise une chaîne pour comparaison : minuscules, sans accents, sans espaces de bord.
    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    /// Vrai si tous les champs de la ligne sont vides.
    private static func isBlank(_ fields: [String]) -> Bool {
        fields.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Parseur CSV

    /// Parse un texte CSV en lignes de champs, en gérant guillemets, virgules
    /// internes, guillemets doublés et retours à la ligne (CRLF / LF) échappés.
    private static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var field = ""
        var insideQuotes = false

        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if insideQuotes {
                if character == "\"" {
                    let next = index + 1 < characters.count ? characters[index + 1] : nil
                    if next == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    insideQuotes = true
                case ",", ";":
                    currentRow.append(field)
                    field = ""
                case "\n":
                    currentRow.append(field)
                    rows.append(currentRow)
                    currentRow = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }
            index += 1
        }

        if !field.isEmpty || !currentRow.isEmpty {
            currentRow.append(field)
            rows.append(currentRow)
        }

        return rows
    }
}
