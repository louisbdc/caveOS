import SwiftUI
import SwiftData

/// Recherche et filtrage des bouteilles, 100 % en mémoire (offline instantané).
struct SearchView: View {
    @Query(sort: [SortDescriptor(\Bottle.createdAt, order: .reverse)])
    private var bottles: [Bottle]

    @State private var filter = WineFilter()
    @State private var sort: SortOption = .dateAdded

    private let now = Date()

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    emptyState
                } else {
                    ForEach(results) { bottle in
                        BottleRow(bottle: bottle, now: now)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Recherche")
            .searchable(
                text: $filter.text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Vin, domaine, appellation"
            )
            .toolbar { sortToolbar }
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
        }
    }

    // MARK: - Filtrage + tri (en mémoire)

    private var results: [Bottle] {
        bottles
            .filter { filter.matches($0, now: now) }
            .sorted(by: sort.comparator)
    }

    // MARK: - Barre de filtres

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                colorMenu
                statusMenu
                regionMenu
                priceMenu
                if !filter.isEmpty {
                    Button {
                        filter = WineFilter()
                    } label: {
                        Label("Réinitialiser", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.wine)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
        }
        .background(.bar)
    }

    private var colorMenu: some View {
        Menu {
            ForEach(WineColor.allCases) { color in
                Button {
                    filter.colors.toggle(color)
                } label: {
                    Label(color.label, systemImage: filter.colors.contains(color) ? "checkmark" : "")
                }
            }
            if !filter.colors.isEmpty {
                Divider()
                Button("Effacer", role: .destructive) { filter.colors = [] }
            }
        } label: {
            FilterChip(
                title: filter.colors.isEmpty
                    ? "Couleur"
                    : "Couleur (\(filter.colors.count))",
                isActive: !filter.colors.isEmpty,
                systemImage: "drop.fill"
            )
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(ApogeeStatus.allCases) { status in
                Button {
                    filter.statuses.toggle(status)
                } label: {
                    Label(status.label, systemImage: filter.statuses.contains(status) ? "checkmark" : status.symbol)
                }
            }
            if !filter.statuses.isEmpty {
                Divider()
                Button("Effacer", role: .destructive) { filter.statuses = [] }
            }
        } label: {
            FilterChip(
                title: filter.statuses.isEmpty
                    ? "Apogée"
                    : "Apogée (\(filter.statuses.count))",
                isActive: !filter.statuses.isEmpty,
                systemImage: "clock.fill"
            )
        }
    }

    private var regionMenu: some View {
        Menu {
            Button {
                filter.regionName = nil
            } label: {
                Label("Toutes", systemImage: filter.regionName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(availableRegions, id: \.self) { name in
                Button {
                    filter.regionName = (filter.regionName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.regionName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.regionName ?? "Région",
                isActive: filter.regionName != nil,
                systemImage: "map.fill"
            )
        }
    }

    private var priceMenu: some View {
        Menu {
            ForEach(PriceRange.allCases) { range in
                Button {
                    apply(range)
                } label: {
                    Label(range.label, systemImage: isSelected(range) ? "checkmark" : "")
                }
            }
            if filter.minPrice != nil || filter.maxPrice != nil {
                Divider()
                Button("Effacer", role: .destructive) {
                    filter.minPrice = nil
                    filter.maxPrice = nil
                }
            }
        } label: {
            FilterChip(
                title: priceLabel,
                isActive: filter.minPrice != nil || filter.maxPrice != nil,
                systemImage: "eurosign.circle.fill"
            )
        }
    }

    private var sortToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Trier par", selection: $sort) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Aucun résultat",
            systemImage: "wineglass",
            description: Text("Modifiez votre recherche ou vos filtres.")
        )
        .listRowSeparator(.hidden)
    }

    // MARK: - Données dérivées

    private var availableRegions: [String] {
        let names = bottles.compactMap { $0.wine?.region?.name }
        return Set(names).sorted()
    }

    private var priceLabel: String {
        switch (filter.minPrice, filter.maxPrice) {
        case (nil, nil): return "Prix"
        case let (min?, max?): return "\(Int(min))–\(Int(max)) €"
        case let (min?, nil): return "≥ \(Int(min)) €"
        case let (nil, max?): return "≤ \(Int(max)) €"
        }
    }

    private func apply(_ range: PriceRange) {
        if isSelected(range) {
            filter.minPrice = nil
            filter.maxPrice = nil
        } else {
            filter.minPrice = range.min
            filter.maxPrice = range.max
        }
    }

    private func isSelected(_ range: PriceRange) -> Bool {
        filter.minPrice == range.min && filter.maxPrice == range.max
    }
}

// MARK: - Présentation compacte d'une bouteille

private struct BottleRow: View {
    let bottle: Bottle
    let now: Date

    private var status: ApogeeStatus { ApogeeEngine.status(for: bottle, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(bottle.wine?.name ?? "Vin inconnu")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let vintage = bottle.vintage, vintage > 0 {
                    Text(verbatim: "\(vintage)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("NM")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let producer = bottle.wine?.producer?.name {
                Text(producer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: Theme.Spacing.s) {
                if let color = bottle.wine?.color {
                    StatusBadge(text: color.label, color: color.tint, systemImage: "drop.fill")
                }
                StatusBadge(text: status.label, color: status.tint, systemImage: status.symbol)
                if let price = bottle.purchasePrice {
                    StatusBadge(
                        text: "\(Int(price)) €",
                        color: Theme.gold,
                        systemImage: "eurosign"
                    )
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Composants de la barre de filtres

private struct FilterChip: View {
    let title: String
    let isActive: Bool
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(
            (isActive ? Theme.wine : Color(.systemGray5)),
            in: Capsule()
        )
        .foregroundStyle(isActive ? .white : .primary)
    }
}

// MARK: - Options de tri

private enum SortOption: String, CaseIterable, Identifiable {
    case name, vintage, price, dateAdded
    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Nom"
        case .vintage: return "Millésime"
        case .price: return "Prix"
        case .dateAdded: return "Date d'ajout"
        }
    }

    var comparator: (Bottle, Bottle) -> Bool {
        switch self {
        case .name:
            return { ($0.wine?.name ?? "") .localizedCaseInsensitiveCompare($1.wine?.name ?? "") == .orderedAscending }
        case .vintage:
            return { ($0.vintage ?? 0) > ($1.vintage ?? 0) }
        case .price:
            return { ($0.purchasePrice ?? 0) > ($1.purchasePrice ?? 0) }
        case .dateAdded:
            return { $0.createdAt > $1.createdAt }
        }
    }
}

// MARK: - Fourchettes de prix prédéfinies

private enum PriceRange: String, CaseIterable, Identifiable {
    case under15, from15to30, from30to60, from60to120, over120
    var id: String { rawValue }

    var label: String {
        switch self {
        case .under15: return "Moins de 15 €"
        case .from15to30: return "15 – 30 €"
        case .from30to60: return "30 – 60 €"
        case .from60to120: return "60 – 120 €"
        case .over120: return "Plus de 120 €"
        }
    }

    var min: Double? {
        switch self {
        case .under15: return nil
        case .from15to30: return 15
        case .from30to60: return 30
        case .from60to120: return 60
        case .over120: return 120
        }
    }

    var max: Double? {
        switch self {
        case .under15: return 15
        case .from15to30: return 30
        case .from30to60: return 60
        case .from60to120: return 120
        case .over120: return nil
        }
    }
}

// MARK: - Utilitaires

private extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}

#Preview {
    SearchView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
