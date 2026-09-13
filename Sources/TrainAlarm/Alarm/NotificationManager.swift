import Foundation
import UserNotifications

/// Lokale Mitteilungen als Rueckfallebene.
///
/// ## Wichtige Einschraenkung
///
/// Ein Mitteilungston laeuft ueber die **Systemwiedergabe**, nicht ueber die
/// Audio-Session dieser App. iOS entscheidet dann selbst ueber die Route -- und
/// waehlt im Zweifel den iPhone-Lautsprecher. Genau das soll TrainAlarm
/// verhindern.
///
/// Deshalb sind alle Mitteilungen standardmaessig **lautlos**. Sie dienen als
/// sichtbarer Hinweis (plus Vibration, je nach Systemeinstellung), falls die App
/// vom System beendet wurde und der Weckton gar nicht erst starten konnte.
/// Wer den Systemton trotzdem will, kann ihn in den Einstellungen einschalten --
/// mit entsprechendem Warnhinweis in der Oberflaeche.
@MainActor
final class NotificationManager: ObservableObject {

    enum AuthorizationState: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var authorization: AuthorizationState = .unknown

    private let center = UNUserNotificationCenter.current()

    private enum Identifier {
        static let alarm = "trainalarm.alarm"
        static let headphonesMissing = "trainalarm.headphones-missing"
        static let missed = "trainalarm.missed"
    }

    // MARK: - Berechtigung

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorization = .granted
        case .denied:
            authorization = .denied
        case .notDetermined:
            authorization = .unknown
        @unknown default:
            authorization = .unknown
        }
    }

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorization = granted ? .granted : .denied
            AppLog.notifications.info("Mitteilungs-Berechtigung: \(granted ? "erteilt" : "abgelehnt", privacy: .public)")
        } catch {
            authorization = .denied
            AppLog.notifications.error("Berechtigung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Planen

    /// Plant die Rueckfall-Mitteilung zur Weckzeit.
    func scheduleAlarm(at date: Date, withSound: Bool) async {
        cancelAlarm()
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "TrainAlarm"
        content.body = "Weckzeit erreicht - Zeit zum Aussteigen."
        content.sound = withSound ? .default : nil
        // Bricht auch durch Fokus-Modi. Ohne passende Berechtigung stuft iOS
        // die Stufe stillschweigend auf "aktiv" herunter.
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.alarm, content: content, trigger: trigger)

        do {
            try await center.add(request)
            AppLog.notifications.info("Rueckfall-Mitteilung fuer \(date.description, privacy: .public) geplant")
        } catch {
            AppLog.notifications.error("Mitteilung konnte nicht geplant werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelAlarm() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.alarm])
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.alarm])
    }

    // MARK: - Sofort-Hinweise

    /// Weckzeit erreicht, aber keine Kopfhoerer verbunden.
    func notifyHeadphonesMissing(graceMinutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Wecker kann nicht klingeln"
        content.body = "Keine Kopfhoerer verbunden. Sobald du sie wieder verbindest, klingelt TrainAlarm sofort (noch \(graceMinutes) Min)."
        content.sound = nil
        content.interruptionLevel = .timeSensitive
        await post(content, identifier: Identifier.headphonesMissing)
    }

    /// Wartefenster abgelaufen, ohne dass Kopfhoerer zurueckkamen.
    func notifyAlarmMissed() async {
        let content = UNMutableNotificationContent()
        content.title = "Wecker verpasst"
        content.body = "Die Kopfhoerer kamen nicht rechtzeitig zurueck. Der Wecker wurde deaktiviert."
        content.sound = nil
        content.interruptionLevel = .timeSensitive
        await post(content, identifier: Identifier.missed)
    }

    func clearTransientNotices() {
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.headphonesMissing, Identifier.missed])
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.headphonesMissing, Identifier.missed])
    }

    private func post(_ content: UNMutableNotificationContent, identifier: String) async {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            AppLog.notifications.error("Hinweis \(identifier, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }
}
