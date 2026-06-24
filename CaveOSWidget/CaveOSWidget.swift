import WidgetKit
import SwiftUI

// MARK: - Palette

private enum WidgetPalette {
    static let bordeaux = Color(red: 0.45, green: 0.07, blue: 0.13)
    static let bordeauxDark = Color(red: 0.28, green: 0.05, blue: 0.09)
    static let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
}

private extension Color {
    /// Construit une couleur depuis un hex de la forme `#RRGGBB` (fallback bordeaux).
    init(widgetHex hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = WidgetPalette.bordeaux
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Timeline

struct CaveOSEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct CaveOSProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaveOSEntry {
        CaveOSEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaveOSEntry) -> Void) {
        completion(CaveOSEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaveOSEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let entry = CaveOSEntry(date: Date(), snapshot: snapshot)
        // Rafraîchit régulièrement ; l'app force aussi un reload après chaque modification.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date().addingTimeInterval(21_600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Vues

private struct StatBlock: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(WidgetPalette.cream)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetPalette.cream.opacity(0.75))
        }
    }
}

private struct PriorityRow: View {
    let item: WidgetSnapshot.Item

    private var title: String {
        if let vintage = item.vintage, vintage > 0 {
            return "\(item.wineName) \(vintage)"
        }
        return item.wineName
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(widgetHex: item.colorHex))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetPalette.cream)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(item.statusLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WidgetPalette.cream.opacity(0.7))
                .lineLimit(1)
        }
    }
}

struct CaveOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaveOSEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    private var maxRows: Int { family == .systemMedium ? 3 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                StatBlock(value: snapshot.totalBottles, label: "Bouteilles")
                StatBlock(value: snapshot.readyToDrink, label: "À boire")
                Spacer(minLength: 0)
            }

            if snapshot.priorityItems.isEmpty {
                Spacer(minLength: 0)
                Text("Aucune priorité")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.cream.opacity(0.7))
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.priorityItems.prefix(maxRows)) { item in
                        PriorityRow(item: item)
                    }
                }
                if family == .systemMedium { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [WidgetPalette.bordeaux, WidgetPalette.bordeauxDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Widget

struct CaveOSWidget: Widget {
    let kind = "CaveOSWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaveOSProvider()) { entry in
            CaveOSWidgetView(entry: entry)
        }
        .configurationDisplayName("Ma cave")
        .description("Aperçu de votre cave et des vins à boire en priorité.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CaveOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaveOSWidget()
    }
}
