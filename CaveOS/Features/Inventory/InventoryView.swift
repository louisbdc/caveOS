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
        let deletedIDs = Set(toDelete.map(\.id))
        let affectedWines = Set(toDelete.compactMap(\.wine))

        for bottle in toDelete {
            service.cancelAll(for: bottle)
            context.delete(bottle)
        }

        cleanupOrphans(after: affectedWines, deletedBottleIDs: deletedIDs)

        try? context.save()
        SnapshotCoordinator.refresh(modelContext: context)
    }

    /// Supprime les vins devenus sans bouteille (et leur producteur s'il n'est plus
    /// utilisé), pour éviter l'accumulation d'entités orphelines créées par l'utilisateur.
    /// Les données de référence embarquées (région, appellation, cépage) ne sont jamais touchées.
    private func cleanupOrphans(after wines: Set<Wine>, deletedBottleIDs: Set<UUID>) {
        for wine in wines {
            let remaining = wine.bottles.filter { !deletedBottleIDs.contains($0.id) }
            guard remaining.isEmpty else { continue }
            let producer = wine.producer
            context.delete(wine)
            if let producer { deleteProducerIfUnused(producer, excludingWineID: wine.id) }
        }
    }

    /// Supprime un producteur s'il n'est plus rattaché à aucun autre vin.
    private func deleteProducerIfUnused(_ producer: Producer, excludingWineID: UUID) {
        let producerID = producer.id
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate { $0.producer?.id == producerID }
        )
        let stillUsing = (try? context.fetch(descriptor))?.filter { $0.id != excludingWineID } ?? []
        if stillUsing.isEmpty {
            context.delete(producer)
        }
    }

    /// Crée une bouteille pré-remplie depuis un scan puis ouvre l'éditeur dessus.
    /// Relie tout le résultat OCR (producteur, appellation, cépages, EAN, format)
    /// aux entités existantes pour éviter les doublons.
    private func createPrefilledBottle(from label: ScannedLabel) {
        let wine = Wine()
        wine.name = label.wineName ?? ""
        context.insert(wine)

        if let producerName = label.producer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !producerName.isEmpty {
            wine.producer = resolveProducer(named: producerName)
        }

        if let appellationName = label.appellation,
           let appellation = firstMatch(of: Appellation.self, name: appellationName, key: { $0.name }) {
            wine.appellation = appellation
            if let regionName = appellation.regionName,
               let region = firstMatch(of: Region.self, name: regionName, key: { $0.name }) {
                wine.region = region
            }
        }

        if !label.grapes.isEmpty {
            wine.grapes = label.grapes.compactMap { name in
                firstMatch(of: Grape.self, name: name, key: { $0.name })
            }
        }

        let bottle = Bottle()
        bottle.wine = wine
        if let vintage = label.vintage, vintage > 0 {
            bottle.vintage = vintage
        }
        if let ean = label.ean, let valid = ScanView.validEAN(ean) {
            bottle.ean = valid
        }
        if let formatLabel = label.format,
           let format = BottleFormat.allCases.first(where: { $0.label == formatLabel }) {
            bottle.format = format
        }
        context.insert(bottle)
        try? context.save()
        SnapshotCoordinator.refresh(modelContext: context)

        prefilledBottle = bottle
    }

    /// Réutilise un producteur existant (insensible casse/accents) ou en crée un.
    private func resolveProducer(named name: String) -> Producer {
        if let existing = firstMatch(of: Producer.self, name: name, key: { $0.name }) {
            return existing
        }
        let producer = Producer(name: name)
        context.insert(producer)
        return producer
    }

    /// Recherche une entité de référence par nom (insensible casse/accents).
    private func firstMatch<T: PersistentModel>(
        of type: T.Type, name: String, key: (T) -> String
    ) -> T? {
        let target = name.foldedForMatch
        guard !target.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.first { key($0).foldedForMatch == target }
    }
}
