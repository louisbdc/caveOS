import Foundation

/// Utilitaires réseau partagés : une session avec des timeouts raisonnables
/// (pour ne jamais figer l'app sur un mauvais réseau) et une relance avec
/// backoff exponentiel pour absorber les erreurs transitoires.
enum Networking {

    /// Session partagée avec timeouts courts : 15 s par requête, 30 s au total.
    /// Adaptée aux appels rapides (scan d'une étiquette, enrichissement d'un vin).
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Session pour les opérations longues : 120 s par requête, 150 s au total.
    ///
    /// Le scan d'une carte des vins entière (extraction multi-vins + enrichissement
    /// serveur) peut légitimement durer jusqu'à ~90 s côté serveur. La session
    /// courte (15 s) coupait l'analyse en plein vol — le serveur recevait alors un
    /// « context canceled ». Cette session laisse le temps au serveur de répondre.
    static let longSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 150
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Exécute une opération asynchrone et la relance en cas d'échec.
    ///
    /// - Parameters:
    ///   - attempts: Nombre total de tentatives (au moins 1).
    ///   - initialDelay: Délai avant la 1re relance, doublé à chaque nouvel échec.
    ///   - operation: L'opération à tenter ; chaque échec déclenche une relance.
    /// - Returns: Le résultat de la 1re tentative réussie.
    /// - Throws: La dernière erreur si toutes les tentatives échouent.
    static func retrying<T>(
        attempts: Int = 3,
        initialDelay: Duration = .milliseconds(400),
        operation: () async throws -> T
    ) async throws -> T {
        let total = max(1, attempts)
        var delay = initialDelay
        var lastError: Error?

        for attempt in 1...total {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < total {
                    try? await Task.sleep(for: delay)
                    delay *= 2
                }
            }
        }

        throw lastError ?? CancellationError()
    }
}
