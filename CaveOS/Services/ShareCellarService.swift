import Foundation
import SwiftData

#if canImport(CloudKit)
import CloudKit
#endif

/// Prépare le partage en **lecture seule** d'une cave.
///
/// SwiftData masque son container CloudKit privé, il n'est donc pas possible
/// de créer fiablement un `CKShare` sur le store applicatif. On adopte donc une
/// approche pragmatique et robuste :
///  - on génère toujours un récapitulatif exportable (texte + CSV) de la cave ;
///  - on tente, lorsqu'un compte iCloud est disponible, de préparer un partage
///    CloudKit léger ; en cas d'échec (pas de compte, hors-ligne…) on retombe
///    proprement sur le partage texte via `UIActivityViewController` / `ShareLink`.
///
/// Aucun état n'est muté : le service ne fait que lire la cave et produire des
/// valeurs.
struct ShareCellarService {

    init() {}

    // MARK: - Texte partageable

    /// Récapitulatif lisible de la cave (lecture seule).
    func makeShareText(for cellar: Cellar) -> String {
        let lines = summaryLines(for: cellar)
        return lines.joined(separator: "\n")
    }

    /// CSV exportable des bouteilles de la cave.
    func makeCSV(for cellar: Cellar) -> String {
        let header = "Vin;Couleur;Millésime;Format;Quantité;Emplacement;État"
        let rows = sortedBottles(for: cellar).map(csvRow(for:))
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Items pour UIActivity / ShareLink

    /// Items à partager : le texte de récap, et (si possible) un fichier CSV.
    func makeShareItems(for cellar: Cellar) -> [Any] {
        var items: [Any] = [makeShareText(for: cellar)]

        if let csvURL = writeCSVFile(for: cellar) {
            items.append(csvURL)
        }

        return items
    }

    // MARK: - Tentative CloudKit (best-effort, non bloquante)

    /// Indique si un partage CloudKit est envisageable (compte iCloud actif).
    /// Retombe silencieusement à `false` sans CloudKit ou sans compte.
    func canUseCloudShare() async -> Bool {
        #if canImport(CloudKit)
        do {
            let status = try await CKContainer(identifier: AppContainer.cloudKitContainerID)
                .accountStatus()
            return status == .available
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Construction du récapitulatif

    private func summaryLines(for cellar: Cellar) -> [String] {
        let bottles = sortedBottles(for: cellar)
        let total = bottles.reduce(0) { $0 + $1.quantity }

        var lines: [String] = []
        lines.append("Cave « \(cellar.name) » — \(cellar.type.label)")
        lines.append("Partage en lecture seule")
        lines.append("\(total) bouteille\(total > 1 ? "s" : "") · \(bottles.count) référence\(bottles.count > 1 ? "s" : "")")
        lines.append("")

        if bottles.isEmpty {
            lines.append("Cette cave est vide.")
            return lines
        }

        for bottle in bottles {
            lines.append("• \(bottleLine(for: bottle))")
        }

        return lines
    }

    private func bottleLine(for bottle: Bottle) -> String {
        let name = bottle.wine?.name ?? "Bouteille"
        let vintage = (bottle.vintage.map { $0 > 0 ? " \($0)" : "" }) ?? ""
        let quantity = bottle.quantity > 1 ? " ×\(bottle.quantity)" : ""
        let location = bottle.location.map { " — \($0.label)" } ?? ""
        return "\(name)\(vintage)\(quantity)\(location)"
    }

    private func csvRow(for bottle: Bottle) -> String {
        let fields: [String] = [
            bottle.wine?.name ?? "",
            bottle.wine?.color.label ?? "",
            bottle.vintage.map { $0 > 0 ? String($0) : "" } ?? "",
            bottle.format.label,
            String(bottle.quantity),
            bottle.location?.label ?? "",
            bottle.state.label
        ]
        return fields.map(escapeCSV).joined(separator: ";")
    }

    private func escapeCSV(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func sortedBottles(for cellar: Cellar) -> [Bottle] {
        cellar.locations
            .flatMap { $0.bottles }
            .sorted { lhs, rhs in
                let lName = lhs.wine?.name ?? ""
                let rName = rhs.wine?.name ?? ""
                if lName != rName { return lName < rName }
                return (lhs.vintage ?? 0) < (rhs.vintage ?? 0)
            }
    }

    // MARK: - Fichier CSV temporaire

    private func writeCSVFile(for cellar: Cellar) -> URL? {
        let csv = makeCSV(for: cellar)
        let safeName = cellar.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileName = "Cave-\(safeName.isEmpty ? "export" : safeName).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
