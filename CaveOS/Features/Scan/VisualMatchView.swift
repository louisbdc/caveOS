import SwiftUI
import SwiftData
import PhotosUI

/// Recherche d'une bouteille par comparaison visuelle d'étiquette, on-device.
///
/// L'utilisateur choisit une photo d'étiquette ; on la compare aux photos
/// d'étiquettes déjà enregistrées dans sa cave et on propose les plus proches.
struct VisualMatchView: View {
    @Query private var bottles: [Bottle]

    @State private var selectedItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var matches: [VisualMatchService.VisualMatch] = []
    @State private var isAnalyzing = false
    @State private var didSearch = false

    /// Bouteilles disposant d'une photo d'étiquette exploitable.
    private var bottlesWithPhoto: [Bottle] {
        bottles.filter { $0.labelPhotoData != nil }
    }

    var body: some View {
        List {
            explanationSection
            pickerSection

            if isAnalyzing {
                Section {
                    HStack {
                        ProgressView()
                        Text("Analyse en cours…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if didSearch {
                resultsSection
            }
        }
        .navigationTitle("Match visuel")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItem) { _, newValue in
            Task { await loadAndMatch(newValue) }
        }
    }

    // MARK: - Sections

    private var explanationSection: some View {
        Section {
            Label {
                Text("Comparaison visuelle locale, sur l'appareil. CaveOS compare la photo choisie aux étiquettes déjà enregistrées dans votre cave — il ne s'agit pas d'une base de données mondiale de vins.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    @ViewBuilder
    private var pickerSection: some View {
        Section {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(pickedImageData == nil ? "Choisir une photo d'étiquette" : "Choisir une autre photo",
                      systemImage: "photo.on.rectangle.angled")
            }

            if let data = pickedImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if bottlesWithPhoto.isEmpty {
            Section {
                ContentUnavailableView(
                    "Aucune étiquette enregistrée",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Ajoutez des photos d'étiquettes à vos bouteilles pour pouvoir les retrouver visuellement.")
                )
            }
        } else if matches.isEmpty {
            Section {
                ContentUnavailableView(
                    "Aucune correspondance",
                    systemImage: "magnifyingglass",
                    description: Text("Aucune bouteille n'a pu être comparée à cette photo.")
                )
            }
        } else {
            Section("Bouteilles les plus proches") {
                ForEach(matches) { match in
                    matchRow(match)
                }
            }
        }
    }

    private func matchRow(_ match: VisualMatchService.VisualMatch) -> some View {
        let bottle = match.bottle
        let name = bottle.wine?.name ?? "Vin sans nom"
        let producer = bottle.wine?.producer?.name
        let vintage = bottle.vintage.map(String.init) ?? "Sans millésime"

        return HStack(spacing: Theme.Spacing.m) {
            if let data = bottle.labelPhotoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                if let producer {
                    Text(producer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(vintage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(text: similarityLabel(for: match.distance),
                        color: similarityColor(for: match.distance))
        }
    }

    // MARK: - Matching

    @MainActor
    private func loadAndMatch(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isAnalyzing = true
        didSearch = false
        matches = []

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            pickedImageData = nil
            isAnalyzing = false
            didSearch = true
            return
        }

        pickedImageData = data
        matches = VisualMatchService.bestMatches(for: data, among: bottlesWithPhoto)
        isAnalyzing = false
        didSearch = true
    }

    // MARK: - Présentation de la similarité

    /// La distance Vision est plus petite quand les images sont proches.
    private func similarityLabel(for distance: Float) -> String {
        switch distance {
        case ..<0.7: return "Très proche"
        case ..<1.1: return "Proche"
        default: return "Possible"
        }
    }

    private func similarityColor(for distance: Float) -> Color {
        switch distance {
        case ..<0.7: return .green
        case ..<1.1: return Theme.gold
        default: return .secondary
        }
    }
}
