import SwiftUI
import SwiftData

/// Écran principal d'inventaire : liste des bouteilles, ajout manuel et via scan.
struct InventoryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Bottle.createdAt, order: .reverse) private var bottles: [Bottle]

    @State private var isCreating = false
    @State private var isScanning = false
    @State private var scanPrefill: ScannedLabel?
    @State private var prefilledBottle: Bottle?
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if bottles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Inventaire")
            .toolbar {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
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

    // MARK: - Sous-vues

    private var list: some View {
        List {
            ForEach(bottles) { bottle in
                NavigationLink {
                    BottleDetailView(bottle: bottle)
                } label: {
                    BottleRowView(bottle: bottle)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
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

    // MARK: - Actions

    private func delete(at offsets: IndexSet) {
        let service = NotificationService()
        for index in offsets {
            let bottle = bottles[index]
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
