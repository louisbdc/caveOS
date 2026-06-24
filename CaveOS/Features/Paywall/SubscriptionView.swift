import SwiftUI

/// Abonnement CaveOS Pro via le web (Stripe), en complément des achats in-app (StoreKit).
/// Honnêteté: le paiement se fait sur une page Stripe sécurisée hors de l'app.
struct SubscriptionView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var checkout: IdentifiableURL?
    @State private var isLoading = false
    @State private var errorText: String?

    private let advantages = [
        ("infinity", "Scan d'étiquette illimité"),
        ("icloud", "Synchronisation iCloud multi-appareils"),
        ("chart.pie", "Analytics de cave"),
        ("wineglass", "Carnet de dégustation avancé")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    header
                    advantagesCard
                    actions
                    disclaimer
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("CaveOS Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $checkout, onDismiss: { Task { await pollAfterCheckout() } }) { item in
                SafariView(url: item.url)
            }
            .task { await refreshStatus() }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: store.isPro ? "checkmark.seal.fill" : "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.gold)
            Text(store.isPro ? "Abonnement actif" : "4,99 € / an")
                .font(.title2.bold())
            if !store.isPro {
                Text("Sans engagement, résiliable à tout moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.m)
    }

    private var advantagesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(advantages, id: \.1) { symbol, label in
                Label(label, systemImage: symbol)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var actions: some View {
        if store.isPro {
            Button {
                Task { await openPortal() }
            } label: {
                Label("Gérer mon abonnement", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                Task { await subscribe() }
            } label: {
                Group {
                    if isLoading { ProgressView() } else { Text("S'abonner") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.wine)
            .disabled(isLoading)
        }

        Button("Vérifier mon abonnement") {
            Task { await refreshStatus() }
        }
        .font(.footnote)

        if let errorText {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var disclaimer: some View {
        Text("Le paiement est traité de manière sécurisée par Stripe sur une page web. Vous pouvez aussi débloquer CaveOS Pro via un achat App Store depuis l'écran précédent.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func subscribe() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let url = try await BillingService.startCheckout()
            checkout = IdentifiableURL(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func openPortal() async {
        do {
            let url = try await BillingService.openPortal()
            checkout = IdentifiableURL(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refreshStatus() async {
        let active = await BillingService.status()
        store.setWebSubscription(active: active)
    }

    /// Après le retour du Checkout, le webhook peut prendre un court instant :
    /// on interroge le statut plusieurs fois.
    private func pollAfterCheckout() async {
        for _ in 0..<5 {
            let active = await BillingService.status()
            if active {
                store.setWebSubscription(active: true)
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        await refreshStatus()
    }
}
