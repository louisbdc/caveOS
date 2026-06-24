import Foundation
import WatchConnectivity

/// Reçoit un résumé de cave simple depuis l'iPhone via WatchConnectivity.
/// Dictionnaire attendu : ["total": Int, "ready": Int, "items": [[String: String]]].
@MainActor
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private(set) var total: Int = 0
    private(set) var ready: Int = 0
    private(set) var items: [[String: String]] = []

    override init() {
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Mise à jour interne

    /// Applique des valeurs déjà Sendable (Int / [[String:String]]).
    private func set(total: Int?, ready: Int?, items: [[String: String]]?) {
        if let total { self.total = total }
        if let ready { self.ready = ready }
        if let items { self.items = items }
    }

    /// Extrait les valeurs Sendable d'un payload non-Sendable (contexte nonisolated).
    nonisolated private func dispatch(_ payload: [String: Any]) {
        let total = payload["total"] as? Int
        let ready = payload["ready"] as? Int
        let items = payload["items"] as? [[String: String]]
        Task { @MainActor in
            self.set(total: total, ready: ready, items: items)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WatchSessionManager activation failed:", error.localizedDescription)
            return
        }
        // Récupère le dernier contexte connu au démarrage.
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        dispatch(context)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        dispatch(message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        dispatch(applicationContext)
    }
}
