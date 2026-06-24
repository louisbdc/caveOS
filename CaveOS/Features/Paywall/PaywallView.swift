import SwiftUI
import StoreKit

/// Écran d'achat Pro. Transparent et honnête : on affiche clairement
/// les avantages, les prix réels et un bouton de restauration.
struct PaywallView: View {

    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

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
            .background(Theme.cream)
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
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                Task { await runPurchase { try await store.purchaseLifetime() } }
            } label: {
                purchaseLabel(
                    title: "Débloquer à vie",
                    subtitle: lifetimeProductAvailable ? lifetimePrice : "Achat unique"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.wine)
            .disabled(isPurchasing)

            Button {
                Task { await runPurchase { try await store.purchaseSubscription() } }
            } label: {
                purchaseLabel(
                    title: "Abonnement annuel",
                    subtitle: subscriptionProductAvailable ? subscriptionPrice : "Renouvelable chaque année"
                )
            }
            .buttonStyle(.bordered)
            .tint(Theme.wine)
            .disabled(isPurchasing)

            Button("Restaurer mes achats") {
                Task {
                    isPurchasing = true
                    await store.restore()
                    isPurchasing = false
                    if store.isPro { dismiss() }
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

    private func purchaseLabel(title: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var legal: some View {
        Text("Sans publicité, sans revente de vos données. L'abonnement se renouvelle automatiquement sauf annulation au moins 24 h avant la fin de la période. L'achat à vie est un paiement unique.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.Spacing.s)
    }

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

    private var lifetimeProductAvailable: Bool { store.lifetimeProduct != nil }
    private var subscriptionProductAvailable: Bool { store.subscriptionProduct != nil }

    private var lifetimePrice: String {
        store.lifetimeProduct?.displayPrice ?? "Achat unique"
    }

    private var subscriptionPrice: String {
        if let price = store.subscriptionProduct?.displayPrice {
            return "\(price) / an"
        }
        return "—"
    }

    // MARK: - Achat

    private func runPurchase(_ operation: @escaping () async throws -> Void) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await operation()
            if store.isPro { dismiss() }
        } catch {
            // L'erreur lisible est déjà publiée dans store.purchaseError.
        }
    }
}

#Preview {
    PaywallView()
        .environment(StoreManager())
}
