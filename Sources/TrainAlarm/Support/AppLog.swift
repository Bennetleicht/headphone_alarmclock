import Foundation
import OSLog

/// Zentrale Logger-Instanzen. Ueber die Konsole (Console.app / `log stream`)
/// laesst sich damit nachvollziehen, warum der Wecker geklingelt hat -- oder
/// eben bewusst nicht.
enum AppLog {
    private static let subsystem = "de.trainalarm.app"

    static let route = Logger(subsystem: subsystem, category: "audio-route")
    static let engine = Logger(subsystem: subsystem, category: "audio-engine")
    static let alarm = Logger(subsystem: subsystem, category: "alarm")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
