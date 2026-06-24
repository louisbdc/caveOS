import SwiftUI
import SwiftData

/// Création / édition d'une cave et génération de ses emplacements.
struct CellarEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Cave existante (édition) ou nil (création).
    private let cellar: Cellar?

    @State private var name: String
    @State private var type: CellarType
    @State private var brand: String
    @State private var model: String
    @State private var rows: Int
    @State private var columns: Int
    @State private var levels: Int
    @State private var hasBackPositions: Bool

    init(cellar: Cellar? = nil) {
        self.cellar = cellar
        _name = State(initialValue: cellar?.name ?? "")
        _type = State(initialValue: cellar?.type ?? .electric)
        _brand = State(initialValue: cellar?.brand ?? "")
        _model = State(initialValue: cellar?.model ?? "")
        _rows = State(initialValue: cellar?.rows ?? 6)
        _columns = State(initialValue: cellar?.columns ?? 6)
        _levels = State(initialValue: cellar?.levels ?? 1)
        // Active par défaut si la cave existante possède déjà des positions arrière.
        _hasBackPositions = State(initialValue: cellar?.locations.contains { !$0.isFront } ?? false)
    }

    private var isEditing: Bool { cellar != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations") {
                    TextField("Nom de la cave", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(CellarType.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol)
                                .tag(kind)
                        }
                    }
                    TextField("Marque", text: $brand)
                    TextField("Modèle", text: $model)
                }

                Section {
                    Stepper("Lignes : \(rows)", value: $rows, in: 1...500)
                    Stepper("Colonnes : \(columns)", value: $columns, in: 1...500)
                    Stepper("Niveaux : \(levels)", value: $levels, in: 1...500)
                    Toggle("Positions avant / arrière", isOn: $hasBackPositions)
                } header: {
                    Text("Configuration")
                } footer: {
                    let perCell = hasBackPositions ? 2 : 1
                    Text("\(levels * columns * perCell) emplacement(s) seront générés\(hasBackPositions ? " (avant et arrière)" : ""), chacun d'une capacité de \(rows) bouteille(s).")
                }
            }
            .navigationTitle(isEditing ? "Modifier la cave" : "Nouvelle cave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cellar {
            // Édition : on met à jour les champs, sans toucher aux emplacements.
            cellar.name = trimmedName
            cellar.type = type
            cellar.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            cellar.model = trimmedModel.isEmpty ? nil : trimmedModel
            cellar.rows = rows
            cellar.columns = columns
            cellar.levels = levels
        } else {
            // Création : nouvelle cave + génération des emplacements.
            let newCellar = Cellar(
                name: trimmedName,
                type: type,
                rows: rows,
                columns: columns,
                levels: levels
            )
            newCellar.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            newCellar.model = trimmedModel.isEmpty ? nil : trimmedModel
            context.insert(newCellar)

            // Positions générées : avant uniquement, ou avant + arrière selon l'option.
            let fronts = hasBackPositions ? [true, false] : [true]
            for level in 0..<levels {
                for column in 0..<columns {
                    for isFront in fronts {
                        let suffix = hasBackPositions ? (isFront ? " Av" : " Ar") : ""
                        let location = Location(
                            kind: .shelf,
                            label: "N\(level + 1)·C\(column + 1)\(suffix)",
                            levelIndex: level,
                            column: column,
                            isFront: isFront,
                            capacity: rows,
                            cellar: newCellar
                        )
                        context.insert(location)
                    }
                }
            }
        }

        try? context.save()
        dismiss()
    }
}
