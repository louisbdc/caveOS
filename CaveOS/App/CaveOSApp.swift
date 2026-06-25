import SwiftUI
import SwiftData

/// Point d'entrée de l'application CaveOS.
/// Offline-first : conteneur SwiftData 100% local, gestionnaire d'achats injecté dans l'environnement.
@main
struct CaveOSApp: App {

    /// Conteneur SwiftData partagé pour toute l'application.
    ///
    /// ⚠️ DÉMO TEMPORAIRE — en `DEBUG`, l'app démarre sur un conteneur **en mémoire**
    /// peuplé par ``SampleData`` (réinitialisé à chaque lancement, jamais persisté ni
    /// synchronisé CloudKit). Pour revenir à la base persistante, supprimer ce bloc
    /// `#if DEBUG` et ne garder que `AppContainer.makeContainer()`.
    #if DEBUG
    private let container: ModelContainer = SampleData.makeContainer()
    #else
    private let container: ModelContainer = AppContainer.makeContainer()
    #endif

    /// Gestionnaire d'abonnements / achats (StoreKit), observable et partagé.
    @State private var store = StoreManager()

    /// Phase de la scène, utilisée pour rafraîchir le snapshot du widget en arrière-plan.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    // Droits Pro via StoreKit : observation des transactions + chargement
                    // des produits (prix). L'abonnement passe par l'achat intégré Apple
                    // (conforme Guideline 3.1.1) ; aucun paiement externe dans l'app.
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
        SnapshotCoordinator.refresh(modelContext: container.mainContext)
    }
}
