import Foundation
import SwiftData

/// Point d'entrée unique pour rafraîchir l'instantané partagé : met à jour le
/// widget (App Group + reload des timelines) puis pousse le résumé vers l'Apple Watch.
/// Appelé au lancement, en arrière-plan, et après chaque modification de la cave.
enum SnapshotCoordinator {
    @MainActor
    static func refresh(modelContext: ModelContext) {
        WidgetSnapshotWriter.update(modelContext: modelContext)

        let snapshot = WidgetSnapshotStore.read()
        let items: [[String: String]] = snapshot.priorityItems.prefix(5).map { item in
            let vintageText: String = item.vintage.map(String.init) ?? ""
            // La Watch lit la clé "subtitle" : on y combine millésime et statut d'apogée.
            let subtitle = vintageText.isEmpty
                ? item.statusLabel
                : "\(vintageText) · \(item.statusLabel)"
            return [
                "name": item.wineName,
                "vintage": vintageText,
                "subtitle": subtitle
            ]
        }
        PhoneWatchSync.push(
            total: snapshot.totalBottles,
            ready: snapshot.readyToDrink,
            items: Array(items)
        )
    }
}
