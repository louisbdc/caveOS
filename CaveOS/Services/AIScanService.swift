import Foundation
import UIKit

/// Réponse JSON du serveur pour `POST /v1/scan`, normalisée quel que soit le
/// fournisseur (Mistral, Gemini, …). Internal (non `private`) pour rester testable.
struct ScanResponse: Codable {
    var producer: String?
    var wineName: String?
    var vintage: Int?
    var appellation: String?
    var grapes: [String]?
    var format: String?
    var abv: String?
    var provider: String?

    /// Convertit la réponse serveur en `ScannedLabel` (champs vides → `nil`).
    func toScannedLabel() -> ScannedLabel {
        var label = ScannedLabel()
        label.producer = producer?.nilIfBlank
        label.wineName = wineName?.nilIfBlank
        label.vintage = (vintage ?? 0) > 0 ? vintage : nil
        label.appellation = appellation?.nilIfBlank
        label.grapes = (grapes ?? []).compactMap { $0.nilIfBlank }
        label.format = format?.nilIfBlank
        label.abv = abv?.nilIfBlank
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

/// Service de scan d'étiquette par IA : envoie l'image au serveur CaveOS qui la
/// confie au fournisseur demandé et renvoie les champs structurés.
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

    /// Analyse une image d'étiquette via le fournisseur d'IA donné.
    ///
    /// - Parameters:
    ///   - image: Photo de l'étiquette à analyser.
    ///   - provider: Identifiant du fournisseur (`"mistral"`, `"gemini"`, …).
    /// - Returns: Les champs détectés sous forme de `ScannedLabel`.
    /// - Throws: `AIScanError` en cas d'image invalide, d'erreur réseau ou de décodage.
    static func scan(image: UIImage, provider: String) async throws -> ScannedLabel {
        guard let jpeg = downscaledJPEG(image) else { throw AIScanError.invalidImage }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AIScanError.invalidURL
        }
        components.path = "/v1/scan"
        guard let url = components.url else { throw AIScanError.invalidURL }

        let payload: [String: String] = [
            "provider": provider,
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
