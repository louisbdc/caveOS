import XCTest
@testable import CaveOS

/// Tests de la logique freemium de `StoreManager` (quota de scans gratuits et
/// bypass Pro). Chaque test utilise un `UserDefaults` isolé pour ne pas toucher
/// l'état réel de l'app.
@MainActor
final class StoreManagerTests: XCTestCase {

    /// Crée un `UserDefaults` vierge, propre à un test.
    private func freshDefaults(
        function: String = #function
    ) -> UserDefaults {
        let suiteName = "test.caveos.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Initialisation du quota

    func testFirstLaunchSeedsFreeScanLimit() {
        let store = StoreManager(defaults: freshDefaults())
        XCTAssertEqual(store.freeScansRemaining, StoreManager.freeScanLimit)
        XCTAssertTrue(store.canUseScan())
    }

    func testQuotaIsPersistedAcrossInstances() {
        let defaults = freshDefaults()

        let first = StoreManager(defaults: defaults)
        first.consumeFreeScan()
        let remaining = first.freeScansRemaining

        // Une nouvelle instance sur le même stockage retrouve le quota décrémenté.
        let second = StoreManager(defaults: defaults)
        XCTAssertEqual(second.freeScansRemaining, remaining)
        XCTAssertEqual(second.freeScansRemaining, StoreManager.freeScanLimit - 1)
    }

    // MARK: - Consommation

    func testConsumeDecrementsWhenNotPro() {
        let store = StoreManager(defaults: freshDefaults())
        store.consumeFreeScan()
        XCTAssertEqual(store.freeScansRemaining, StoreManager.freeScanLimit - 1)
    }

    func testConsumeStopsAtZeroAndBlocksScan() {
        let store = StoreManager(defaults: freshDefaults())
        for _ in 0..<StoreManager.freeScanLimit {
            store.consumeFreeScan()
        }
        XCTAssertEqual(store.freeScansRemaining, 0)
        XCTAssertFalse(store.canUseScan())

        // Au-delà de zéro, on ne descend pas dans le négatif.
        store.consumeFreeScan()
        XCTAssertEqual(store.freeScansRemaining, 0)
    }

    // MARK: - Bypass Pro

    func testProBypassesQuota() {
        let store = StoreManager(defaults: freshDefaults())
        for _ in 0..<StoreManager.freeScanLimit {
            store.consumeFreeScan()
        }
        XCTAssertFalse(store.canUseScan())

        store.isPro = true
        XCTAssertTrue(store.canUseScan(), "Un utilisateur Pro peut scanner même à quota épuisé.")
    }

    func testProDoesNotConsumeFreeScans() {
        let store = StoreManager(defaults: freshDefaults())
        store.isPro = true
        store.consumeFreeScan()
        XCTAssertEqual(store.freeScansRemaining, StoreManager.freeScanLimit,
                       "Un achat Pro ne doit pas entamer le quota gratuit.")
    }
}
