import SwiftUI

/// Ligne d'un vin classé dans l'écran de résultats de la carte restaurant.
/// Affiche le nom, le producteur, le millésime, le prix et les badges contextuels.
struct MenuWineRow: View {
    let item: RankedMenuWine

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            headerRow
            if hasBadges {
                badgeRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.wine.wineName ?? "Vin inconnu")
                    .font(.subheadline.weight(.semibold))
                if let producer = item.wine.producer, !producer.isEmpty {
                    Text(producer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let vintage = item.wine.vintage {
                    Text(verbatim: "\(vintage)")
                        .font(.caption.weight(.semibold))
                }
                if let price = item.wine.price {
                    Text(formattedPrice(price))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Badges

    private var hasBadges: Bool {
        pairingIsVisible || valueIsVisible || item.drinkNow || item.cellarCount > 0 || item.personalScore != nil
    }

    private var pairingIsVisible: Bool {
        guard let p = item.pairing else { return false }
        return p != .poor
    }

    private var valueIsVisible: Bool {
        item.value == .goodValue || item.value == .expensive
    }

    private var badgeRow: some View {
        BadgeWrapLayout(spacing: Theme.Spacing.xs) {
            if let pairing = item.pairing, pairing != .poor {
                StatusBadge(
                    text: pairingLabel(pairing),
                    color: pairing == .perfect ? Theme.gold : Theme.slate
                )
            }
            if item.value == .goodValue {
                StatusBadge(text: "bon Q/P", color: .green)
            } else if item.value == .expensive {
                StatusBadge(text: "cher", color: Theme.wine)
            }
            if item.drinkNow {
                StatusBadge(text: "à boire maintenant", color: Theme.gold, systemImage: "wineglass")
            }
            if item.cellarCount > 0 {
                StatusBadge(text: "\(item.cellarCount) en cave", color: Theme.slate, systemImage: "building.columns")
            }
            if let score = item.personalScore {
                StatusBadge(text: "noté \(score)/100", color: Theme.gold, systemImage: "star.fill")
            }
        }
    }

    // MARK: - Helpers

    private func pairingLabel(_ pairing: PairingScore) -> String {
        switch pairing {
        case .perfect: return "★ accord parfait"
        case .good:    return "◐ bon accord"
        case .ok:      return "◐ accord correct"
        case .poor:    return ""
        }
    }

    private func formattedPrice(_ price: Double) -> String {
        let symbol = item.wine.currency ?? "€"
        return String(format: "%.0f %@", price, symbol)
    }
}

// MARK: - Layout de badges (wrapping multi-lignes)

/// Layout maison qui répartit ses enfants sur plusieurs lignes selon la largeur disponible.
/// Copie du pattern FlowRow de PairingView, localisé pour ne pas polluer l'espace de noms global.
private struct BadgeWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(
            width: maxWidth == .infinity ? (rows.map(\.width).max() ?? 0) : maxWidth,
            height: height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowLayout {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [RowLayout] {
        var rows: [RowLayout] = []
        var current = RowLayout()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.width == 0 ? size.width : current.width + spacing + size.width
            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = RowLayout(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MenuWineRow — variantes") {
    let perfect = RankedMenuWine(
        wine: PreviewMenuWine.make(
            lineIndex: 0, producer: "Château Margaux", name: "Grand Vin",
            vintage: 2018, price: 320.0
        ),
        value: .expensive,
        pairing: .perfect,
        drinkNow: false,
        cellarCount: 2,
        personalScore: 95
    )
    let good = RankedMenuWine(
        wine: PreviewMenuWine.make(
            lineIndex: 1, producer: "Domaine Leflaive", name: "Puligny-Montrachet",
            vintage: 2020, price: 72.0
        ),
        value: .goodValue,
        pairing: .good,
        drinkNow: true,
        cellarCount: 0,
        personalScore: nil
    )
    let noInfo = RankedMenuWine(
        wine: PreviewMenuWine.make(
            lineIndex: 2, producer: nil, name: "Bordeaux Générique",
            vintage: nil, price: nil
        ),
        value: .unknown,
        pairing: nil,
        drinkNow: false,
        cellarCount: 0,
        personalScore: nil
    )
    return ScrollView {
        VStack(spacing: Theme.Spacing.s) {
            MenuWineRow(item: perfect)
            MenuWineRow(item: good)
            MenuWineRow(item: noInfo)
        }
        .padding(Theme.Spacing.m)
    }
    .background(Theme.surface.opacity(0.4))
}

/// Helpers de prévisualisation uniquement — permet de construire des ScannedMenuWine sans décodeur JSON.
enum PreviewMenuWine {
    static func make(
        lineIndex: Int,
        producer: String?,
        name: String?,
        vintage: Int?,
        price: Double?
    ) -> ScannedMenuWine {
        var dict: [String: Any] = ["lineIndex": lineIndex, "byGlass": false]
        if let producer { dict["producer"] = producer }
        if let name { dict["wineName"] = name }
        if let vintage { dict["vintage"] = vintage }
        if let price { dict["price"] = price }
        // swiftlint:disable:next force_try
        let data = try! JSONSerialization.data(withJSONObject: dict)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(ScannedMenuWine.self, from: data)
    }
}
#endif
