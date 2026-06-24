import Foundation
import SwiftData
import WidgetKit

/// Calcule un instantané léger de la cave et l'écrit dans l'App Group,
/// puis demande au widget de se recharger.
enum WidgetSnapshotWriter {
    /// Couleurs des pastilles du widget, dérivées de `WineColor`.
    /// (Hex statiques pour rester cohérent avec `WineColor.tint` côté app.)
    private static func hex(for color: WineColor) -> String {
        switch color {
        case .red: return "#73121F"
        case .white: return "#D9C773"
        case .rose: return "#EB8C99"
        case .sparkling: return "#E6CC8C"
        case .sweet: return "#CC9933"
        case .fortified: return "#66332E"
        case .orange: return "#D98033"
        }
    }

    @MainActor
    static func update(modelContext: ModelContext) {
        let now = Date()

        let bottles = (try? modelContext.fetch(FetchDescriptor<Bottle>())) ?? []

        // On ne considère que les bouteilles encore en cave.
        let inCellar = bottles.filter { $0.state == .inCellar }

        let totalBottles = inCellar.reduce(0) { $0 + max($1.quantity, 0) }

        let statuses: [(bottle: Bottle, status: ApogeeStatus)] = inCellar.map {
            ($0, ApogeeEngine.status(for: $0, now: now))
        }

        let readyToDrink = statuses.reduce(0) { partial, entry in
            (entry.status == .ready || entry.status == .peak)
                ? partial + max(entry.bottle.quantity, 0)
                : partial
        }

        // Priorité : à boire vite, puis à l'apogée, puis prêt à boire.
        func priority(_ status: ApogeeStatus) -> Int {
            switch status {
            case .drinkSoon: return 0
            case .peak: return 1
            case .ready: return 2
            default: return 3
            }
        }

        let priorityItems = statuses
            .filter { priority($0.status) < 3 }
            .sorted { priority($0.status) < priority($1.status) }
            .prefix(5)
            .map { entry -> WidgetSnapshot.Item in
                let bottle = entry.bottle
                let wine = bottle.wine
                return WidgetSnapshot.Item(
                    id: bottle.id,
                    wineName: wine?.name ?? "Vin",
                    producer: wine?.producer?.name ?? "",
                    vintage: bottle.vintage,
                    statusLabel: entry.status.label,
                    colorHex: hex(for: wine?.color ?? .red)
                )
            }

        let snapshot = WidgetSnapshot(
            totalBottles: totalBottles,
            readyToDrink: readyToDrink,
            priorityItems: Array(priorityItems),
            generatedAt: now
        )

        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
