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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    store.startObserving()
                    await store.loadProducts()
                }
        }
        .modelContainer(container)
    }
}
