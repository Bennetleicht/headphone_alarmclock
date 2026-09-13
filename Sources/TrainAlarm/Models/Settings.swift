import Foundation

/// Persistente Einstellungen.
///
/// Die Werte liegen in `UserDefaults`, weil sie auch aus Nicht-Main-Actor-
/// Kontexten gelesen werden muessen (der Failsafe bewertet die Route im
/// Notification-Handler, bevor er auf den Main-Actor springt).
enum SettingsKey {
    static let trustUSBAudio = "settings.trustUSBAudio"
    static let volume = "settings.volume"
    static let gentleWakeUp = "settings.gentleWakeUp"
    static let gentleWakeUpDuration = "settings.gentleWakeUpDuration"
    static let notificationSound = "settings.notificationSound"
    static let maxRingMinutes = "settings.maxRingMinutes"
    static let reconnectGraceMinutes = "settings.reconnectGraceMinutes"
    static let snoozeMinutes = "settings.snoozeMinutes"
    static let lastAlarmHour = "settings.lastAlarmHour"
    static let lastAlarmMinute = "settings.lastAlarmMinute"
}

@MainActor
final class SettingsStore: ObservableObject {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKey.trustUSBAudio: true,
            SettingsKey.volume: 0.85,
            SettingsKey.gentleWakeUp: true,
            SettingsKey.gentleWakeUpDuration: 20.0,
            SettingsKey.notificationSound: false,
            SettingsKey.maxRingMinutes: 10.0,
            SettingsKey.reconnectGraceMinutes: 15.0,
            SettingsKey.snoozeMinutes: 5.0,
        ])
    }

    /// USB-C-Headsets als "privat" werten. Standardmaessig an, weil das
    /// iPhone 15 kabelgebundene EarPods ueber USB-C anbindet.
    var trustUSBAudio: Bool {
        get { defaults.bool(forKey: SettingsKey.trustUSBAudio) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.trustUSBAudio) }
    }

    /// App-interne Lautstaerke des Wecktons (0.0 ... 1.0).
    var volume: Double {
        get { defaults.double(forKey: SettingsKey.volume) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.volume) }
    }

    /// Sanftes Aufwachen: der Ton startet leise und steigert sich.
    var gentleWakeUp: Bool {
        get { defaults.bool(forKey: SettingsKey.gentleWakeUp) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.gentleWakeUp) }
    }

    /// Dauer der Lautstaerkerampe in Sekunden.
    var gentleWakeUpDuration: Double {
        get { defaults.double(forKey: SettingsKey.gentleWakeUpDuration) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.gentleWakeUpDuration) }
    }

    /// Systemton fuer die Fallback-Mitteilung.
    ///
    /// **Achtung:** Mitteilungstoene laufen ueber die Systemwiedergabe und
    /// koennen damit auf dem iPhone-Lautsprecher landen. Deshalb aus.
    var notificationSound: Bool {
        get { defaults.bool(forKey: SettingsKey.notificationSound) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.notificationSound) }
    }

    /// Nach wie vielen Minuten der Weckton von selbst aufhoert.
    var maxRingMinutes: Double {
        get { defaults.double(forKey: SettingsKey.maxRingMinutes) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.maxRingMinutes) }
    }

    /// Wie lange nach der Weckzeit noch auf zurueckkehrende Kopfhoerer
    /// gewartet wird (Akku leer, Ohrhoerer im Etui ...).
    var reconnectGraceMinutes: Double {
        get { defaults.double(forKey: SettingsKey.reconnectGraceMinutes) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.reconnectGraceMinutes) }
    }

    /// Schlummerdauer in Minuten.
    var snoozeMinutes: Double {
        get { defaults.double(forKey: SettingsKey.snoozeMinutes) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: SettingsKey.snoozeMinutes) }
    }

    /// Zuletzt eingestellte Weckzeit, damit die App sie beim Start wieder anbietet.
    func storeLastAlarm(hour: Int, minute: Int) {
        defaults.set(hour, forKey: SettingsKey.lastAlarmHour)
        defaults.set(minute, forKey: SettingsKey.lastAlarmMinute)
    }

    var lastAlarmComponents: (hour: Int, minute: Int)? {
        guard defaults.object(forKey: SettingsKey.lastAlarmHour) != nil else { return nil }
        return (defaults.integer(forKey: SettingsKey.lastAlarmHour),
                defaults.integer(forKey: SettingsKey.lastAlarmMinute))
    }

    /// Nicht-isolierter Zugriff fuer den Failsafe-Pfad.
    nonisolated static var trustUSBAudioValue: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.trustUSBAudio) as? Bool ?? true
    }
}
