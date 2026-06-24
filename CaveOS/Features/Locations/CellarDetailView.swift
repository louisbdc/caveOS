import SwiftUI
import SwiftData

/// Détail d'une cave : grille des emplacements avec drag & drop des bouteilles.
struct CellarDetailView: View {
    @Environment(\.modelContext) private var context

    let cellar: Cellar

    /// Bouteilles sans emplacement assigné (vrac).
    @Query private var unplacedBottles: [Bottle]

    @State private var isGrid = true
    @State private var showingEditor = false
    @State private var dropError: String?

    init(cellar: Cellar) {
        self.cellar = cellar
        // Bouteilles en cave sans emplacement.
        _unplacedBottles = Query(
            filter: #Predicate<Bottle> { $0.location == nil },
            sort: \Bottle.createdAt
        )
    }

    /// Niveaux triés, du plus haut index au plus bas (haut de la cave en premier).
    private var levels: [Int] {
        Array(0..<max(cellar.levels, 1)).reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(levels, id: \.self) { level in
                    levelSection(level)
                }

                bulkSection
            }
            .padding(Theme.Spacing.m)
        }
        .navigationTitle(cellar.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Emplacement plein", isPresented: .constant(dropError != nil)) {
            Button("OK") { dropError = nil }
        } message: {
            Text(dropError ?? "")
        }
        .toolbar {
            if cellar.locations.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Affichage", selection: $isGrid) {
                        Image(systemName: "square.grid.2x2").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Modifier la cave")
            }
        }
        .sheet(isPresented: $showingEditor) {
            CellarEditView(cellar: cellar)
        }
    }

    // MARK: - Sections par niveau

    @ViewBuilder
    private func levelSection(_ level: Int) -> some View {
        let cells = locations(forLevel: level)

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Niveau \(level + 1)")
                .font(.headline)
                .foregroundStyle(.secondary)

            if isGrid {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Theme.Spacing.s),
                        count: max(cellar.columns, 1)
                    ),
                    spacing: Theme.Spacing.s
                ) {
                    ForEach(cells) { location in
                        LocationCell(location: location, cellar: cellar, onDrop: handleDrop, onMove: move)
                    }
                }
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(cells) { location in
                        LocationRow(location: location, onDrop: handleDrop)
                    }
                }
            }
        }
    }

    private var bulkSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Vrac (sans emplacement)")
                .font(.headline)
                .foregroundStyle(.secondary)

            BulkDropZone(bottles: unplacedBottles) { idString in
                assign(idString: idString, to: nil)
            }
        }
    }

    // MARK: - Données

    private func locations(forLevel level: Int) -> [Location] {
        cellar.locations
            .filter { $0.levelIndex == level }
            .sorted { $0.column < $1.column }
    }

    // MARK: - Drag & drop

    private func handleDrop(idString: String, target: Location) -> Bool {
        assign(idString: idString, to: target)
    }

    @discardableResult
    private func assign(idString: String, to target: Location?) -> Bool {
        guard let uuid = UUID(uuidString: idString) else { return false }

        let descriptor = FetchDescriptor<Bottle>(
            predicate: #Predicate { $0.id == uuid }
        )
        guard let bottle = try? context.fetch(descriptor).first else { return false }

        guard hasRoom(at: target, for: bottle) else {
            dropError = "L'emplacement « \(target?.label ?? "") » est plein (capacité \(target?.capacity ?? 0))."
            return false
        }

        bottle.location = target
        bottle.updatedAt = Date()
        try? context.save()
        return true
    }

    /// Vérifie qu'un emplacement peut accueillir la bouteille sans dépasser sa capacité.
    /// Le vrac (`nil`) n'a pas de limite.
    private func hasRoom(at target: Location?, for bottle: Bottle) -> Bool {
        guard let target else { return true }
        if bottle.location?.id == target.id { return true }
        let current = target.bottles.reduce(0) { $0 + $1.quantity }
        return current + bottle.quantity <= target.capacity
    }

    /// Déplace une bouteille précise vers un emplacement (ou le vrac si nil).
    private func move(_ bottle: Bottle, to target: Location?) {
        guard hasRoom(at: target, for: bottle) else {
            dropError = "L'emplacement « \(target?.label ?? "") » est plein (capacité \(target?.capacity ?? 0))."
            return
        }
        bottle.location = target
        bottle.updatedAt = Date()
        try? context.save()
    }
}

// MARK: - Case de grille

private struct LocationCell: View {
    let location: Location
    let cellar: Cellar
    let onDrop: (String, Location) -> Bool
    let onMove: (Bottle, Location?) -> Void

    @State private var isTargeted = false
    @State private var showingContents = false

    private var count: Int {
        location.bottles.reduce(0) { $0 + $1.quantity }
    }

    private var isFull: Bool { count >= location.capacity }

