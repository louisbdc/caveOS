import SwiftUI

/// Ligne d'inventaire représentant une bouteille (nom, domaine, millésime, format, badges).
struct BottleRowView: View {
    let bottle: Bottle

    private var wineName: String {
        let name = bottle.wine?.name ?? ""
        return name.isEmpty ? "Vin sans nom" : name
    }

    private var producerName: String? {
        let name = bottle.wine?.producer?.name
        return (name?.isEmpty ?? true) ? nil : name
    }

    private var vintageText: String {
        if let vintage = bottle.vintage, vintage > 0 {
            return String(vintage)
        }
        return "Sans millésime"
    }

    private var apogeeStatus: ApogeeStatus {
        ApogeeEngine.status(for: bottle, now: Date())
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(bottle.wine?.color.tint ?? Theme.wine)
                .frame(width: 6, height: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(wineName)
                    .font(.headline)
                    .lineLimit(1)

                if let producerName {
                    Text(producerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: Theme.Spacing.s) {
                    Text(vintageText)
                    Text("•")
                    Text(bottle.format.label)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: Theme.Spacing.s) {
                    if let color = bottle.wine?.color {
                        StatusBadge(text: color.label, color: color.tint)
                    }
                    StatusBadge(
                        text: apogeeStatus.label,
                        color: apogeeStatus.tint,
                        systemImage: apogeeStatus.symbol
                    )
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text("×\(bottle.quantity)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.wine)
                Image(systemName: bottle.state.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
