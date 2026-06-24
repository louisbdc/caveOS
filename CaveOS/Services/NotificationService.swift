import Foundation
import UserNotifications

/// Service de notifications locales : alertes d'apogée et rappels de bouteilles ouvertes.
@MainActor
@Observable
final class NotificationService {

    private let center = UNUserNotificationCenter.current()

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

    /// Annule toutes les notifications planifiées pour une bouteille.
    func cancel(for bottle: Bottle) {
        center.removePendingNotificationRequests(withIdentifiers: [
            apogeeIdentifier(for: bottle),
            openedIdentifier(for: bottle)
        ])
    }
}
