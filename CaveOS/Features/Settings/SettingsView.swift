import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Écran de réglages : statut Pro, export CSV, notifications, données et à propos.
struct SettingsView: View {

    @Environment(StoreManager.self) private var store
    @Query(sort: \Bottle.createdAt, order: .reverse) private var bottles: [Bottle]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsEnabled = false
    @State private var isRequestingAuthorization = false
    @State private var showPaywall = false
    @State private var showImporter = false
    @State private var importResult: ImportResult?
    @AppStorage(AppContainer.iCloudSyncKey) private var iCloudSyncEnabled = false
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode = AppearanceMode.system

    private let notificationService = NotificationService()

    /// Version affichée dans la section À propos.
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Fichier CSV temporaire généré à partir de l'inventaire courant.
    private var csvFile: CSVFile {
        CSVFile(content: CSVExporter.csv(from: bottles))
    }

    /// URL d'un classeur Excel temporaire généré à partir de l'inventaire courant.
    private var excelFileURL: URL? {
        guard !bottles.isEmpty else { return nil }
        return try? ExcelExporter.makeFile(from: bottles)
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                exportSection
                importSection
                notificationsSection
                iCloudSyncSection
                enrichmentSection
                hardwareSection
                toolsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Réglages")
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("OK") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Compte / Pro

    @ViewBuilder
    private var accountSection: some View {
        Section("Abonnement") {
            if store.isPro {
                Label("CaveOS Pro actif ✓", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.gold)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("Passer à CaveOS Pro", systemImage: "crown.fill")
                }
            }
        }
    }

    // MARK: - Apparence

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .tag(mode)
                }
            } label: {
                Label("Thème", systemImage: "paintbrush")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Apparence")
        } footer: {
            Text("Choisissez le thème clair, sombre, ou laissez CaveOS suivre les réglages de votre appareil.")
        }
    }

    // MARK: - Export

    @ViewBuilder
    private var exportSection: some View {
        Section {
            ShareLink(
                item: csvFile,
                preview: SharePreview("Inventaire CaveOS", image: Image(systemName: "doc.text"))
            ) {
                Label("Exporter l'inventaire (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(bottles.isEmpty)

            if let excelURL = excelFileURL {
                ShareLink(
                    item: excelURL,
                    preview: SharePreview("Inventaire CaveOS", image: Image(systemName: "tablecells"))
                ) {
                    Label("Exporter en Excel (.xls)", systemImage: "tablecells")
                }
                .disabled(bottles.isEmpty)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("\(bottles.count) bouteille(s) seront exportées. Le fichier inclut une ligne d'en-tête (Vin, Domaine, Millésime…) pour le réimporter ailleurs.")
        }
    }

    // MARK: - Import

    @ViewBuilder
    private var importSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("Importer depuis un CSV", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Importez un inventaire au format CSV (exports CaveOS, Vinotag, CellarTracker…). Seules les lignes comportant un nom de vin sont importées ; les doublons ne sont pas détectés (un nouvel import ajoute les bouteilles).")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(item: $importResult) { result in
            Alert(
                title: Text(result.isSuccess ? "Import terminé" : "Échec de l'import"),
                message: Text(result.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Alertes d'apogée", systemImage: "bell.badge")
            }
            .disabled(isRequestingAuthorization)
            .onChange(of: notificationsEnabled) { _, enabled in
                guard enabled else { return }
                requestNotificationAuthorization()
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Recevez une alerte lorsqu'une bouteille entre dans sa période d'apogée.")
        }
    }

    // MARK: - Synchronisation iCloud

    @ViewBuilder
    private var iCloudSyncSection: some View {
        Section {
            Toggle(isOn: $iCloudSyncEnabled) {
                Label("Synchronisation iCloud", systemImage: "icloud")
            }
            NavigationLink {
                SyncStatusView()
            } label: {
                Label("État de la synchronisation", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Synchronisation iCloud")
        } footer: {
            Text("Synchronisez votre cave entre vos appareils via votre iCloud privé. Un redémarrage de l'application est nécessaire pour appliquer le changement ; consultez « État de la synchronisation » pour vérifier qu'elle est active.")
        }
    }

    // MARK: - Données & enrichissement

    @ViewBuilder
    private var enrichmentSection: some View {
        Section("Données & enrichissement") {
            NavigationLink {
                EnrichmentView()
            } label: {
                Label("Enrichir les vins", systemImage: "sparkles")
            }
        }
    }

    // MARK: - Matériel

    @ViewBuilder
    private var hardwareSection: some View {
        Section("Matériel") {
            NavigationLink {
                HardwareCodesView()
            } label: {
                Label("Codes matériel", systemImage: "barcode.viewfinder")
            }
        }
    }

    // MARK: - Outils

    @ViewBuilder
    private var toolsSection: some View {
        Section("Outils") {
            NavigationLink {
                VisualMatchView()
            } label: {
                Label("Matching visuel", systemImage: "camera.viewfinder")
            }
            NavigationLink {
                ShareCellarListView()
            } label: {
                Label("Partager une cave", systemImage: "square.and.arrow.up.on.square")
            }
        }
    }

    // MARK: - Données

    @ViewBuilder
    private var dataSection: some View {
        Section("Données") {
            NavigationLink {
                CreditsView()
            } label: {
                Label("Sources & crédits", systemImage: "text.book.closed")
            }
        }
    }

    // MARK: - À propos

    @ViewBuilder
    private var aboutSection: some View {
        Section("À propos") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Application", value: "CaveOS")
        }
    }

    // MARK: - Actions

    private func requestNotificationAuthorization() {
        isRequestingAuthorization = true
        Task {
            await notificationService.requestAuthorization()
            isRequestingAuthorization = false
        }
    }

    /// Traite le résultat du sélecteur de fichier et lance l'import CSV.
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let count = try CSVImporter.importBottles(from: url, into: modelContext)
                importResult = ImportResult(
                    isSuccess: true,
                    message: "\(count) bouteille(s) importée(s) avec succès."
                )
            } catch {
                importResult = ImportResult(
                    isSuccess: false,
                    message: error.localizedDescription
                )
            }
        case .failure(let error):
            importResult = ImportResult(
                isSuccess: false,
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Résultat d'import

/// Résultat affiché à l'utilisateur après une tentative d'import CSV.
struct ImportResult: Identifiable {
    let id = UUID()
    let isSuccess: Bool
    let message: String
}

// MARK: - Fichier partageable

/// Enveloppe `Transferable` exposant le CSV comme fichier exportable via `ShareLink`.
struct CSVFile: Transferable {
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.content.utf8)
        }
        .suggestedFileName("inventaire-caveos.csv")
    }
}

// MARK: - Partage de cave

/// Liste des caves, chacune menant à l'écran de partage correspondant.
struct ShareCellarListView: View {
    @Query(sort: \Cellar.createdAt, order: .reverse) private var cellars: [Cellar]

    var body: some View {
        List {
            if cellars.isEmpty {
                ContentUnavailableView(
                    "Aucune cave",
                    systemImage: "tray",
                    description: Text("Créez une cave pour pouvoir la partager.")
                )
            } else {
                ForEach(cellars) { cellar in
                    NavigationLink {
                        ShareCellarView(cellar: cellar)
                    } label: {
                        Label(cellar.name, systemImage: cellar.type.symbol)
                    }
                }
            }
        }
        .navigationTitle("Partager une cave")
    }
}
