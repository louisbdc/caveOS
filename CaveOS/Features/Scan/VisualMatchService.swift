import Foundation
import Vision

/// Matching visuel d'étiquettes 100 % on-device, sans entraînement.
///
/// Utilise `VNGenerateImageFeaturePrintRequest` pour générer une empreinte
/// visuelle de chaque image, puis compare ces empreintes par distance.
/// Aucune base de données mondiale n'est utilisée : on compare uniquement
/// la photo fournie aux photos d'étiquettes déjà enregistrées dans la cave.
enum VisualMatchService {

    /// Résultat d'un appariement : une bouteille et sa distance visuelle
    /// à l'image de référence (plus la distance est faible, plus c'est proche).
    struct VisualMatch: Identifiable {
        let bottle: Bottle
        let distance: Float

        var id: UUID { bottle.id }
    }

    /// Calcule l'empreinte visuelle d'une image.
    /// - Returns: L'observation Vision, ou `nil` si l'analyse échoue.
    static func featurePrint(for imageData: Data) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    /// Distance entre deux empreintes visuelles.
    /// - Returns: La distance (0 = identique), ou `nil` si le calcul échoue.
    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var value = Float(0)
        do {
            try a.computeDistance(&value, to: b)
            return value
        } catch {
            return nil
        }
    }

    /// Trouve, parmi les bouteilles fournies, celles dont l'étiquette
    /// enregistrée est visuellement la plus proche de l'image de référence.
    ///
    /// Seules les bouteilles disposant d'une `labelPhotoData` sont comparées.
    /// - Parameters:
    ///   - imageData: La photo d'étiquette à rechercher.
    ///   - bottles: Les bouteilles candidates.
    ///   - max: Nombre maximum de résultats renvoyés (triés du plus proche au plus lointain).
    @MainActor
    static func bestMatches(for imageData: Data, among bottles: [Bottle], max: Int = 3) -> [VisualMatch] {
        guard let reference = featurePrint(for: imageData) else { return [] }

        let matches: [VisualMatch] = bottles.compactMap { bottle in
            guard let photo = bottle.labelPhotoData,
                  let print = featurePrint(for: photo),
                  let dist = distance(reference, print) else {
                return nil
            }
            return VisualMatch(bottle: bottle, distance: dist)
        }

        return matches
            .sorted { $0.distance < $1.distance }
            .prefix(max)
            .map { $0 }
    }
}
