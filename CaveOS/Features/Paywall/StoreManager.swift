import Foundation
import StoreKit

/// Gère le freemium (scans gratuits limités) et l'achat Pro via StoreKit 2.
/// Achat unique « à vie » + abonnement annuel. Restauration via AppStore.sync().
@MainActor
@Observable
final class StoreManager {

    // MARK: - Identifiants produits

    static let lifetimeProductID = "com.louisbdc.caveos.pro.lifetime"
    static let subscriptionProductID = "com.louisbdc.caveos.pro.yearly"

    /// Limite de scans gratuits avant invitation à passer Pro.
    static let freeScanLimit = 25

    private static let freeScansKey = "caveos.freeScansRemaining"
    private static let webSubKey = "caveos.webSubscriptionActive"

    // MARK: - État publié

    /// L'utilisateur a-t-il débloqué les fonctionnalités Pro ?
    var isPro: Bool = false

    /// Nombre de scans gratuits restants (persisté via UserDefaults).
    var freeScansRemaining: Int {
        didSet {
            UserDefaults.standard.set(freeScansRemaining, forKey: Self.freeScansKey)
        }
    }

    /// Produit non-consommable « à vie » chargé depuis l'App Store.
    var lifetimeProduct: Product?

    /// Produit d'abonnement annuel chargé depuis l'App Store.
    var subscriptionProduct: Product?

    /// Dernière erreur d'achat lisible par l'utilisateur (nil si aucune).
    var purchaseError: String?

    /// Abonnement Pro souscrit via le web (Stripe), persisté localement.
    var webSubscriptionActive: Bool = UserDefaults.standard.bool(forKey: StoreManager.webSubKey) {
        didSet { UserDefaults.standard.set(webSubscriptionActive, forKey: Self.webSubKey) }
    }

    // MARK: - Privé

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.freeScansKey) == nil {
            // Première installation : on initialise au quota par défaut.
            defaults.set(Self.freeScanLimit, forKey: Self.freeScansKey)
            self.freeScansRemaining = Self.freeScanLimit
        } else {
            self.freeScansRemaining = defaults.integer(forKey: Self.freeScansKey)
        }
    }

    // MARK: - Observation des transactions

    /// Démarre l'écoute des mises à jour de transactions et synchronise les droits.
    func startObserving() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            // Vérifie l'état initial dès le lancement.
            await self?.updateProEntitlement()
            // Puis réagit aux transactions futures (achats hors session, renouvellements…).
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.updateProEntitlement()
            }
        }
    }

    /// Parcourt les droits actifs et met à jour `isPro`.
    func updateProEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                if transaction.productID == Self.lifetimeProductID
                    || transaction.productID == Self.subscriptionProductID {
                    entitled = true
                }
            }
        }
        isPro = entitled || webSubscriptionActive
    }

    /// Applique le droit Pro issu d'un abonnement web (Stripe).
    func setWebSubscription(active: Bool) {
        webSubscriptionActive = active
        Task { await updateProEntitlement() }
    }

    // MARK: - Chargement des produits

    /// Charge les métadonnées (prix, libellés) des produits depuis l'App Store.
    func loadProducts() async {
        do {
            let products = try await Product.products(
                for: [Self.lifetimeProductID, Self.subscriptionProductID]
            )
            for product in products {
                switch product.id {
                case Self.lifetimeProductID:
                    lifetimeProduct = product
                case Self.subscriptionProductID:
                    subscriptionProduct = product
                default:
                    break
                }
            }
        } catch {
            purchaseError = "Impossible de charger les offres. Vérifiez votre connexion."
        }
    }

    // MARK: - Achats

    /// Achat unique « à vie » (non-consommable).
    func purchaseLifetime() async throws {
        guard let product = lifetimeProduct else {
            throw StoreError.productUnavailable
        }
        try await purchase(product)
    }

    /// Abonnement annuel.
    func purchaseSubscription() async throws {
        guard let product = subscriptionProduct else {
            throw StoreError.productUnavailable
        }
        try await purchase(product)
    }

    private func purchase(_ product: Product) async throws {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw StoreError.unverified
                }
                await transaction.finish()
                isPro = true
                await updateProEntitlement()
            case .userCancelled:
                // Annulation volontaire : silencieux, pas une erreur.
                break
            case .pending:
                purchaseError = "Achat en attente de validation (Demander à acheter)."
            @unknown default:
                break
            }
        } catch let error as StoreError {
            purchaseError = error.message
            throw error
        } catch {
            purchaseError = "L'achat a échoué. Veuillez réessayer."
            throw error
        }
    }

    /// Restaure les achats précédents via la synchronisation App Store.
    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await updateProEntitlement()
            if !isPro {
                purchaseError = "Aucun achat à restaurer pour ce compte."
            }
        } catch {
            purchaseError = "La restauration a échoué. Veuillez réessayer."
        }
    }

    // MARK: - Quota de scans

    /// L'utilisateur peut-il lancer un scan ?
    func canUseScan() -> Bool {
        isPro || freeScansRemaining > 0
    }

    /// Consomme un scan gratuit si l'utilisateur n'est pas Pro.
    func consumeFreeScan() {
        guard !isPro else { return }
        if freeScansRemaining > 0 {
            freeScansRemaining -= 1
        }
    }

    // MARK: - Erreurs

    enum StoreError: Error {
        case productUnavailable
        case unverified

        var message: String {
            switch self {
            case .productUnavailable:
                return "Cette offre n'est pas disponible pour le moment."
            case .unverified:
                return "La transaction n'a pas pu être vérifiée."
            }
        }
    }
}
