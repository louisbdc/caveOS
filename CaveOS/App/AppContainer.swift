import Foundation
import SwiftData

/// Construction du ModelContainer.
/// CloudKit est prévu en v2 ; au MVP on reste 100% local (offline-first absolu).
enum AppContainer {
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none // .private(...) en v2
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedIfNeeded(container: container)
            return container
        } catch {
            fatalError("Impossible de créer le ModelContainer: \(error)")
        }
    }

    /// Amorce la base vin embarquée au premier lancement.
    @MainActor
    private static func seedIfNeeded(container: ModelContainer) {
        let repository = CaveRepository(context: container.mainContext)
        SeedImporter.seedIfNeeded(repository: repository)
    }
}
