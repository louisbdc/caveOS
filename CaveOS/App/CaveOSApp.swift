import SwiftUI
import SwiftData

/// Point d'entrée de l'application CaveOS.
/// Offline-first : conteneur SwiftData 100% local, gestionnaire d'achats injecté dans l'environnement.
@main
struct CaveOSApp: App {

    /// Conteneur SwiftData partagé pour toute l'application.
    private let container: ModelContainer = AppContainer.makeContainer()

    /// Gestionnaire d'abonnements / achats (StoreKit), observable et partagé.
    @State private var store = StoreManager()

    /// Phase de la scène, utilisée pour rafraîchir le snapshot du widget en arrière-plan.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    store.startObserving()
                    await store.loadProducts()
                    refreshWidgetSnapshot()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                refreshWidgetSnapshot()
            }
        }
    }

    /// Recalcule le snapshot partagé avec le widget et pousse le résumé vers l'Apple Watch.
    @MainActor
    private func refreshWidgetSnapshot() {
        WidgetSnapshotWriter.update(modelContext: container.mainContext)

        // Pousse le même résumé vers l'app Apple Watch (consultation rapide).
        let snapshot = WidgetSnapshotStore.read()
        let items: [[String: String]] = snapshot.priorityItems.prefix(5).map { item in
            let vintageText: String = item.vintage.map(String.init) ?? ""
            return [
                "name": item.wineName,
                "vintage": vintageText,
                "status": item.statusLabel
            ]
        }
        PhoneWatchSync.push(total: snapshot.totalBottles, ready: snapshot.readyToDrink, items: Array(items))
    }
}
