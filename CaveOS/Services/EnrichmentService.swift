import Foundation

/// Résultat d'un appel d'enrichissement renvoyé par le serveur Go.
struct EnrichmentResult: Codable {
    var name: String
    var vintage: Int?
    var matchedOn: String?
    var regionName: String?
    var drinkFrom: Int?
    var peak: Int?
    var drinkBy: Int?
}

/// Erreurs spécifiques à l'enrichissement, pour des messages utilisateur clairs.
enum EnrichmentError: LocalizedError {
    case disabled
    case invalidURL
    case unavailable
    case decoding

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "L'enrichissement est désactivé."
        case .invalidURL:
            return "Requête invalide."
        case .unavailable:
            return "Service indisponible, l'app reste fonctionnelle hors-ligne."
        case .decoding:
            return "Réponse du service illisible."
        }
    }
}

/// Service d'enrichissement opt-in interrogeant un serveur Go distant.
///
/// Entièrement non bloquant : tout appel passe par `async`/`await` et l'app
/// continue de fonctionner hors-ligne si le service est indisponible.
enum EnrichmentService {

    /// Adresse de base du serveur d'enrichissement.
    static let baseURL = URL(string: "https://caveos.152.228.136.49.sslip.io")!

    /// Clé `UserDefaults` mémorisant l'activation par l'utilisateur.
    private static let enabledKey = "caveos.enrichmentEnabled"

    /// Indique si l'utilisateur a activé l'enrichissement (opt-in).
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Interroge le service d'enrichissement pour un vin donné.
    ///
    /// - Parameters:
    ///   - name: Nom du vin à rechercher.
    ///   - vintage: Millésime optionnel.
    /// - Returns: Le résultat décodé renvoyé par le serveur.
    /// - Throws: `EnrichmentError` en cas de désactivation, d'erreur réseau ou de décodage.
    static func enrich(name: String, vintage: Int?) async throws -> EnrichmentResult {
        guard isEnabled else { throw EnrichmentError.disabled }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw EnrichmentError.invalidURL
        }
        components.path = "/v1/enrich"

        var queryItems = [URLQueryItem(name: "name", value: name)]
        if let vintage {
            queryItems.append(URLQueryItem(name: "vintage", value: String(vintage)))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw EnrichmentError.invalidURL }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw EnrichmentError.unavailable
            }

            do {
                return try JSONDecoder().decode(EnrichmentResult.self, from: data)
            } catch {
                throw EnrichmentError.decoding
            }
        } catch let error as EnrichmentError {
            throw error
        } catch {
            throw EnrichmentError.unavailable
        }
    }
}
