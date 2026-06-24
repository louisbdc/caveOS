import SwiftUI
import SwiftData

/// Écran principal d'inventaire : liste des bouteilles avec recherche, filtres
/// et tri intégrés (offline instantané), ajout manuel et via scan.
struct InventoryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Bottle.createdAt, order: .reverse) private var bottles: [Bottle]
    @Query(sort: [SortDescriptor(\Grape.name)]) private var grapes: [Grape]
    @Query(sort: [SortDescriptor(\Appellation.name)]) private var appellations: [Appellation]
    @Query(sort: [SortDescriptor(\Cellar.name)]) private var cellars: [Cellar]

    @State private var isCreating = false
    @State private var isScanning = false
    @State private var scanPrefill: ScannedLabel?
    @State private var prefilledBottle: Bottle?
    @State private var isShowingSettings = false

    @State private var filter = WineFilter()
    @State private var sort: SortOption = .dateAdded
    @State private var secondarySort: SortOption?
    @State private var sortAscending = false

    private let now = Date()

    var body: some View {
        NavigationStack {
            Group {
                if bottles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Cave")
            .toolbar { toolbarContent }
            .searchable(
                text: $filter.text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Vin, domaine, appellation"
            )
            .sheet(isPresented: $isCreating) {
                BottleEditView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(item: $prefilledBottle) { bottle in
                BottleEditView(bottle: bottle)
            }
            .fullScreenCover(isPresented: $isScanning) {
                ScanView { label in
                    isScanning = false
                    createPrefilledBottle(from: label)
                }
            }
        }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Réglages")
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isScanning = true
            } label: {
                Image(systemName: "camera")
            }
            .accessibilityLabel("Scanner une étiquette")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Ajouter une bouteille")
        }
        ToolbarItem(placement: .topBarTrailing) {
            sortMenu
        }
    }

    private var sortMenu: some View {
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
        .accessibilityLabel("Trier")
    }

    // MARK: - Liste

    private var list: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView(
                    "Aucun résultat",
                    systemImage: "wineglass",
                    description: Text("Modifiez votre recherche ou vos filtres.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(results) { bottle in
                    NavigationLink {
                        BottleDetailView(bottle: bottle)
                    } label: {
                        BottleRowView(bottle: bottle)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            WineFilterBar(
                filter: $filter,
                regions: availableRegions,
                appellations: availableAppellations,
                grapes: availableGrapes,
                vintages: availableVintages,
                locations: availableLocations
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Cave vide", systemImage: "wineglass")
        } description: {
            Text("Ajoutez votre première bouteille manuellement ou en scannant une étiquette.")
        } actions: {
            Button {
                isCreating = true
            } label: {
                Label("Ajouter une bouteille", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.wine)

            Button {
                isScanning = true
            } label: {
                Label("Scanner une étiquette", systemImage: "camera")
            }
        }
    }

    // MARK: - Filtrage + tri (en mémoire)

    private var results: [Bottle] {
        bottles
            .filter { filter.matches($0, now: now) }
            .sorted { lhs, rhs in
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

    // MARK: - Valeurs disponibles pour les filtres

    private var availableRegions: [String] {
        Set(bottles.compactMap { $0.wine?.region?.name }).sorted()
    }

    private var availableAppellations: [String] {
        Set(appellations.map { $0.name }.filter { !$0.isEmpty }).sorted()
    }

    private var availableGrapes: [String] {
        Set(grapes.map { $0.name }.filter { !$0.isEmpty }).sorted()
    }

    private var availableVintages: [Int] {
        Set(bottles.compactMap { $0.vintage }.filter { $0 > 0 }).sorted(by: >)
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

    // MARK: - Actions

    private func delete(at offsets: IndexSet) {
        let service = NotificationService()
        let toDelete = offsets.map { results[$0] }
        for bottle in toDelete {
            service.cancelAll(for: bottle)
            context.delete(bottle)
        }
        try? context.save()
    }

    /// Crée une bouteille pré-remplie depuis un scan puis ouvre l'éditeur dessus.
    private func createPrefilledBottle(from label: ScannedLabel) {
        let wine = Wine()
        wine.name = label.wineName ?? ""
        context.insert(wine)

        if let producerName = label.producer, !producerName.isEmpty {
            let producer = Producer(name: producerName)
            context.insert(producer)
            wine.producer = producer
        }

        let bottle = Bottle()
        bottle.wine = wine
        if let vintage = label.vintage, vintage > 0 {
            bottle.vintage = vintage
        }
        context.insert(bottle)
        try? context.save()

        prefilledBottle = bottle
    }
}
