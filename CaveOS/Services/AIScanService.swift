import Foundation
import UIKit

/// Réponse JSON du serveur pour `POST /v1/scan` : fusion des passes 1 (lecture
/// Mistral + Gemini) et 2 (déduction). Internal (non `private`) pour rester testable.
///
/// Décodage 100 % tolérant : un champ optionnel absent, vide ou portant une
/// `rawValue` d'enum inconnue n'échoue jamais et retombe sur `nil`.
struct ScanResponse: Codable {
    // Passe 1 — lus sur l'étiquette
    var producer: String?
    var wineName: String?
    var vintage: Int?
    var appellation: String?
    var grapes: [String]?
    var format: String?
    var abv: String?

    // Passe 2 — déductions
    var color: String?          // rawValue WineColor
    var wineType: String?       // rawValue WineType
    var region: String?
    var country: String?
    var grapesGuess: [String]?  // cépages déduits (utilisés si absents de l'étiquette)
    var peakFrom: Int?
    var peak: Int?              // milieu d'apogée (non exposé dans `ScannedLabel`)
    var peakTo: Int?

    // Méta
    var provider: String?           // ex. "mistral+gemini" (info/debug)
    var inferredFields: [String]?   // clés des champs déduits par la passe 2

    /// Convertit la réponse serveur en `ScannedLabel` (champs vides → `nil`,
    /// `rawValue` d'enum inconnue → `nil`, `peak`/`vintage` à 0 → `nil`).
    func toScannedLabel() -> ScannedLabel {
        var label = ScannedLabel()
        label.producer = producer?.nilIfBlank
        label.wineName = wineName?.nilIfBlank
        label.vintage = (vintage ?? 0) > 0 ? vintage : nil
        label.appellation = appellation?.nilIfBlank
        // Cépages lus en priorité ; à défaut, on retombe sur la déduction (passe 2).
        let readGrapes = (grapes ?? []).compactMap { $0.nilIfBlank }
        let guessedGrapes = (grapesGuess ?? []).compactMap { $0.nilIfBlank }
        label.grapes = readGrapes.isEmpty ? guessedGrapes : readGrapes
        label.format = format?.nilIfBlank
        label.abv = abv?.nilIfBlank
        label.color = color?.nilIfBlank.flatMap(WineColor.init(rawValue:))
        label.wineType = wineType?.nilIfBlank.flatMap(WineType.init(rawValue:))
        label.region = region?.nilIfBlank
        label.country = country?.nilIfBlank
        label.peakFrom = (peakFrom ?? 0) > 0 ? peakFrom : nil
        label.peakTo = (peakTo ?? 0) > 0 ? peakTo : nil
        // Le serveur marque les cépages déduits sous la clé "grapesGuess" ; quand
        // on retombe effectivement sur la déduction, on la traduit en "grapes" (la
        // clé surveillée par l'UI) pour que le badge « estimé » s'affiche.
        var inferred = Set(inferredFields ?? [])
        if readGrapes.isEmpty, !guessedGrapes.isEmpty, inferred.contains("grapesGuess") {
            inferred.insert(ScannedLabel.Field.grapes)
        }
        // Restreint aux clés connues (un champ inconnu côté serveur est ignoré).
        label.inferredFields = inferred.intersection(ScannedLabel.Field.allKeys)
        return label
    }
}

/// Erreurs du scan par IA, avec des messages lisibles par l'utilisateur.
enum AIScanError: LocalizedError {
    case invalidImage
    case invalidURL
    case unavailable
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Image illisible pour l'analyse IA."
        case .invalidURL:
            return "Requête invalide."
        case .unavailable:
            return "Service d'IA indisponible. Analyse locale utilisée."
        case .decoding:
            return "Réponse du service illisible."
        }
    }
}

/// Service de scan d'étiquette par IA : envoie l'image au serveur CaveOS qui
/// orchestre les deux passes (lecture Mistral + Gemini, puis déduction) et
/// renvoie les champs structurés fusionnés.
///
/// L'image est compressée (JPEG) et redimensionnée avant l'envoi pour limiter le
/// volume réseau. La clé d'accès partagée (`X-CaveOS-Key`) est lue depuis
/// `Info.plist` (`CaveOSScanKey`) ; absente, aucun en-tête n'est envoyé.
enum AIScanService {

    /// Même serveur que l'enrichissement.
    static let baseURL = EnrichmentService.baseURL

    private static let jpegQuality: CGFloat = 0.7
    private static let maxDimension: CGFloat = 1600

    /// Clé d'accès partagée, lue depuis `Info.plist` (vide si non configurée).
    private static var sharedKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "CaveOSScanKey") as? String) ?? ""
    }

    /// Analyse une image d'étiquette via le serveur CaveOS (Mistral + Gemini
    /// fusionnés, puis passe 2 de déduction). Le client ne choisit plus de
    /// fournisseur : le serveur orchestre les deux passes.
    ///
    /// - Parameter image: Photo de l'étiquette à analyser.
    /// - Returns: Les champs détectés (+ déduits) sous forme de `ScannedLabel`.
    /// - Throws: `AIScanError` en cas d'image invalide, d'erreur réseau ou de décodage.
    static func scan(image: UIImage) async throws -> ScannedLabel {
        guard let jpeg = downscaledJPEG(image) else { throw AIScanError.invalidImage }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AIScanError.invalidURL
        }
        components.path = "/v1/scan"
        guard let url = components.url else { throw AIScanError.invalidURL }

        let payload: [String: String] = [
            "image": jpeg.base64EncodedString(),
            "mimeType": "image/jpeg"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = sharedKey
        if !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-CaveOS-Key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await Networking.retrying {
                try await Networking.session.data(for: request)
            }
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw AIScanError.unavailable
            }
            do {
                return try JSONDecoder().decode(ScanResponse.self, from: data).toScannedLabel()
            } catch {
                throw AIScanError.decoding
            }
        } catch let error as AIScanError {
            throw error
        } catch {
            throw AIScanError.unavailable
        }
    }

    /// Redimensionne (côté max ≤ `maxDimension`) puis encode l'image en JPEG.
    private static func downscaledJPEG(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longestSide = max(size.width, size.height)
        let ratio = longestSide > maxDimension ? maxDimension / longestSide : 1
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}

private extension String {
    /// `nil` si la chaîne est vide ou ne contient que des espaces, sinon elle-même
    /// (rognée).
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
