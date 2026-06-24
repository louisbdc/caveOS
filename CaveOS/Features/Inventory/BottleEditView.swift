import SwiftUI
import SwiftData

/// Formulaire de création / édition d'une bouteille (et du vin associé).
/// Seul le nom du vin est requis.
struct BottleEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Region.name) private var regions: [Region]
    @Query(sort: \Appellation.name) private var appellations: [Appellation]
    @Query(sort: \Grape.name) private var grapes: [Grape]

    /// Bouteille existante (édition) ou nil (création).
    private let existingBottle: Bottle?

    // MARK: - Champs « vin »
    @State private var wineName: String
    @State private var producerName: String
    @State private var color: WineColor
    @State private var type: WineType
    @State private var selectedRegionID: UUID?
    @State private var selectedAppellationID: UUID?
    @State private var selectedGrapeIDs: Set<UUID>

    // MARK: - Champs « bouteille »
    @State private var vintageText: String
    @State private var format: BottleFormat
    @State private var quantity: Int
    @State private var purchasePriceText: String
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var supplier: String
    @State private var storageQuality: StorageQuality
    @State private var notes: String

    // MARK: - État entamée
    @State private var state: BottleState
    @State private var openedDate: Date
    @State private var remainingServingsText: String
    @State private var conservation: ConservationMethod

    init(bottle: Bottle? = nil, prefill: ScannedLabel? = nil) {
        self.existingBottle = bottle

        let wine = bottle?.wine
        _wineName = State(initialValue: wine?.name ?? prefill?.wineName ?? "")
        _producerName = State(initialValue: wine?.producer?.name ?? prefill?.producer ?? "")
        _color = State(initialValue: wine?.color ?? .red)
        _type = State(initialValue: wine?.type ?? .still)
        _selectedRegionID = State(initialValue: wine?.region?.id)
        _selectedAppellationID = State(initialValue: wine?.appellation?.id)
        _selectedGrapeIDs = State(initialValue: Set((wine?.grapes ?? []).map(\.id)))

        let vintage = bottle?.vintage ?? prefill?.vintage
        _vintageText = State(initialValue: (vintage.map { $0 > 0 ? String($0) : "" }) ?? "")
        _format = State(initialValue: bottle?.format ?? .bottle)
        _quantity = State(initialValue: bottle?.quantity ?? 1)
        _purchasePriceText = State(initialValue: bottle?.purchasePrice.map { String(format: "%.2f", $0) } ?? "")
        _hasPurchaseDate = State(initialValue: bottle?.purchaseDate != nil)
        _purchaseDate = State(initialValue: bottle?.purchaseDate ?? Date())
        _supplier = State(initialValue: bottle?.supplier ?? "")
        _storageQuality = State(initialValue: bottle?.storageQuality ?? .good)
        _notes = State(initialValue: bottle?.notes ?? "")

        _state = State(initialValue: bottle?.state ?? .inCellar)
        _openedDate = State(initialValue: bottle?.openedDate ?? Date())
        _remainingServingsText = State(initialValue: bottle?.remainingServings.map(String.init) ?? "")
        _conservation = State(initialValue: bottle?.conservation ?? .none)
    }

    private var isValid: Bool {
        !wineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                wineSection
                originSection
                grapesSection
                bottleSection
                purchaseSection
                stateSection
                notesSection
            }
            .navigationTitle(existingBottle == nil ? "Nouvelle bouteille" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Sections

    private var wineSection: some View {
        Section("Vin") {
            TextField("Nom du vin", text: $wineName)
            TextField("Domaine / Château", text: $producerName)
            Picker("Couleur", selection: $color) {
                ForEach(WineColor.allCases) { Text($0.label).tag($0) }
            }
            Picker("Type", selection: $type) {
                ForEach(WineType.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private var originSection: some View {
        Section("Origine") {
            Picker("Région", selection: $selectedRegionID) {
                Text("Aucune").tag(UUID?.none)
                ForEach(regions) { region in
                    Text(region.name).tag(UUID?.some(region.id))
                }
            }
            Picker("Appellation", selection: $selectedAppellationID) {
                Text("Aucune").tag(UUID?.none)
                ForEach(appellations) { appellation in
                    Text(appellation.name).tag(UUID?.some(appellation.id))
                }
            }
        }
    }

    private var grapesSection: some View {
        Section("Cépages") {
            if grapes.isEmpty {
                Text("Aucun cépage disponible").foregroundStyle(.secondary)
            } else {
                ForEach(grapes) { grape in
                    Button {
                        toggleGrape(grape.id)
                    } label: {
                        HStack {
                            Text(grape.name).foregroundStyle(.primary)
                            Spacer()
                            if selectedGrapeIDs.contains(grape.id) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.wine)
                            }
                        }
                    }
                }
            }
        }
    }

    private var bottleSection: some View {
        Section("Bouteille") {
            TextField("Millésime", text: $vintageText)
                .keyboardType(.numberPad)
            Picker("Format", selection: $format) {
                ForEach(BottleFormat.allCases) { Text($0.label).tag($0) }
            }
            Stepper("Quantité : \(quantity)", value: $quantity, in: 1...999)
            Picker("Qualité de stockage", selection: $storageQuality) {
                ForEach(StorageQuality.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private var purchaseSection: some View {
        Section("Achat") {
            TextField("Prix d'achat (€)", text: $purchasePriceText)
                .keyboardType(.decimalPad)
            Toggle("Date d'achat", isOn: $hasPurchaseDate.animation())
            if hasPurchaseDate {
                DatePicker("Date", selection: $purchaseDate, displayedComponents: .date)
            }
            TextField("Fournisseur", text: $supplier)
        }
    }

    private var stateSection: some View {
        Section("État") {
            Picker("État", selection: $state.animation()) {
                ForEach(BottleState.allCases) { Text($0.label).tag($0) }
            }
            if state == .opened {
                DatePicker("Date d'ouverture", selection: $openedDate, displayedComponents: .date)
                TextField("Verres restants", text: $remainingServingsText)
                    .keyboardType(.numberPad)
                Picker("Conservation", selection: $conservation) {
                    ForEach(ConservationMethod.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Logique

    private func toggleGrape(_ id: UUID) {
        if selectedGrapeIDs.contains(id) {
            selectedGrapeIDs.remove(id)
        } else {
            selectedGrapeIDs.insert(id)
        }
    }

    private func parsedVintage() -> Int? {
        let trimmed = vintageText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func parsedPrice() -> Double? {
        let normalized = purchasePriceText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func resolveProducer(named name: String) -> Producer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let producer = Producer(name: trimmed)
        context.insert(producer)
        return producer
    }

    private func save() {
        let trimmedName = wineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let selectedGrapes = grapes.filter { selectedGrapeIDs.contains($0.id) }
        let region = regions.first { $0.id == selectedRegionID }
        let appellation = appellations.first { $0.id == selectedAppellationID }

        let wine = existingBottle?.wine ?? Wine()
        if existingBottle?.wine == nil {
            context.insert(wine)
        }
        wine.name = trimmedName
        wine.color = color
        wine.type = type
        wine.region = region
        wine.appellation = appellation
        wine.grapes = selectedGrapes

        let producerName = self.producerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if producerName.isEmpty {
            wine.producer = nil
        } else if wine.producer?.name != producerName {
            wine.producer = resolveProducer(named: producerName)
        }

        let bottle = existingBottle ?? Bottle()
        if existingBottle == nil {
            context.insert(bottle)
        }
        bottle.wine = wine
        bottle.vintage = parsedVintage()
        bottle.format = format
        bottle.quantity = quantity
        bottle.purchasePrice = parsedPrice()
        bottle.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        bottle.supplier = supplier.isEmpty ? nil : supplier
        bottle.storageQuality = storageQuality
        bottle.notes = notes.isEmpty ? nil : notes
        bottle.state = state

        if state == .opened {
            bottle.openedDate = openedDate
            bottle.remainingServings = Int(remainingServingsText.trimmingCharacters(in: .whitespaces))
            bottle.conservation = conservation
        } else {
            bottle.openedDate = nil
            bottle.remainingServings = nil
            bottle.conservation = .none
        }
        bottle.updatedAt = Date()

        try? context.save()
        dismiss()
    }
}
