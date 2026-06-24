import Foundation
import SwiftData

/// Construction du ModelContainer.
/// Offline-first absolu : la base locale est la source de vérité.
/// La sync CloudKit (v2) est activable par l'utilisateur ; désactivée par défaut
/// pour rester fonctionnelle sans compte iCloud / sans entitlement provisionné.
enum AppContainer {
    static let iCloudSyncKey = "caveos.iCloudSyncEnabled"
    static let cloudKitContainerID = "iCloud.com.louisbdc.caveos"

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let syncEnabled = UserDefaults.standard.bool(forKey: iCloudSyncKey)

        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
            (syncEnabled && !inMemory) ? .private(cloudKitContainerID) : .none

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitDatabase
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedIfNeeded(container: container)
            return container
        } catch {
            // Repli : si CloudKit échoue (entitlement absent), on retombe en local pur.
            print("ModelContainer CloudKit indisponible, repli local: \(error)")
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfig])
                seedIfNeeded(container: container)
                return container
            } catch {
                fatalError("Impossible de créer le ModelContainer: \(error)")
            }
        }
    }

    /// Amorce la base vin embarquée au premier lancement.
    @MainActor
    private static func seedIfNeeded(container: ModelContainer) {
        let repository = CaveRepository(context: container.mainContext)
        SeedImporter.seedIfNeeded(repository: repository)
    }
}
