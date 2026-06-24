import SwiftUI

/// Affiche l'état de la synchronisation iCloud et rappelle le modèle offline-first.
struct SyncStatusView: View {
    @State private var monitor = SyncMonitor()

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.m) {
                    statusIcon
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(monitor.lastEventDescription)
                            .font(.headline)
                        Text(monitor.isSyncing ? "Échange en cours avec iCloud…" : "Aucune opération en cours")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if monitor.isSyncing {
                        ProgressView()
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)

                if let error = monitor.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("État de la synchronisation")
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label("Offline-first", systemImage: "internaldrive")
                        .font(.headline)
                    Text("La cave locale est la source de vérité. CaveOS fonctionne entièrement hors-ligne : vos bouteilles, dégustations et emplacements sont toujours disponibles sur cet appareil.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("iCloud sert uniquement de miroir pour partager vos données entre vos appareils. La synchronisation se fait automatiquement en arrière-plan dès qu'une connexion est disponible.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            } header: {
                Text("Comment ça marche")
            }
        }
        .navigationTitle("Synchronisation iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { monitor.start() }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if monitor.lastError != nil {
            Image(systemName: "icloud.slash.fill")
                .font(.title2)
                .foregroundStyle(.red)
        } else if monitor.isSyncing {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.title2)
                .foregroundStyle(Theme.gold)
        } else {
            Image(systemName: "checkmark.icloud.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    NavigationStack {
        SyncStatusView()
    }
}
