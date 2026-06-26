import Foundation
import Vision
import UIKit

/// Repli d'analyse locale : OCR Vision sur l'image, regroupement en entrées,
/// parsing `LabelParser` par groupe, sans prix ni enrichissement serveur.
enum MenuDeviceFallback {

    /// Point d'entrée principal : OCR sur `image` → groupes de lignes → `ScannedMenuWine`.
    /// Retourne un tableau vide si aucune ligne exploitable n'est détectée.
    static func scan(
        image: UIImage,
        knownAppellations: [String],
        knownGrapes: [String]
    ) async -> [ScannedMenuWine] {
        guard let cgImage = image.cgImage else { return [] }

        let lines: [String]
        do {
            lines = try await recognizeText(in: cgImage)
        } catch {
            return []
        }

        let groups = groupLines(lines)

        return groups
            .enumerated()
            .compactMap { (index, group) -> ScannedMenuWine? in
                let label = LabelParser.parse(
                    lines: group,
                    knownAppellations: knownAppellations,
                    knownGrapes: knownGrapes
                )
                // Filtre les groupes sans information utile.
                guard label.producer != nil || label.wineName != nil else { return nil }

                return ScannedMenuWine(
                    lineIndex: index,
                    producer: label.producer,
                    wineName: label.wineName,
                    vintage: label.vintage,
                    appellation: label.appellation,
                    grapes: label.grapes.isEmpty ? nil : label.grapes,
                    color: label.color,
                    wineType: label.wineType,
                    region: nil,
                    country: nil,
                    peakFrom: nil,
                    peakTo: nil,
                    price: nil,
                    currency: nil,
                    byGlass: false,
                    priceGlass: nil
                )
            }
    }

    // MARK: - Groupement

    /// Regroupe des lignes OCR brutes en sous-tableaux représentant chaque entrée
    /// de la carte : un groupe = une séquence de lignes non vides séparée par au
    /// moins une ligne vide (ou une ligne de séparation réduite à des espaces).
    ///
    /// Règle simple et testable : les lignes vides sont des séparateurs.
    static func groupLines(_ lines: [String]) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    groups.append(current)
                    current = []
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }

        return groups
    }

    // MARK: - OCR Vision

    /// Hauteur de texte minimale (fraction de la hauteur d'image) prise en compte par l'OCR.
    private static let minimumTextHeightFraction: Float = 0.012

    /// Langues de reconnaissance OCR, par ordre de priorité.
    private static let recognitionLanguages = ["fr-FR", "en-US", "it-IT", "es-ES"]

    /// Reconnait le texte dans une image via Apple Vision.
    ///
    /// La reconnaissance Vision est synchrone et coûteuse en CPU : on l'exécute
    /// sur une tâche détachée pour ne pas bloquer un thread du pool coopératif.
    static func recognizeText(in cgImage: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try performRecognition(on: cgImage)
        }.value
    }

    /// Exécute la requête OCR de façon synchrone et renvoie le meilleur candidat par ligne.
    private static func performRecognition(on cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages
        request.minimumTextHeight = minimumTextHeightFraction

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
