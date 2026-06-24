import SwiftUI
import SwiftData

/// Fiche détaillée d'une bouteille : informations, fenêtre d'apogée, dégustations, actions.
struct BottleDetailView: View {
    @Environment(\.modelContext) private var context
    let bottle: Bottle

    @State private var isEditing = false

    private var wineName: String {
        let name = bottle.wine?.name ?? ""
        return name.isEmpty ? "Vin sans nom" : name
    }

    private var apogeeStatus: ApogeeStatus {
        ApogeeEngine.status(for: bottle, now: Date())
    }

    private var apogeeWindow: ApogeeEngine.Window? {
        ApogeeEngine.window(for: bottle, now: Date())
    }

    var body: some View {
        List {
            headerSection
            infoSection
            apogeeSection
            if bottle.state == .opened {
                openedSection
            }
            tastingSection
            actionsSection
        }
        .navigationTitle(wineName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Éditer") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            BottleEditView(bottle: bottle)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let producer = bottle.wine?.producer?.name, !producer.isEmpty {
                    Text(producer).font(.headline).foregroundStyle(.secondary)
                }
                HStack(spacing: Theme.Spacing.s) {
                    if let color = bottle.wine?.color {
                        StatusBadge(text: color.label, color: color.tint)
                    }
                    StatusBadge(
                        text: apogeeStatus.label,
                        color: apogeeStatus.tint,
                        systemImage: apogeeStatus.symbol
                    )
                    StatusBadge(text: bottle.state.label, color: Theme.slate, systemImage: bottle.state.symbol)
                }
            }
        }
    }

    private var infoSection: some View {
        Section("Informations") {
            if let vintage = bottle.vintage, vintage > 0 {
                labelRow("Millésime", String(vintage))
            } else {
                labelRow("Millésime", "Sans millésime")
            }
            labelRow("Format", bottle.format.label)
            labelRow("Quantité", "×\(bottle.quantity)")
            if let region = bottle.wine?.region?.name { labelRow("Région", region) }
            if let appellation = bottle.wine?.appellation?.name { labelRow("Appellation", appellation) }
            if let grapes = bottle.wine?.grapes, !grapes.isEmpty {
                labelRow("Cépages", grapes.map(\.name).joined(separator: ", "))
            }
            labelRow("Qualité de stockage", bottle.storageQuality.label)
            if let price = bottle.purchasePrice {
                labelRow("Prix d'achat", String(format: "%.2f €", price))
            }
            if let date = bottle.purchaseDate {
                labelRow("Date d'achat", date.formatted(date: .abbreviated, time: .omitted))
            }
            if let supplier = bottle.supplier, !supplier.isEmpty {
                labelRow("Fournisseur", supplier)
            }
            if let location = bottle.location?.label, !location.isEmpty {
                labelRow("Emplacement", location)
            }
            if let notes = bottle.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    Text(notes)
                }
            }
        }
    }

    private var apogeeSection: some View {
        Section("Apogée") {
            HStack {
                Image(systemName: apogeeStatus.symbol)
                Text(apogeeStatus.label)
                Spacer()
            }
            .foregroundStyle(apogeeStatus.tint)
            if let window = apogeeWindow {
                labelRow("À boire à partir de", String(window.drinkFrom))
                labelRow("Apogée", String(window.peak))
                labelRow("À boire avant", String(window.drinkBy))
            } else {
                Text("Fenêtre d'apogée indisponible").foregroundStyle(.secondary)
            }
        }
    }

    private var openedSection: some View {
        Section("Bouteille entamée") {
            if let date = bottle.openedDate {
                labelRow("Ouverte le", date.formatted(date: .abbreviated, time: .omitted))
            }
            if let servings = bottle.remainingServings {
                labelRow("Verres restants", String(servings))
            }
            labelRow("Conservation", bottle.conservation.label)
        }
    }

    private var tastingSection: some View {
        Section("Dégustations") {
            let notes = fetchTastingNotes()
            if notes.isEmpty {
                Text("Aucune dégustation").foregroundStyle(.secondary)
            } else {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            Text(note.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let score = note.score {
                                StatusBadge(text: "\(score)/100", color: Theme.gold)
                            }
                        }
                        if let text = note.text, !text.isEmpty {
                            Text(text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if bottle.state != .opened {
                Button {
                    markOpened()
                } label: {
                    Label("Marquer entamée", systemImage: "wineglass")
                }
            }
            if bottle.state != .consumed {
                Button(role: .destructive) {
                    markConsumed()
                } label: {
                    Label("Marquer consommée", systemImage: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Helpers

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func fetchTastingNotes() -> [TastingNote] {
        let bottleID = bottle.id
        let descriptor = FetchDescriptor<TastingNote>(
            predicate: #Predicate { $0.bottle?.id == bottleID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func markOpened() {
        bottle.state = .opened
        bottle.openedDate = Date()
        bottle.updatedAt = Date()
        try? context.save()
    }

    private func markConsumed() {
        bottle.state = .consumed
        bottle.updatedAt = Date()
        try? context.save()
    }
}
