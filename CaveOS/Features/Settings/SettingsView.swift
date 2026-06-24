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
