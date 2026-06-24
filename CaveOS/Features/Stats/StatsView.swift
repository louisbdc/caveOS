import SwiftUI
import SwiftData
import Charts

/// Tableau de bord analytique de la cave (Swift Charts).
///
/// Synthétise l'inventaire : volumétrie, valeur estimée, et répartitions
/// par couleur, région et statut d'apogée. Met en avant les bouteilles
/// à boire en priorité.
struct StatsView: View {
    @Query private var bottles: [Bottle]

    var body: some View {
        NavigationStack {
            Group {
                if activeBottles.isEmpty {
                    ContentUnavailableView(
                        "Aucune bouteille en cave",
                        systemImage: "chart.pie",
                        description: Text(bottles.isEmpty
                            ? "Ajoutez des bouteilles pour découvrir vos statistiques."
                            : "Vous avez consommé toutes vos bouteilles. Ajoutez-en pour suivre votre cave.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Statistiques")
        }
    }

    // MARK: - Contenu

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                summaryCard
                colorCard
                regionCard
                apogeeCard
                priorityCard
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.surface.opacity(0.4))
    }

    // MARK: - Synthèse

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Vue d'ensemble")
                .font(.headline)
            HStack(spacing: Theme.Spacing.m) {
                metric(value: "\(distinctBottleCount)", label: "Entrées")
                metric(value: "\(totalQuantity)", label: "Bouteilles")
                metric(value: formattedValue, label: "Valeur estimée")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.wine)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Répartition par couleur

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Répartition par couleur")
                .font(.headline)
            if colorBreakdown.isEmpty {
                emptyChartHint
            } else {
                Chart(colorBreakdown) { item in
                    SectorMark(
                        angle: .value("Quantité", item.quantity),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .cornerRadius(Theme.Radius.s)
                    .foregroundStyle(item.color.tint)
                    .annotation(position: .overlay) {
                        if item.quantity > 0 {
                            Text("\(item.quantity)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 220)
                colorLegend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var colorLegend: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            ForEach(colorBreakdown) { item in
                StatusBadge(text: "\(item.color.label) · \(item.quantity)", color: item.color.tint)
            }
        }
    }

    // MARK: - Répartition par région

    private var regionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(distinctRegionCount > 6 ? "Top régions (6 principales sur \(distinctRegionCount))" : "Régions")
                .font(.headline)
            if regionBreakdown.isEmpty {
                emptyChartHint
            } else {
                Chart(regionBreakdown) { item in
                    BarMark(
                        x: .value("Quantité", item.quantity),
                        y: .value("Région", item.name)
                    )
                    .foregroundStyle(Theme.wine.gradient)
                    .cornerRadius(Theme.Radius.s)
                    .annotation(position: .trailing) {
                        Text("\(item.quantity)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(regionBreakdown.count) * 44 + 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Répartition par statut d'apogée

    private var apogeeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Maturité de la cave")
                .font(.headline)
            if apogeeBreakdown.isEmpty {
                emptyChartHint
            } else {
                Chart(apogeeBreakdown) { item in
                    BarMark(
                        x: .value("Statut", item.status.label),
                        y: .value("Quantité", item.quantity)
                    )
                    .foregroundStyle(item.status.tint)
                    .cornerRadius(Theme.Radius.s)
                    .annotation(position: .top) {
                        Text("\(item.quantity)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
            }
            if undatedQuantity > 0 {
                Text("\(undatedQuantity) bouteille(s) sans millésime ne sont pas comptées ici.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - À boire en priorité

    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("À boire en priorité")
                .font(.headline)
            if priorityBottles.isEmpty {
                Text("Aucune bouteille n'est à boire en urgence. Belle cave !")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(priorityBottles, id: \.id) { bottle in
                        NavigationLink {
                            BottleDetailView(bottle: bottle)
                        } label: {
                            priorityRow(bottle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func priorityRow(_ bottle: Bottle) -> some View {
        let status = ApogeeEngine.status(for: bottle)
        return HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(bottle.wine?.name ?? "Vin sans nom")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    if let producer = bottle.wine?.producer?.name {
                        Text(producer)
                    }
                    if let vintage = bottle.vintage, vintage > 0 {
                        Text(verbatim: "· \(vintage)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            StatusBadge(text: status.label, color: status.tint, systemImage: status.symbol)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Aides

    private var emptyChartHint: some View {
        Text("Pas encore de données.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Calculs

    /// Bouteilles encore en cave (non consommées).
    private var activeBottles: [Bottle] {
        bottles.filter { $0.state != .consumed }
    }

    private var distinctBottleCount: Int {
        activeBottles.count
    }

    private var totalQuantity: Int {
        activeBottles.reduce(0) { $0 + $1.quantity }
    }

    private var totalValue: Double {
        activeBottles.reduce(0) { partial, bottle in
            partial + (bottle.purchasePrice ?? 0) * Double(bottle.quantity)
        }
    }

    private var formattedValue: String {
        totalValue.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
    }

    private var colorBreakdown: [ColorSlice] {
        var totals: [WineColor: Int] = [:]
        for bottle in activeBottles {
            guard let color = bottle.wine?.color else { continue }
            totals[color, default: 0] += bottle.quantity
        }
        return WineColor.allCases
            .compactMap { color in
                guard let quantity = totals[color], quantity > 0 else { return nil }
                return ColorSlice(color: color, quantity: quantity)
            }
    }

    private var regionTotals: [String: Int] {
        var totals: [String: Int] = [:]
        for bottle in activeBottles {
            let name = bottle.wine?.region?.name ?? "Inconnue"
            totals[name, default: 0] += bottle.quantity
        }
        return totals
    }

    private var distinctRegionCount: Int { regionTotals.count }

    private var regionBreakdown: [RegionStat] {
        regionTotals
            .map { RegionStat(name: $0.key, quantity: $0.value) }
            .sorted { $0.quantity > $1.quantity }
            .prefix(6)
            .map { $0 }
    }

    private var apogeeBreakdown: [ApogeeStat] {
        var totals: [ApogeeStatus: Int] = [:]
        for bottle in activeBottles {
            let status = ApogeeEngine.status(for: bottle)
            totals[status, default: 0] += bottle.quantity
        }
        // On exclut « Inconnu » (vins sans millésime) pour ne pas fausser la lecture de la maturité.
        let order: [ApogeeStatus] = [.tooYoung, .ready, .peak, .drinkSoon, .past]
        return order.compactMap { status in
            guard let quantity = totals[status], quantity > 0 else { return nil }
            return ApogeeStat(status: status, quantity: quantity)
        }
    }

    /// Quantité de bouteilles sans statut d'apogée déterminable (sans millésime).
    private var undatedQuantity: Int {
        activeBottles
            .filter { ApogeeEngine.status(for: $0) == .unknown }
            .reduce(0) { $0 + $1.quantity }
    }

    /// Bouteilles en pleine apogée ou à consommer rapidement.
    private var priorityBottles: [Bottle] {
        activeBottles
            .filter {
                let status = ApogeeEngine.status(for: $0)
                return status == .drinkSoon || status == .peak
            }
            .sorted { lhs, rhs in
                let lhsWindow = ApogeeEngine.window(for: lhs)?.drinkBy ?? .max
                let rhsWindow = ApogeeEngine.window(for: rhs)?.drinkBy ?? .max
                return lhsWindow < rhsWindow
            }
            .prefix(8)
            .map { $0 }
    }
}

// MARK: - Modèles de données pour les graphiques

private struct ColorSlice: Identifiable {
    let color: WineColor
    let quantity: Int
    var id: WineColor { color }
}

private struct RegionStat: Identifiable {
    let name: String
    let quantity: Int
    var id: String { name }
}

private struct ApogeeStat: Identifiable {
    let status: ApogeeStatus
    let quantity: Int
    var id: String { status.label }
}

// MARK: - Mise en page fluide (légende)

/// Disposition à la ligne pour les pastilles de légende.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, currentRowWidth > 0 {
                totalHeight += rowHeight + spacing
                currentRowWidth = 0
                rowHeight = 0
                rows.append(0)
            }
            currentRowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
