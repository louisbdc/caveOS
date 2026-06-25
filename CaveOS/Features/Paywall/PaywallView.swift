import SwiftUI
import StoreKit

/// Écran d'achat Pro. Transparent et honnête : on affiche clairement
/// les avantages, les prix réels et un bouton de restauration.
struct PaywallView: View {

    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var purchaseSucceeded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    header
                    benefits
                    pricing
                    actions
                    legal
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.surface)
            .navigationTitle("CaveOS Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                await store.loadProducts()
            }
            .overlay(alignment: .bottom) {
                if let error = store.purchaseError {
                    errorBanner(error)
                }
            }
            .overlay {
                if purchaseSucceeded {
                    successOverlay
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.wine)
            Text("Passez à CaveOS Pro")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Tout le potentiel de votre cave, sans abonnement obligatoire.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.m)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            benefitRow(
                icon: "doc.text.viewfinder",
                title: "Scan illimité",
                detail: "Numérisez autant d'étiquettes que vous voulez."
            )
            benefitRow(
                icon: "icloud.fill",
                title: "Sync iCloud (v2)",
                detail: "Votre cave synchronisée sur tous vos appareils."
            )
            benefitRow(
                icon: "chart.bar.fill",
                title: "Analytics avancées",
                detail: "Valeur, apogée, répartition : pilotez votre cave."
            )
            benefitRow(
                icon: "list.star",
                title: "Dégustation avancée",
                detail: "Fiches détaillées, scores et accords mets-vins."
            )
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pricing: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text("Achat unique « à vie »")
                    .font(.subheadline)
                Spacer()
                Text(lifetimePrice)
                    .font(.headline)
                    .foregroundStyle(Theme.wine)
            }
            Divider()
            HStack {
                Text("Abonnement annuel")
                    .font(.subheadline)
                Spacer()
                Text(subscriptionPrice)
                    .font(.headline)
                    .foregroundStyle(Theme.wine)
            }
            Text("L'achat à vie devient plus avantageux si vous gardez l'app plus de 2 ans.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                Task { await buy { try await store.purchaseLifetime() } }
            } label: {
                purchaseLabel(title: "Débloquer à vie", subtitle: lifetimePrice)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.wine)
            .disabled(isPurchasing)

            Button {
                Task { await buy { try await store.purchaseSubscription() } }
            } label: {
                purchaseLabel(title: "Abonnement annuel", subtitle: subscriptionPrice)
            }
            .buttonStyle(.bordered)
            .tint(Theme.wine)
            .disabled(isPurchasing)

            Button("Restaurer mes achats") {
                Task {
                    isPurchasing = true
                    await store.restore()
                    isPurchasing = false
                    if store.isPro { await celebrateAndDismiss() }
                }
            }
            .font(.footnote)
            .disabled(isPurchasing)

            if isPurchasing {
                ProgressView()
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Achat via StoreKit

    /// Lance un achat StoreKit puis ferme l'écran si l'utilisateur est devenu Pro.
    /// Les erreurs éventuelles sont exposées à l'utilisateur via `store.purchaseError`.
    private func buy(_ purchase: () async throws -> Void) async {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await purchase()
        if store.isPro { await celebrateAndDismiss() }
    }

    /// Affiche brièvement la confirmation de déblocage avant de fermer.
    private func celebrateAndDismiss() async {
        withAnimation { purchaseSucceeded = true }
        try? await Task.sleep(for: .seconds(1.4))
        dismiss()
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.gold)
                Text("CaveOS Pro débloqué ✓")
                    .font(.headline)
            }
            .padding(Theme.Spacing.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func purchaseLabel(title: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var legal: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Sans publicité, sans revente de vos données. L'abonnement annuel se renouvelle automatiquement sauf annulation au moins 24 h avant la fin de la période, depuis les réglages de votre compte Apple. L'achat à vie est un paiement unique.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Liens requis pour les abonnements auto-renouvelables (Guideline 3.1.2).
            HStack(spacing: Theme.Spacing.m) {
                Link("Conditions d'utilisation", destination: Self.termsURL)
                Text("·").foregroundStyle(.secondary)
                Link("Confidentialité", destination: Self.privacyURL)
            }
            .font(.caption2)
            .tint(Theme.wine)
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// EULA standard Apple (l'app ne fournit pas ses propres conditions).
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Politique de confidentialité servie par le serveur CaveOS.
    private static let privacyURL = URL(string: "https://caveos.152.228.136.49.sslip.io/privacy")!

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity)
            .background(Theme.wineDark, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .padding(Theme.Spacing.m)
    }

    // MARK: - Helpers prix

    /// Prix « à vie » réel issu de l'App Store (locale + devise), repli si non chargé.
    private var lifetimePrice: String {
        store.lifetimeProduct?.displayPrice ?? "50 €"
    }

    /// Prix de l'abonnement annuel réel issu de l'App Store, repli si non chargé.
    private var subscriptionPrice: String {
        guard let displayPrice = store.subscriptionProduct?.displayPrice else {
            return "30 € / an"
        }
        return "\(displayPrice) / an"
    }

}

#Preview {
    PaywallView()
        .environment(StoreManager())
}
