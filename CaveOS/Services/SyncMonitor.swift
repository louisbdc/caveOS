import Foundation
import CoreData

/// Observe l'état de la synchronisation CloudKit (NSPersistentCloudKitContainer).
///
/// CaveOS est offline-first : la cave locale reste la source de vérité.
/// Ce moniteur sert uniquement à informer l'utilisateur de l'état du miroir iCloud.
/// Il est robuste si CloudKit est absent ou désactivé : aucun événement ne sera
/// simplement reçu et l'état restera « Inactif ».
@MainActor
@Observable
final class SyncMonitor {
    /// `true` tant qu'un événement de synchronisation est en cours.
    var isSyncing: Bool = false

    /// Description lisible du dernier événement reçu.
    var lastEventDescription: String = "Inactif"

    /// Message de la dernière erreur rencontrée, le cas échéant.
    var lastError: String?

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Démarre l'observation des événements CloudKit.
    ///
    /// Sûr à appeler plusieurs fois : un seul observateur est enregistré.
    func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }

            // On extrait des valeurs Sendable (l'Event non-Sendable ne traverse pas la frontière d'acteur).
            let label = Self.label(for: event.type)
            let inProgress = event.endDate == nil
            let errorDescription = event.error?.localizedDescription

            // L'observateur est posté sur la file principale, on reste donc sur le MainActor.
            MainActor.assumeIsolated {
                self?.apply(label: label, inProgress: inProgress, errorDescription: errorDescription)
            }
        }
    }

    private func apply(label: String, inProgress: Bool, errorDescription: String?) {
        if inProgress {
            isSyncing = true
            lastEventDescription = "\(label) en cours…"
            return
        }

        isSyncing = false
        if let errorDescription {
            lastError = errorDescription
            lastEventDescription = "\(label) — échec"
        } else {
            lastError = nil
            lastEventDescription = "\(label) terminé"
        }
    }

    nonisolated private static func label(for type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            return "Configuration iCloud"
        case .import:
            return "Import iCloud"
        case .export:
            return "Export iCloud"
        @unknown default:
            return "Synchronisation"
        }
    }
}
