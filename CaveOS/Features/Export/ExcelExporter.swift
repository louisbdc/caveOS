import Foundation

/// Exporte les bouteilles de la cave au format Excel (SpreadsheetML 2003).
///
/// Génère un véritable classeur Excel au format XML SpreadsheetML 2003
/// (extension `.xls`), ouvrable nativement par Microsoft Excel, Numbers et
/// LibreOffice sans aucune dépendance externe. Les colonnes sont identiques
/// à celles de l'export CSV.
enum ExcelExporter {

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

    /// Écrit le classeur Excel dans un fichier temporaire et retourne son URL (pour ShareLink).
    static func makeFile(from bottles: [Bottle]) throws -> URL {
        let content = workbook(from: bottles)

        let fileName = "CaveOS-export-\(dateFormatter.string(from: Date())).xls"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Échec de l'écriture du fichier Excel : \(error)")
            throw error
        }
    }

    // MARK: - Génération du XML

    /// Construit le document SpreadsheetML 2003 complet.
    private static func workbook(from bottles: [Bottle]) -> String {
        let headerRow = row(cells: headers.map { textCell($0) })
        let dataRows = bottles.map { dataRow(for: $0) }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:o="urn:schemas-microsoft-com:office:office"
         xmlns:x="urn:schemas-microsoft-com:office:excel"
         xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:html="http://www.w3.org/TR/REC-html40">
         <Styles>
          <Style ss:ID="Header">
           <Font ss:Bold="1"/>
          </Style>
         </Styles>
         <Worksheet ss:Name="Inventaire">
          <Table>
        \(headerRowStyled(headerRow))
        \(dataRows)
          </Table>
         </Worksheet>
        </Workbook>
        """
    }

    /// Applique le style « Header » (gras) à la ligne d'en-tête.
    private static func headerRowStyled(_ headerRow: String) -> String {
        headerRow.replacingOccurrences(
            of: "<Cell>",
            with: "<Cell ss:StyleID=\"Header\">"
        )
    }

    /// Construit une ligne de données pour une bouteille donnée.
    private static func dataRow(for bottle: Bottle) -> String {
        let wine = bottle.wine

        let cells: [String] = [
            textCell(wine?.name ?? ""),
            textCell(wine?.producer?.name ?? ""),
            bottle.vintage.map(numberCell) ?? textCell(""),
            textCell(wine?.color.label ?? ""),
            textCell(wine?.region?.name ?? ""),
            textCell(wine?.appellation?.name ?? ""),
            textCell((wine?.grapes ?? []).map(\.name).joined(separator: " / ")),
            textCell(bottle.format.label),
            numberCell(bottle.quantity),
            bottle.purchasePrice.map(numberCell) ?? textCell(""),
            textCell(bottle.purchaseDate.map { dateFormatter.string(from: $0) } ?? ""),
            textCell(bottle.location?.label ?? ""),
            textCell(bottle.state.label),
            textCell(apogeeDescription(for: bottle)),
            textCell(bottle.notes ?? "")
        ]

        return row(cells: cells)
    }

    /// Décrit la fenêtre d'apogée d'une bouteille de façon lisible.
    private static func apogeeDescription(for bottle: Bottle) -> String {
        guard let window = ApogeeEngine.window(for: bottle, now: Date()) else {
            return ""
        }
        return "\(window.drinkFrom)–\(window.drinkBy)"
    }

    // MARK: - Cellules & lignes

    /// Assemble une ligne `<Row>` à partir de cellules déjà sérialisées.
    private static func row(cells: [String]) -> String {
        let inner = cells.map { "    \($0)" }.joined(separator: "\n")
        return "   <Row>\n\(inner)\n   </Row>"
    }

    /// Cellule de type chaîne, contenu échappé pour le XML.
    private static func textCell(_ value: String) -> String {
        "<Cell><Data ss:Type=\"String\">\(escape(value))</Data></Cell>"
    }

    /// Cellule numérique entière.
    private static func numberCell(_ value: Int) -> String {
        "<Cell><Data ss:Type=\"Number\">\(value)</Data></Cell>"
    }

    /// Cellule numérique décimale (deux décimales).
    private static func numberCell(_ value: Double) -> String {
        "<Cell><Data ss:Type=\"Number\">\(String(format: "%.2f", value))</Data></Cell>"
    }

    /// Échappe les caractères réservés du XML (`&`, `<`, `>`, `"`).
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
