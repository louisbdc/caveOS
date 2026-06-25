import Foundation
import SwiftData

/// Couche d'abstraction au-dessus de SwiftData.
/// Centralise les sauvegardes EXPLICITES (le CDC déconseille l'auto-save silencieux)
/// et offre des requêtes typées aux ViewModels. Permet un repli Core Data en v3.
@MainActor
final class CaveRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Sauvegarde explicite
    @discardableResult
    func save() -> Result<Void, Error> {
        guard context.hasChanges else { return .success(()) }
        do {
            try context.save()
            return .success(())
        } catch {
            Log.persistence("CaveRepository.save a échoué : \(error.localizedDescription)")
            return .failure(error)
        }
    }

    // MARK: - Insertion / suppression génériques
    func insert(_ model: any PersistentModel) {
        context.insert(model)
    }

    func delete(_ model: any PersistentModel) {
        context.delete(model)
    }

    // MARK: - Bouteilles
    func fetchBottles(predicate: Predicate<Bottle>? = nil,
                      sortBy: [SortDescriptor<Bottle>] = [SortDescriptor(\.createdAt, order: .reverse)]) -> [Bottle] {
        let descriptor = FetchDescriptor<Bottle>(predicate: predicate, sortBy: sortBy)
        return (try? context.fetch(descriptor)) ?? []
    }

    func bottle(with id: UUID) -> Bottle? {
        let descriptor = FetchDescriptor<Bottle>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Vins
    func fetchWines(sortBy: [SortDescriptor<Wine>] = [SortDescriptor(\.name)]) -> [Wine] {
        let descriptor = FetchDescriptor<Wine>(sortBy: sortBy)
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Caves
    func fetchCellars() -> [Cellar] {
        let descriptor = FetchDescriptor<Cellar>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Emplacements
    func fetchLocations(in cellar: Cellar) -> [Location] {
        let cellarID = cellar.id
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate { $0.cellar?.id == cellarID },
            sortBy: [SortDescriptor(\.levelIndex), SortDescriptor(\.column)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Notes de dégustation
    func fetchTastingNotes(for bottle: Bottle) -> [TastingNote] {
        let bottleID = bottle.id
        let descriptor = FetchDescriptor<TastingNote>(
            predicate: #Predicate { $0.bottle?.id == bottleID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Base vin embarquée (lookups pour le parsing OCR & l'auto-complétion)
    func grapes() -> [Grape] {
        (try? context.fetch(FetchDescriptor<Grape>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func appellations() -> [Appellation] {
        (try? context.fetch(FetchDescriptor<Appellation>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func regions() -> [Region] {
        (try? context.fetch(FetchDescriptor<Region>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func count<T: PersistentModel>(of type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
    }
}
