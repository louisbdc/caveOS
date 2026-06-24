import SwiftUI
import SwiftData

/// Aperçu et partage **en lecture seule** du contenu d'une cave.
///
/// Présente un récapitulatif (nombre de bouteilles, références) puis propose un
/// partage via `ShareLink` (texte + CSV) construit par `ShareCellarService`.
struct ShareCellarView: View {
    let cellar: Cellar

    private let service = ShareCellarService()

    @State private var shareText: String = ""
    @State private var shareItems: [Any] = []
    @State private var canCloudShare = false

    init(cellar: Cellar) {
        self.cellar = cellar
    }

    // MARK: - Données dérivées

    private var bottles: [Bottle] {
        cellar.locations.flatMap { $0.bottles }
    }

    private var totalBottles: Int {
        bottles.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                summaryCard
                previewCard
                shareSection
            }
            .padding(Theme.Spacing.m)
        }
        .navigationTitle("Partager la cave")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            shareText = service.makeShareText(for: cellar)
            shareItems = service.makeShareItems(for: cellar)
            canCloudShare = await service.canUseCloudShare()
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: cellar.type.symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.wine)
                Text(cellar.name)
                    .font(.title2.bold())
            }
            StatusBadge(
                text: "Partage en lecture",
                color: Theme.gold,
                systemImage: "eye"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Récap

    private var summaryCard: some View {
        HStack(spacing: Theme.Spacing.l) {
            metric(value: "\(totalBottles)", label: "Bouteilles")
            metric(value: "\(bottles.count)", label: "Références")
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.m)
        .cardStyle()
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title.bold())
                .foregroundStyle(Theme.wine)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Aperçu

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Aperçu du partage")
                .font(.headline)

            if shareText.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text(shareText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.m)
        .cardStyle()
    }

    // MARK: - Partage

    @ViewBuilder
    private var shareSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !shareText.isEmpty {
                ShareLink(
                    item: shareText,
                    subject: Text("Cave « \(cellar.name) »"),
                    message: Text("Partage en lecture seule de ma cave."),
                    preview: SharePreview("Cave « \(cellar.name) »")
                ) {
                    Label("Partager (texte)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.s)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.wine)
            }

            Button {
                presentActivitySheet()
            } label: {
                Label("Partager (texte + CSV)", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.s)
            }
            .buttonStyle(.bordered)
            .disabled(shareItems.isEmpty)

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerText: String {
        if canCloudShare {
            return "Partage en lecture seule. iCloud disponible : le destinataire reçoit un instantané de la cave."
        }
        return "Partage en lecture seule via texte et fichier CSV. iCloud indisponible : seul l'instantané est partagé."
    }

    // MARK: - UIActivity (fallback robuste)

    private func presentActivitySheet() {
        guard !shareItems.isEmpty else { return }

        let activity = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )

        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        // iPad : ancrage du popover.
        activity.popoverPresentationController?.sourceView = presenter.view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )
        activity.popoverPresentationController?.permittedArrowDirections = []

        presenter.present(activity, animated: true)
    }
}
