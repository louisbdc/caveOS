import SwiftUI
import SwiftData

/// Recherche et filtrage des bouteilles, 100 % en mémoire (offline instantané).
struct SearchView: View {
    @Query(sort: [SortDescriptor(\Bottle.createdAt, order: .reverse)])
    private var bottles: [Bottle]

    @Query(sort: [SortDescriptor(\Grape.name)])
    private var grapes: [Grape]

    @Query(sort: [SortDescriptor(\Appellation.name)])
    private var appellations: [Appellation]

    @Query(sort: [SortDescriptor(\Cellar.name)])
    private var cellars: [Cellar]

    @State private var filter = WineFilter()
    @State private var sort: SortOption = .dateAdded
    @State private var secondarySort: SortOption?
    @State private var sortAscending = false

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
        return bottles
            .filter { filter.matches($0, now: now) }
            .sorted { lhs, rhs in
                // Critère principal (avec sens), puis critère secondaire en départage.
                var primary = sort.order(lhs, rhs)
                if !sortAscending { primary = primary.inverted }
                if primary != .orderedSame { return primary == .orderedAscending }
                if let secondarySort, secondarySort != sort {
                    let secondary = secondarySort.order(lhs, rhs)
                    if secondary != .orderedSame { return secondary == .orderedAscending }
                }
                return false
            }
    }

    // MARK: - Barre de filtres

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                colorMenu
                statusMenu
                regionMenu
                appellationMenu
                grapeMenu
                vintageMenu
                locationMenu
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

    private var appellationMenu: some View {
        Menu {
            Button {
                filter.appellationName = nil
            } label: {
                Label("Toutes", systemImage: filter.appellationName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(availableAppellations, id: \.self) { name in
                Button {
                    filter.appellationName = (filter.appellationName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.appellationName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.appellationName ?? "Appellation",
                isActive: filter.appellationName != nil,
                systemImage: "seal.fill"
            )
        }
    }

    private var grapeMenu: some View {
        Menu {
            Button {
                filter.grapeName = nil
            } label: {
                Label("Tous", systemImage: filter.grapeName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(availableGrapes, id: \.self) { name in
                Button {
                    filter.grapeName = (filter.grapeName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.grapeName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.grapeName ?? "Cépage",
                isActive: filter.grapeName != nil,
                systemImage: "leaf.fill"
            )
        }
    }

    private var vintageMenu: some View {
        Menu {
            Section("Millésime minimum") {
                Button {
                    filter.vintageMin = nil
                } label: {
                    Label("Indifférent", systemImage: filter.vintageMin == nil ? "checkmark" : "")
                }
                ForEach(availableVintages, id: \.self) { year in
                    Button {
                        filter.vintageMin = (filter.vintageMin == year) ? nil : year
                    } label: {
                        Label("\(year)", systemImage: filter.vintageMin == year ? "checkmark" : "")
                    }
                }
            }
            Section("Millésime maximum") {
                Button {
                    filter.vintageMax = nil
                } label: {
                    Label("Indifférent", systemImage: filter.vintageMax == nil ? "checkmark" : "")
                }
                ForEach(availableVintages, id: \.self) { year in
                    Button {
                        filter.vintageMax = (filter.vintageMax == year) ? nil : year
                    } label: {
                        Label("\(year)", systemImage: filter.vintageMax == year ? "checkmark" : "")
                    }
                }
            }
        } label: {
            FilterChip(
                title: vintageLabel,
                isActive: filter.vintageMin != nil || filter.vintageMax != nil,
                systemImage: "calendar"
            )
        }
    }

    private var locationMenu: some View {
        Menu {
            Button {
                filter.locationName = nil
            } label: {
                Label("Tous", systemImage: filter.locationName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(availableLocations, id: \.self) { name in
                Button {
                    filter.locationName = (filter.locationName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.locationName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.locationName ?? "Emplacement",
                isActive: filter.locationName != nil,
                systemImage: "square.grid.3x3.fill"
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
                Divider()
                Picker("Sens", selection: $sortAscending) {
                    Label("Ascendant", systemImage: "arrow.up").tag(true)
                    Label("Descendant", systemImage: "arrow.down").tag(false)
                }
                Divider()
                Picker("Puis par", selection: $secondarySort) {
                    Text("Aucun").tag(SortOption?.none)
                    ForEach(SortOption.allCases) { option in
                        Text(option.label).tag(SortOption?.some(option))
                    }
                }
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
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

    private var availableAppellations: [String] {
        let names = appellations.map { $0.name }.filter { !$0.isEmpty }
        return Set(names).sorted()
    }

    private var availableGrapes: [String] {
        let names = grapes.map { $0.name }.filter { !$0.isEmpty }
        return Set(names).sorted()
    }

    private var availableVintages: [Int] {
        let years = bottles.compactMap { $0.vintage }.filter { $0 > 0 }
        return Set(years).sorted(by: >)
    }

    private var availableLocations: [String] {
        var names: Set<String> = []
        for cellar in cellars where !cellar.name.isEmpty {
            names.insert(cellar.name)
        }
        for bottle in bottles {
            if let label = bottle.location?.label, !label.isEmpty {
                names.insert(label)
            }
        }
        return names.sorted()
    }

    private var vintageLabel: String {
        switch (filter.vintageMin, filter.vintageMax) {
        case (nil, nil): return "Millésime"
        case let (min?, max?): return min == max ? "\(min)" : "\(min)–\(max)"
        case let (min?, nil): return "≥ \(min)"
        case let (nil, max?): return "≤ \(max)"
        }
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

private extension ComparisonResult {
    var inverted: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

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

    /// Ordre naturel ascendant, composable (permet le tri multi-critères).
    func order(_ a: Bottle, _ b: Bottle) -> ComparisonResult {
        switch self {
        case .name:
            return (a.wine?.name ?? "").localizedCaseInsensitiveCompare(b.wine?.name ?? "")
        case .vintage:
            return compare(a.vintage ?? 0, b.vintage ?? 0)
        case .price:
            return compare(a.purchasePrice ?? 0, b.purchasePrice ?? 0)
        case .dateAdded:
            return compare(a.createdAt, b.createdAt)
        }
    }

    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
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
