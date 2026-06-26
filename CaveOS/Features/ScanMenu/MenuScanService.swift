import UIKit

/// Service de scan de carte des vins : envoie la photo au serveur CaveOS
/// (`POST /v1/scan/list`) et décode la liste structurée des vins détectés.
///
/// La compression JPEG et la clé d'authentification sont déléguées aux helpers
/// partagés d'`AIScanService` pour éviter toute duplication.
enum MenuScanService {

    /// Même serveur que les autres services CaveOS.
    static var baseURL: URL { EnrichmentService.baseURL }

    /// Analyse une photo de carte des vins et retourne les vins détectés.
    ///
    /// - Parameter image: Photo de la carte à analyser.
    /// - Returns: `MenuScanResult` contenant la liste des vins et les méta-données.
    /// - Throws: `URLError` en cas d'image invalide, d'erreur réseau ou de statut HTTP non-2xx.
    static func scanList(image: UIImage) async throws -> MenuScanResult {
        guard let jpeg = AIScanService.jpegData(for: image) else {
            throw URLError(.cannotDecodeContentData)
        }

        let url = baseURL.appendingPathComponent("v1/scan/list")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = AIScanService.scanKey {
            request.setValue(key, forHTTPHeaderField: "X-CaveOS-Key")
        }

        let body: [String: String] = [
            "image": jpeg.base64EncodedString(),
            "mimeType": "image/jpeg"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Networking.retrying {
            try await Networking.session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MenuScanResult.self, from: data)
    }
}
