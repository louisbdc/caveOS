import Foundation
import UserNotifications

/// Service de notifications locales : alertes d'apogée et rappels de bouteilles ouvertes.
@MainActor
@Observable
final class NotificationService {

    private let center = UNUserNotificationCenter.current()

    /// Statut d'autorisation iOS actuel (pour refléter l'état réel dans l'UI).
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Demande l'autorisation d'envoyer des notifications (alerte, badge, son).
    /// Retourne le statut résultant.
    @discardableResult
    func requestAuthorizationResult() async -> UNAuthorizationStatus {
        await requestAuthorization()
        return await authorizationStatus()
    }

    /// Demande l'autorisation d'envoyer des notifications (alerte, badge, son).
    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Échec de la demande d'autorisation de notifications : \(error)")
        }
    }

    /// Identifiant unique d'une alerte d'apogée pour une bouteille.
    private func apogeeIdentifier(for bottle: Bottle) -> String {
        "apogee-\(bottle.id.uuidString)"
    }

    /// Identifiant unique d'un rappel de bouteille ouverte.
    private func openedIdentifier(for bottle: Bottle) -> String {
        "opened-\(bottle.id.uuidString)"
    }

    /// Identifiant unique d'une alerte « à boire vite » pour une bouteille.
    private func drinkSoonIdentifier(for bottle: Bottle) -> String {
        "drinksoon-\(bottle.id.uuidString)"
    }

    /// Identifiant d'une alerte de stock bas pour un vin.
    private func lowStockIdentifier(for wine: Wine) -> String {
        "lowstock-\(wine.id.uuidString)"
    }

    /// Planifie une alerte à l'entrée d'apogée (1er janvier de l'année `drinkFrom`).
    func scheduleApogeeAlert(for bottle: Bottle) {
        guard let window = ApogeeEngine.window(for: bottle, now: Date()) else { return }

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = window.drinkFrom
        components.month = 1
        components.day = 1
        components.hour = 9
        components.minute = 0

        // Ne planifie pas si la date est déjà passée.
        guard let triggerDate = calendar.date(from: components),
              triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Apogée atteinte"
        let wineName = bottle.wine?.name ?? "Votre vin"
        content.body = "\(wineName) entre dans sa période d'apogée. C'est le moment idéal pour le déguster."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: apogeeIdentifier(for: bottle),
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("Échec de la planification de l'alerte d'apogée : \(error)")
            }
        }
    }

    /// Planifie un rappel `afterDays` jours après l'ouverture d'une bouteille.
    func scheduleOpenedReminder(for bottle: Bottle, afterDays: Int) {
        let baseDate = bottle.openedDate ?? Date()
        guard let triggerDate = Calendar.current.date(
            byAdding: .day,
            value: afterDays,
            to: baseDate
        ), triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Bouteille ouverte"
        let wineName = bottle.wine?.name ?? "Votre vin"
        content.body = "\(wineName) est ouvert depuis \(afterDays) jour(s). Pensez à le terminer pour profiter au mieux de ses arômes."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: openedIdentifier(for: bottle),
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("Échec de la planification du rappel d'ouverture : \(error)")
            }
        }
    }

    /// Planifie une alerte « à boire vite » ~1 an avant la fin de la fenêtre de garde.
    func scheduleDrinkSoonAlert(for bottle: Bottle) {
        guard let window = ApogeeEngine.window(for: bottle, now: Date()) else { return }

        // ~1 an avant la date limite de consommation (1er janvier).
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = window.drinkBy - 1
        components.month = 1
        components.day = 1
        components.hour = 9
        components.minute = 0

        // Ne planifie pas si la date est déjà passée.
        guard let triggerDate = calendar.date(from: components),
              triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "À boire bientôt"
        let wineName = bottle.wine?.name ?? "Votre vin"
        content.body = "\(wineName) approche de la fin de sa période de garde. Pensez à le déguster avant qu'il ne décline."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: drinkSoonIdentifier(for: bottle),
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("Échec de la planification de l'alerte « à boire vite » : \(error)")
            }
        }
    }

    /// (Ré)planifie l'ensemble des alertes liées à une bouteille.
    ///
    /// Demande l'autorisation si nécessaire, annule les anciennes notifications
    /// pour éviter les doublons, puis replanifie : entrée en apogée, « à boire vite »
    /// et, si la bouteille est entamée, un rappel après 7 jours.
    func syncAlerts(for bottle: Bottle) async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            await requestAuthorization()
        }

        // Évite les doublons en repartant d'un état propre.
        cancelAll(for: bottle)

        // Une bouteille consommée n'a plus d'alerte à recevoir.
        guard bottle.state != .consumed else { return }

        scheduleApogeeAlert(for: bottle)
        scheduleDrinkSoonAlert(for: bottle)

        if bottle.state == .opened {
            scheduleOpenedReminder(for: bottle, afterDays: 7)
        }
    }

    /// Annule toutes les notifications en attente liées à une bouteille
    /// (apogée, « à boire vite » et rappel d'ouverture).
    func cancelAll(for bottle: Bottle) {
        center.removePendingNotificationRequests(withIdentifiers: [
            apogeeIdentifier(for: bottle),
            drinkSoonIdentifier(for: bottle),
            openedIdentifier(for: bottle)
        ])
    }

    /// Annule toutes les notifications planifiées pour une bouteille.
    func cancel(for bottle: Bottle) {
        cancelAll(for: bottle)
    }

    /// Notifie immédiatement si le stock d'un vin favori passe sous son seuil.
    func checkLowStock(for wine: Wine) {
        guard wine.isFavorite, let threshold = wine.lowStockThreshold else { return }

        let totalQuantity = wine.bottles
            .filter { $0.state != .consumed }
            .reduce(0) { $0 + $1.quantity }

        guard totalQuantity <= threshold else { return }

        let content = UNMutableNotificationContent()
        content.title = "Stock bas"
        content.body = "\(wine.name) : il ne reste que \(totalQuantity) bouteille(s). Pensez à vous réapprovisionner."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: lowStockIdentifier(for: wine),
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("Échec de la notification de stock bas : \(error)")
            }
        }
    }

    /// Notifie immédiatement si la température d'une cave sort de la plage `[low, high]`.
    func temperatureAlert(cellarName: String, celsius: Double, low: Double, high: Double) {
        guard celsius < low || celsius > high else { return }

        let content = UNMutableNotificationContent()
        content.title = "Température anormale"
        let formatted = String(format: "%.1f", celsius)
        content.body = "La cave « \(cellarName) » est à \(formatted) °C, hors de la plage recommandée (\(String(format: "%.0f", low))–\(String(format: "%.0f", high)) °C)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "temperature-\(cellarName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("Échec de la notification de température : \(error)")
            }
        }
    }
}
