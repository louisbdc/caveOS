import Foundation

/// Instantané léger de la cave partagé entre l'app et le widget via l'App Group.
/// L'app l'écrit après chaque sauvegarde ; le widget le lit (pas d'accès SwiftData partagé).
struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: UUID
        var wineName: String
        var producer: String
        var vintage: Int?
        var statusLabel: String
        var colorHex: String
    }

    var totalBottles: Int
    var readyToDrink: Int
    var priorityItems: [Item]
    var generatedAt: Date

    static let empty = WidgetSnapshot(totalBottles: 0, readyToDrink: 0, priorityItems: [], generatedAt: Date(timeIntervalSince1970: 0))
}

/// Accès au fichier d'instantané dans le conteneur App Group.
enum WidgetSnapshotStore {
    static let appGroupID = "group.com.louisbdc.caveos"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Échec d'écriture du snapshot widget: \(error)")
        }
    }

    static func read() -> WidgetSnapshot {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
