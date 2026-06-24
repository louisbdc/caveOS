import Foundation
import UIKit

/// Client de l'API d'abonnement (Stripe) hébergée sur le serveur CaveOS.
/// AUCUNE clé Stripe côté app : l'app ne parle qu'à son propre serveur, qui détient la clé.
/// Pas d'authentification : un identifiant d'appareil stable relie l'abonnement.
enum BillingService {
    static let baseURL = "https://caveos.152.228.136.49.sslip.io"

    /// Identifiant d'appareil stable (identifierForVendor, repli UUID persisté).
    static var deviceRef: String {
        if let id = UIDevice.current.identifierForVendor?.uuidString { return id }
        let key = "caveos.deviceRef"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    private struct URLBody: Decodable { let url: String }
    private struct StatusBody: Decodable { let active: Bool; let status: String? }

    enum BillingError: LocalizedError {
        case requestFailed
        var errorDescription: String? { "Service d'abonnement indisponible. Réessayez plus tard." }
    }

    /// Crée une session Checkout et renvoie l'URL à ouvrir.
    /// - Parameter kind: `"subscription"` (annuel) ou `"lifetime"` (achat unique).
    static func startCheckout(kind: String = "subscription") async throws -> URL {
        try await postForURL(path: "/v1/billing/checkout", body: ["ref": deviceRef, "kind": kind])
    }

    /// Crée une session du portail client (gestion / annulation).
    static func openPortal() async throws -> URL {
        try await postForURL(path: "/v1/billing/portal", body: ["ref": deviceRef])
    }

    /// Indique si l'abonnement est actif pour cet appareil.
    ///
    /// Renvoie `nil` lorsque l'état est **indéterminé** (réseau indisponible,
    /// serveur injoignable, réponse illisible) : on ne sait pas trancher. Les
    /// appelants doivent alors **conserver** l'état connu plutôt que de révoquer
    /// l'accès — sinon un abonné perdrait son Pro hors-ligne.
    static func status() async -> Bool? {
        guard let url = URL(string: "\(baseURL)/v1/billing/status?ref=\(deviceRef)") else { return nil }
        do {
            let (data, _) = try await Networking.retrying {
                try await Networking.session.data(from: url)
            }
            return (try? JSONDecoder().decode(StatusBody.self, from: data))?.active
        } catch {
            return nil
        }
    }

    private static func postForURL(path: String, body: [String: String]) async throws -> URL {
        guard let endpoint = URL(string: baseURL + path) else { throw BillingError.requestFailed }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Networking.retrying {
            try await Networking.session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let body = try? JSONDecoder().decode(URLBody.self, from: data),
              let url = URL(string: body.url) else {
            throw BillingError.requestFailed
        }
        return url
    }
}