    var body: some View {
        VStack(spacing: 2) {
            Text(location.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "wineglass.fill")
                .font(.caption)
                .foregroundStyle(count > 0 ? Theme.wine : Color.secondary.opacity(0.3))
            Text("\(count)/\(location.capacity)")
                .font(.caption.bold())
                .foregroundStyle(isFull ? Color(red: 0.85, green: 0.55, blue: 0.20) : .primary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(isTargeted ? Theme.gold.opacity(0.25) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .stroke(isTargeted ? Theme.gold : Color.clear, lineWidth: 2)
        )
        .draggableBottles(location.bottles)
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return onDrop(first, location)
        } isTargeted: { isTargeted = $0 }
        .onTapGesture {
            if !location.bottles.isEmpty { showingContents = true }
        }
        .sheet(isPresented: $showingContents) {
            LocationContentsSheet(location: location, cellar: cellar, onMove: onMove)
        }
    }
}

// MARK: - Contenu d'une case (déplacement par bouteille)

/// Feuille listant les bouteilles d'un emplacement, chacune déplaçable
/// vers n'importe quel autre emplacement (ou le vrac). Corrige la limite
/// du drag&drop en grille qui ne déplaçait que la première bouteille.
private struct LocationContentsSheet: View {
    let location: Location
    let cellar: Cellar
    let onMove: (Bottle, Location?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var targets: [Location] {
        cellar.locations
            .filter { $0.id != location.id }
            .sorted { ($0.levelIndex, $0.column) < ($1.levelIndex, $1.column) }
    }

    var body: some View {
        NavigationStack {
            List {
                if location.bottles.isEmpty {
                    ContentUnavailableView("Emplacement vide", systemImage: "wineglass")
                } else {
                    ForEach(location.bottles) { bottle in
                        bottleRow(bottle)
                    }
                }
            }
            .navigationTitle(location.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func bottleRow(_ bottle: Bottle) -> some View {
        let name = bottle.wine?.name ?? "Bouteille"
        let title = (bottle.vintage ?? 0) > 0 ? "\(name) \(bottle.vintage!)" : name

        HStack {
            Image(systemName: "wineglass.fill")
                .foregroundStyle(bottle.wine?.color.tint ?? Theme.wine)
            Text(title).lineLimit(1)
            Spacer()
            Menu {
                Button("Vrac (retirer)") { onMove(bottle, nil); dismiss() }
                Divider()
                ForEach(targets) { target in
                    let fill = target.bottles.reduce(0) { $0 + $1.quantity }
                    Button("Niv. \(target.levelIndex + 1) · \(target.label) (\(fill)/\(target.capacity))") {
                        onMove(bottle, target)
                        dismiss()
                    }
                }
            } label: {
                Label("Déplacer", systemImage: "arrow.left.arrow.right")
                    .labelStyle(.iconOnly)
            }
        }
    }
}

// MARK: - Ligne (vue liste)

private struct LocationRow: View {
    let location: Location
    let onDrop: (String, Location) -> Bool

    @State private var isTargeted = false

    private var count: Int {
        location.bottles.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(location.label)
                .font(.subheadline.bold())
                .frame(minWidth: 64, alignment: .leading)

            ForEach(location.bottles) { bottle in
                BottleChip(bottle: bottle)
            }

            Spacer()

            StatusBadge(text: "\(count)", color: Theme.gold, systemImage: "wineglass")
        }
        .padding(Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(isTargeted ? Theme.gold.opacity(0.25) : Color(.secondarySystemBackground))
        )
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return onDrop(first, location)
        } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Zone vrac

private struct BulkDropZone: View {
    let bottles: [Bottle]
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    private var count: Int {
        bottles.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if bottles.isEmpty {
                Text("Déposez ici une bouteille pour la retirer de son emplacement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.s)],
                    spacing: Theme.Spacing.s
                ) {
                    ForEach(bottles) { bottle in
                        BottleChip(bottle: bottle)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(isTargeted ? Theme.gold.opacity(0.25) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(isTargeted ? Theme.gold : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            onDrop(first)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Vignette de bouteille (déplaçable)

private struct BottleChip: View {
    let bottle: Bottle

    private var title: String {
        let name = bottle.wine?.name ?? "Bouteille"
        if let vintage = bottle.vintage, vintage > 0 {
            return "\(name) \(vintage)"
        }
        return name
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wineglass.fill")
                .font(.caption2)
                .foregroundStyle(bottle.wine?.color.tint ?? Theme.wine)
            Text(title)
                .font(.caption)
                .lineLimit(1)
            if bottle.quantity > 1 {
                Text("×\(bottle.quantity)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill(Color(.tertiarySystemBackground))
        )
        .draggable(bottle.id.uuidString)
    }
}

// MARK: - Helper drag pour une case (première bouteille déplaçable)

private extension View {
    /// Rend la case déplaçable via l'id de sa première bouteille (s'il y en a une).
    @ViewBuilder
    func draggableBottles(_ bottles: [Bottle]) -> some View {
        if let first = bottles.first {
            self.draggable(first.id.uuidString)
        } else {
            self
        }
    }
}
