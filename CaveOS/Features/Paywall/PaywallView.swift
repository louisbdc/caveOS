import SwiftUI
import StoreKit

/// Écran d'achat Pro. Transparent et honnête : on affiche clairement
/// les avantages, les prix réels et un bouton de restauration.
struct PaywallView: View {

    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var checkout: IdentifiableURL?
    @State private var billingError: String?
    @State private var purchaseSucceeded = false
    @State private var isVerifying = false

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
                if isVerifying {
                    verificationOverlay
                }
                if purchaseSucceeded {
                    successOverlay
                }
            }
            .sheet(item: $checkout, onDismiss: { Task { await pollAfterCheckout() } }) { item in
                SafariView(url: item.url)
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
                Task { await startStripe(kind: "lifetime") }
            } label: {
                purchaseLabel(title: "Débloquer à vie", subtitle: lifetimePrice)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.wine)
            .disabled(isPurchasing)

            Button {
                Task { await startStripe(kind: "subscription") }
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
                    if let active = await BillingService.status() {
                        store.setWebSubscription(active: active)
                    }
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

            if let billingError {
                Text(billingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Paiement via Stripe

    private func startStripe(kind: String) async {
        isPurchasing = true
        billingError = nil
        defer { isPurchasing = false }
        do {
            let url = try await BillingService.startCheckout(kind: kind)
            checkout = IdentifiableURL(url: url)
        } catch {
            billingError = error.localizedDescription
        }
    }

    /// Après le retour du Checkout, le webhook peut tarder un peu : on interroge le statut.
    private func pollAfterCheckout() async {
        isVerifying = true
        defer { isVerifying = false }
        for _ in 0..<6 {
            if await BillingService.status() == true {
                store.setWebSubscription(active: true)
                await celebrateAndDismiss()
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        billingError = "Paiement non confirmé pour l'instant. S'il a abouti, le déblocage apparaîtra dans un instant ; sinon réessayez."
    }

    /// Affiche brièvement la confirmation de déblocage avant de fermer.
    private func celebrateAndDismiss() async {
        withAnimation { purchaseSucceeded = true }
        try? await Task.sleep(for: .seconds(1.4))
        dismiss()
    }

    private var verificationOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("Vérification du paiement…")
                    .font(.subheadline)
            }
            .padding(Theme.Spacing.l)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
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
