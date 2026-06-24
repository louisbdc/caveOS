import Foundation
import WatchConnectivity

/// Pousse un résumé de cave vers l'app Apple Watch via WatchConnectivity.
/// Utilise `updateApplicationContext` (persistant) avec repli sur `sendMessage`.
enum PhoneWatchSync {
    @MainActor
    static func push(total: Int, ready: Int, items: [[String: String]]) {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = PhoneWatchSyncDelegate.shared
        }
        if session.activationState == .notActivated {
            session.activate()
        }

        let payload: [String: Any] = [
            "total": total,
            "ready": ready,
            "items": items
        ]

        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("PhoneWatchSync updateApplicationContext failed:", error.localizedDescription)
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { sendError in
                    print("PhoneWatchSync sendMessage failed:", sendError.localizedDescription)
                }
            }
        }
    }
}

/// Délégué minimal requis pour activer la session côté iPhone.
private final class PhoneWatchSyncDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchSyncDelegate()

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("PhoneWatchSync activation failed:", error.localizedDescription)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Réactive pour une éventuelle bascule de montre appairée.
        session.activate()
    }
}
