import os

/// Journalisation centralisée de CaveOS (remplace `print` en production).
///
/// Les appelants passent une `String` normale ; toute l'API `os.Logger` est
/// encapsulée ici (inutile d'importer `os` ailleurs). Les messages partent dans
/// le système de log unifié d'Apple (Console.app / `log stream`), filtrables par
/// catégorie, au niveau `error` (ces appels remplacent des logs d'échec).
enum Log {
    private static let subsystem = "com.louisbdc.caveos"

    private static let persistenceLog = Logger(subsystem: subsystem, category: "persistence")
    private static let notificationsLog = Logger(subsystem: subsystem, category: "notifications")
    private static let exportLog = Logger(subsystem: subsystem, category: "export")
    private static let syncLog = Logger(subsystem: subsystem, category: "sync")

    static func persistence(_ message: String) {
        persistenceLog.error("\(message, privacy: .public)")
    }

    static func notifications(_ message: String) {
        notificationsLog.error("\(message, privacy: .public)")
    }

    static func export(_ message: String) {
        exportLog.error("\(message, privacy: .public)")
    }

    static func sync(_ message: String) {
        syncLog.error("\(message, privacy: .public)")
    }
}
