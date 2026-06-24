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
                    if bottle.state != .inCellar {
                        StatusBadge(
                            text: bottle.state.label,
                            color: stateTint,
                            systemImage: bottle.state.symbol
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text("×\(bottle.quantity)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.wine)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .opacity(bottle.state == .consumed ? 0.5 : 1)
    }

    /// Couleur du badge d'état : ambre pour entamée, neutre pour consommée.
    private var stateTint: Color {
        switch bottle.state {
        case .opened: return Color(red: 0.85, green: 0.55, blue: 0.20)
        case .consumed: return Theme.slate
        case .inCellar: return Theme.slate
        }
    }
}
