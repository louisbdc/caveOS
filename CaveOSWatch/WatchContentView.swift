import SwiftUI

/// Résumé de cave consultable rapidement depuis la montre.
struct WatchContentView: View {
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        List {
            Section {
                summaryRow(
                    title: "Bouteilles",
                    value: "\(session.total)",
                    symbol: "wineglass",
                    tint: .purple
                )
                summaryRow(
                    title: "À boire",
                    value: "\(session.ready)",
                    symbol: "checkmark.seal.fill",
                    tint: .green
                )
            }

            if session.items.isEmpty {
                Section {
                    Text("Aucune bouteille prioritaire")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Prioritaires") {
                    ForEach(Array(session.items.enumerated()), id: \.offset) { _, item in
                        priorityRow(item)
                    }
                }
            }
        }
        .navigationTitle("Ma cave")
    }

    private func summaryRow(
        title: String,
        value: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
            Spacer()
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }

    private func priorityRow(_ item: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item["name"] ?? "—")
                .font(.body)
                .lineLimit(1)
            if let subtitle = item["subtitle"], !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
