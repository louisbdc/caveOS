import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Écran de réglages : statut Pro, export CSV, notifications, données et à propos.
struct SettingsView: View {

    @Environment(StoreManager.self) private var store
    @Query(sort: \Bottle.createdAt, order: .reverse) private var bottles: [Bottle]

    @State private var notificationsEnabled = false
    @State private var isRequestingAuthorization = false
    @State private var showPaywall = false
    @AppStorage(AppContainer.iCloudSyncKey) private var iCloudSyncEnabled = false

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

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                exportSection
                notificationsSection
                iCloudSyncSection
                enrichmentSection
                hardwareSection
                toolsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Réglages")
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
        } header: {
            Text("Export")
        } footer: {
            Text("\(bottles.count) bouteille(s) seront exportées au format CSV.")
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
            Text("Synchronisez votre cave entre vos appareils. Un redémarrage de l'application est nécessaire pour appliquer le changement.")
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
