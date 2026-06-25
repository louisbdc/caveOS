import XCTest

/// Capture des écrans pour la fiche App Store.
/// Pilote l'app de démo (SampleData) à travers ses onglets et capture chaque écran
/// en pleine résolution. Les images sont jointes au bundle de résultats (.xcresult),
/// puis extraites côté hôte par `scripts/screenshots.sh`.
///
/// Marche sur iPhone (TabView) comme sur iPad (NavigationSplitView) : `go(_:)` essaie
/// successivement la barre d'onglets, un bouton, puis une cellule portant le libellé.
final class ScreenshotUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testCaptureAppStoreScreens() {
        // Force le portrait (le simulateur peut avoir gardé une orientation précédente).
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]

        // 1) Onboarding (premier lancement, sans contourner l'écran d'accueil).
        //    Tout est capturé en PORTRAIT (orientation attendue pour l'App Store).
        app.launch()
        sleep(2)
        shot("00-Accueil")
        app.terminate()

        // 2) Écrans principaux : on contourne l'onboarding via le domaine d'arguments
        //    (UserDefaults), ce que lit @AppStorage("caveos.hasCompletedOnboarding").
        app.launchArguments += ["-caveos.hasCompletedOnboarding", "1"]
        app.launch()
        sleep(2)
        shot("01-Cave")              // Inventaire (rubrique par défaut)

        go(app, "Caves"); sleep(1)
        shot("02-Caves")             // Plan de cave / emplacements

        go(app, "Stats"); sleep(1)
        shot("03-Stats")             // Analytics de cave

        go(app, "Accords"); sleep(1)
        shot("04-Accords")           // Accords mets-vins

        // 3) Fiche d'une bouteille (statut d'apogée). On cible un vin connu de
        //    SampleData pour ne pas taper une cellule de la barre latérale (iPad).
        go(app, "Cave"); sleep(1)
        let bottle = app.staticTexts["Ribolla Gialla"].firstMatch
        if bottle.waitForExistence(timeout: 5), bottle.isHittable {
            bottle.tap()
            sleep(1)
            shot("05-Fiche-apogee")
        }
    }

    // MARK: - Helpers

    /// Navigue vers une destination racine par son libellé, sur iPhone (barre
    /// d'onglets) ou iPad (barre latérale du NavigationSplitView). En portrait,
    /// la barre latérale iPad est repliée : on la révèle d'abord.
    private func go(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label]
        if tab.waitForExistence(timeout: 1), tab.isHittable { tab.tap(); return }

        // iPad portrait : la barre latérale est un overlay qui assombrit le détail.
        // On la révèle, on sélectionne, puis on la referme pour un détail plein écran.
        if !tapDestination(app, label) {
            revealSidebar(app)
            _ = tapDestination(app, label)
            dismissSidebarOverlay(app)
        }
    }

    /// Referme l'overlay de barre latérale (iPad portrait) en touchant le voile
    /// qui recouvre le détail, jusqu'à ce que la barre latérale (nav bar « CaveOS »)
    /// disparaisse — robuste face à l'animation. N'active aucun contenu du détail :
    /// dès que l'overlay est fermé, on cesse de toucher.
    private func dismissSidebarOverlay(_ app: XCUIApplication) {
        let sidebarBar = app.navigationBars["CaveOS"]
        for _ in 0..<4 {
            if !sidebarBar.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            usleep(700_000)
        }
    }

    /// Essaie de toucher la destination (bouton, cellule ou texte). Renvoie false
    /// si rien n'est atteignable (barre latérale repliée).
    private func tapDestination(_ app: XCUIApplication, _ label: String) -> Bool {
        let candidates: [XCUIElement] = [
            app.buttons[label],
            app.cells.containing(.staticText, identifier: label).firstMatch,
            app.staticTexts[label].firstMatch,
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: 1) && candidate.isHittable {
            candidate.tap()
            return true
        }
        return false
    }

    /// Révèle la barre latérale repliée d'un NavigationSplitView (iPad portrait) :
    /// via le bouton système « ToggleSidebar », sinon par un swipe depuis le bord gauche.
    private func revealSidebar(_ app: XCUIApplication) {
        let toggle = app.buttons["ToggleSidebar"]
        if toggle.waitForExistence(timeout: 1), toggle.isHittable {
            toggle.tap()
            usleep(600_000)
            return
        }
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: center)
        usleep(600_000)
    }

    /// Capture l'écran complet et le joint au bundle de résultats.
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
