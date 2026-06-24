import XCTest
@testable import CaveOS

/// Tests du moteur d'apogée.
///
/// Les profils de garde sont exprimés en années depuis le millésime ; la
/// fenêtre absolue dépend du millésime et des multiplicateurs région/stockage.
/// On fixe une date « maintenant » déterministe pour rendre les statuts stables.
final class ApogeeEngineTests: XCTestCase {

    /// Date de référence : 1er juillet 2026.
    private func now(year: Int = 2026) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = 7
        comps.day = 1
        return Calendar.current.date(from: comps)!
    }

    /// Construit une bouteille avec un vin, sans override (profil défaut 3/8/15),
    /// région de qualité moyenne (×1.0) et stockage bon (×0.85 par défaut).
    private func makeBottle(
        vintage: Int?,
        storage: StorageQuality = .ideal,
        tier: QualityTier = .mid,
        baseMin: Int? = nil,
        basePeak: Int? = nil,
        baseMax: Int? = nil
    ) -> Bottle {
        let region = Region(name: "Test", qualityTier: tier)
        let wine = Wine(name: "Vin Test", region: region)
        wine.baseApogeeMin = baseMin
        wine.baseApogeePeak = basePeak
        wine.baseApogeeMax = baseMax

        let bottle = Bottle(wine: wine, vintage: vintage)
        bottle.storageQuality = storage
        return bottle
    }

    // MARK: - Fenêtre de base

    func testWindowUsesDefaultProfileWithIdealStorage() {
        // Profil défaut 3/8/15, mid ×1.0, ideal ×1.0 → fenêtre = millésime + 3/8/15.
        let bottle = makeBottle(vintage: 2020, storage: .ideal, tier: .mid)
        let window = ApogeeEngine.window(for: bottle)
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.drinkFrom, 2023)
        XCTAssertEqual(window?.peak, 2028)
        XCTAssertEqual(window?.drinkBy, 2035)
    }

    // MARK: - Statuts

    func testStatusTooYoung() {
        // Millésime 2024, fenêtre 2027/2032/2039 ; en 2026 → trop jeune.
        let bottle = makeBottle(vintage: 2024, storage: .ideal, tier: .mid)
        XCTAssertEqual(ApogeeEngine.status(for: bottle, now: now()), .tooYoung)
    }

    func testStatusReady() {
        // Millésime 2021, fenêtre 2024/2029/2036 ; en 2026 → prêt (avant pic, hors ±1).
        let bottle = makeBottle(vintage: 2021, storage: .ideal, tier: .mid)
        XCTAssertEqual(ApogeeEngine.status(for: bottle, now: now()), .ready)
    }

    func testStatusPeak() {
        // Millésime 2018, fenêtre 2021/2026/2033 ; en 2026 → à l'apogée (pic exact).
        let bottle = makeBottle(vintage: 2018, storage: .ideal, tier: .mid)
        XCTAssertEqual(ApogeeEngine.status(for: bottle, now: now()), .peak)
    }

    func testStatusDrinkSoon() {
        // Millésime 2010, fenêtre 2013/2018/2025 ; en 2024 → à boire vite.
        // (hors ±1 du pic 2018, avant drinkBy 2025)
        let bottle = makeBottle(vintage: 2010, storage: .ideal, tier: .mid)
        XCTAssertEqual(ApogeeEngine.status(for: bottle, now: now(year: 2024)), .drinkSoon)
    }

    func testStatusPast() {
        // Millésime 2000, fenêtre 2003/2008/2015 ; en 2026 → passé.
        let bottle = makeBottle(vintage: 2000, storage: .ideal, tier: .mid)
        XCTAssertEqual(ApogeeEngine.status(for: bottle, now: now()), .past)
    }

    // MARK: - Sans millésime

    func testNoVintageReturnsNilAndUnknown() {
        let nilVintage = makeBottle(vintage: nil)
        XCTAssertNil(ApogeeEngine.window(for: nilVintage))
        XCTAssertEqual(ApogeeEngine.status(for: nilVintage, now: now()), .unknown)

        let zeroVintage = makeBottle(vintage: 0)
        XCTAssertNil(ApogeeEngine.window(for: zeroVintage))
        XCTAssertEqual(ApogeeEngine.status(for: zeroVintage, now: now()), .unknown)
    }

    // MARK: - Effet du stockage

    func testPoorStorageShrinksWindow() {
        // Profil 5/10/20, poor ×0.4 → 2/4/8 (arrondis) depuis le millésime.
        // 5×0.4=2, 10×0.4=4, 20×0.4=8.
        let bottle = makeBottle(
            vintage: 2020, storage: .poor, tier: .mid,
            baseMin: 5, basePeak: 10, baseMax: 20
        )
        let window = ApogeeEngine.window(for: bottle)
        XCTAssertEqual(window?.drinkFrom, 2022)
        XCTAssertEqual(window?.peak, 2024)
        XCTAssertEqual(window?.drinkBy, 2028)

        // En 2026 : >peak 2024 (hors ±1), <drinkBy 2028 → à boire vite.
        XCTAssertEqual(ApogeeEngine.status(for: bottle, now: now()), .drinkSoon)

        // Comparaison avec stockage idéal : fenêtre bien plus large.
        let ideal = makeBottle(
            vintage: 2020, storage: .ideal, tier: .mid,
            baseMin: 5, basePeak: 10, baseMax: 20
        )
        let idealWindow = ApogeeEngine.window(for: ideal)
        XCTAssertEqual(idealWindow?.drinkBy, 2040)
        XCTAssertGreaterThan(idealWindow!.drinkBy, window!.drinkBy)
    }

    // MARK: - Effet de la région

    func testPremiumTierExtendsWindow() {
        // Profil défaut 3/8/15, premium ×1.4, ideal ×1.0 → 4/11/21 (arrondis).
        let bottle = makeBottle(vintage: 2020, storage: .ideal, tier: .premium)
        let window = ApogeeEngine.window(for: bottle)
        XCTAssertEqual(window?.drinkFrom, 2024)
        XCTAssertEqual(window?.peak, 2031)
        XCTAssertEqual(window?.drinkBy, 2041)
    }

    // MARK: - Priorité des overrides

    func testBottleOverrideTakesPrecedence() {
        let bottle = makeBottle(
            vintage: 2020, storage: .ideal, tier: .mid,
            baseMin: 5, basePeak: 10, baseMax: 20
        )
        bottle.apogeeMinOverride = 1
        bottle.apogeePeakOverride = 2
        bottle.apogeeMaxOverride = 3

        // Override bouteille prioritaire : 1/2/3 depuis 2020.
        let window = ApogeeEngine.window(for: bottle)
        XCTAssertEqual(window?.drinkFrom, 2021)
        XCTAssertEqual(window?.peak, 2022)
        XCTAssertEqual(window?.drinkBy, 2023)
    }

    // MARK: - Profil dérivé des cépages

    func testGrapeAverageUsedWhenNoOverride() {
        let region = Region(name: "Test", qualityTier: .mid)
        let g1 = Grape(name: "A", apogeeMin: 2, apogeePeak: 6, apogeeMax: 10)
        let g2 = Grape(name: "B", apogeeMin: 4, apogeePeak: 10, apogeeMax: 20)
        let wine = Wine(name: "Assemblage", region: region, grapes: [g1, g2])
        // Pas de baseApogee* → moyenne des cépages : 3/8/15.
        let bottle = Bottle(wine: wine, vintage: 2020)
        bottle.storageQuality = .ideal

        let window = ApogeeEngine.window(for: bottle)
        XCTAssertEqual(window?.drinkFrom, 2023)
        XCTAssertEqual(window?.peak, 2028)
        XCTAssertEqual(window?.drinkBy, 2035)
    }
}
