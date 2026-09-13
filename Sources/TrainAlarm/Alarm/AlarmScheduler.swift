import Combine
import Foundation

/// Zustaende, die der Wecker durchlaufen kann.
enum AlarmPhase: Equatable {
    /// Ausgeschaltet.
    case off
    /// Scharf. Die Audio-Engine laeuft im Hintergrund, das Tor ist zu.
    case armed
    /// Weckzeit erreicht, aber die Ausgabe-Route ist nicht privat.
    /// Sobald Kopfhoerer verbunden werden, klingelt es sofort.
    case waitingForHeadphones
    /// Es klingelt.
    case ringing
    /// Schlummern.
    case snoozing

    var isActive: Bool { self != .off }
}

/// Steuert den Wecker: Zeitplanung, Zustandswechsel und das Zusammenspiel von
/// Route, Audio-Engine und Mitteilungen.
@MainActor
final class AlarmScheduler: ObservableObject {

    // MARK: - Beobachtbarer Zustand

    @Published private(set) var phase: AlarmPhase = .off
    /// Zeitpunkt, zu dem geweckt werden soll.
    @Published private(set) var fireDate: Date?
    /// Ende des Wartefensters, in dem noch auf Kopfhoerer gewartet wird.
    @Published private(set) var waitDeadline: Date?
    /// Im Picker eingestellte Uhrzeit.
    @Published var selectedTime: Date = .now
    /// Laufende Uhr fuer die Countdown-Anzeige.
    @Published private(set) var now: Date = .now
    /// Letzter Grund, warum nicht geklingelt werden konnte.
    @Published private(set) var lastBlockReason: String?

    // MARK: - Abhaengigkeiten

    private let engine: AlarmAudioEngine
    private let routeMonitor: AudioRouteMonitor
    private let notifications: NotificationManager
    private let settings: SettingsStore

    private var ticker: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// Wann das Klingeln begonnen hat (fuer die maximale Klingeldauer).
    private var ringingSince: Date?

    init(engine: AlarmAudioEngine,
         routeMonitor: AudioRouteMonitor,
         notifications: NotificationManager,
         settings: SettingsStore) {
        self.engine = engine
        self.routeMonitor = routeMonitor
        self.notifications = notifications
        self.settings = settings
        self.selectedTime = Self.restoreSelectedTime(from: settings)

        engine.onFailsafeTripped = { [weak self] in
            self?.handleFailsafeTripped()
        }

        // Auf Routenwechsel sofort reagieren, statt den naechsten Tick abzuwarten.
        routeMonitor.$safety
            .map(\.isSafeForAlarm)
            .removeDuplicates()
            .sink { [weak self] isSafe in
                self?.routeSafetyChanged(isSafe: isSafe)
            }
            .store(in: &cancellables)

        startTicker()
    }

    // MARK: - Bedienung

    /// Schaltet den Wecker auf die im Picker gewaehlte Uhrzeit scharf.
    func arm() {
        let target = Self.nextOccurrence(of: selectedTime, after: .now)
        arm(at: target)
    }

    /// Schnell-Timer: weckt in `minutes` Minuten.
    func arm(inMinutes minutes: Int) {
        let target = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        selectedTime = target
        arm(at: target)
    }

    private func arm(at date: Date) {
        fireDate = date
        waitDeadline = nil
        lastBlockReason = nil
        phase = .armed
        ringingSince = nil

        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        settings.storeLastAlarm(hour: components.hour ?? 7, minute: components.minute ?? 0)

        engine.apply(settings: settings)
        engine.startKeepAlive()
        notifications.clearTransientNotices()

        let withSound = settings.notificationSound
        Task { await notifications.scheduleAlarm(at: date, withSound: withSound) }

        AppLog.alarm.info("Wecker scharf fuer \(date.description, privacy: .public)")
    }

    /// Schaltet den Wecker komplett ab.
    func disarm() {
        phase = .off
        fireDate = nil
        waitDeadline = nil
        ringingSince = nil
        lastBlockReason = nil
        engine.stopRinging(revertToKeepAlive: false)
        engine.shutdown()
        notifications.cancelAlarm()
        notifications.clearTransientNotices()
        AppLog.alarm.info("Wecker deaktiviert")
    }

    /// Beendet das Klingeln und schaltet den Wecker ab.
    func stopAndDisarm() {
        engine.stopRinging(revertToKeepAlive: false)
        disarm()
    }

    /// Schlummern.
    func snooze() {
        guard phase == .ringing || phase == .waitingForHeadphones else { return }
        let target = Date().addingTimeInterval(settings.snoozeMinutes * 60)
        engine.stopRinging(revertToKeepAlive: true)
        fireDate = target
        waitDeadline = nil
        ringingSince = nil
        phase = .snoozing
        notifications.clearTransientNotices()

        let withSound = settings.notificationSound
        Task { await notifications.scheduleAlarm(at: target, withSound: withSound) }
        AppLog.alarm.info("Schlummern bis \(target.description, privacy: .public)")
    }

    /// Uebernimmt geaenderte Einstellungen in die laufende Engine.
    func settingsChanged() {
        engine.apply(settings: settings)
    }

    // MARK: - Ablaufsteuerung

    private func startTicker() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        now = .now

        switch phase {
        case .off:
            break

        case .armed, .snoozing:
            guard let fireDate, now >= fireDate else { break }
            trigger()

        case .waitingForHeadphones:
            if routeMonitor.safety.isSafeForAlarm {
                startRinging()
            } else if let waitDeadline, now >= waitDeadline {
                giveUp()
            }

        case .ringing:
            // Sicherheitsnetz, falls weder Benachrichtigung noch Watchdog greifen.
            if !routeMonitor.safety.isSafeForAlarm {
                handleFailsafeTripped()
                break
            }
            if let ringingSince, now.timeIntervalSince(ringingSince) >= settings.maxRingMinutes * 60 {
                AppLog.alarm.info("Maximale Klingeldauer erreicht - Wecker wird beendet")
                stopAndDisarm()
            }
        }
    }

    /// Weckzeit erreicht.
    private func trigger() {
        notifications.cancelAlarm()
        if routeMonitor.safety.isSafeForAlarm {
            startRinging()
        } else {
            enterWaitingForHeadphones()
        }
    }

    private func startRinging() {
        engine.apply(settings: settings)
        guard engine.startRinging() else {
            enterWaitingForHeadphones()
            return
        }
        phase = .ringing
        ringingSince = .now
        lastBlockReason = nil
        notifications.clearTransientNotices()
    }

    /// Weckzeit erreicht, aber keine private Route: es bleibt still.
    ///
    /// Das ist die bewusste Konsequenz aus der Kernanforderung. Statt auf den
    /// Lautsprecher auszuweichen, wartet die App darauf, dass die Kopfhoerer
    /// zurueckkommen -- und klingelt dann in derselben Sekunde.
    private func enterWaitingForHeadphones() {
        guard phase != .waitingForHeadphones else { return }
        phase = .waitingForHeadphones
        let grace = settings.reconnectGraceMinutes * 60
        waitDeadline = Date().addingTimeInterval(grace)
        lastBlockReason = routeMonitor.detail
        engine.startKeepAlive()

        let minutes = Int(settings.reconnectGraceMinutes)
        Task { await notifications.notifyHeadphonesMissing(graceMinutes: minutes) }
        AppLog.alarm.error("Weckzeit erreicht, aber keine private Route - es bleibt still")
    }

    private func giveUp() {
        AppLog.alarm.error("Wartefenster abgelaufen - Wecker wird deaktiviert")
        Task { await notifications.notifyAlarmMissed() }
        disarm()
    }

    private func handleFailsafeTripped() {
        guard phase == .ringing else { return }
        AppLog.alarm.error("Failsafe waehrend des Klingelns - zurueck in den Wartezustand")
        engine.stopRinging(revertToKeepAlive: true)
        // Das Wartefenster beginnt neu, damit auch ein spaeter Wiederaufbau
        // der Verbindung noch weckt.
        phase = .armed
        enterWaitingForHeadphones()
    }

    private func routeSafetyChanged(isSafe: Bool) {
        guard isSafe, phase == .waitingForHeadphones else { return }
        AppLog.alarm.info("Kopfhoerer wieder verbunden - Weckton startet sofort")
        startRinging()
    }

    // MARK: - Anzeige-Hilfen

    /// Verbleibende Zeit bis zum Wecken als "1 Std 23 Min".
    var countdownText: String? {
        guard let fireDate, phase == .armed || phase == .snoozing else { return nil }
        let remaining = max(0, fireDate.timeIntervalSince(now))
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let seconds = Int(remaining) % 60

        if hours > 0 { return "\(hours) Std \(minutes) Min" }
        if totalMinutes > 0 { return "\(minutes) Min \(seconds) Sek" }
        return "\(seconds) Sek"
    }

    /// Verbleibende Zeit im Wartefenster.
    var waitCountdownText: String? {
        guard let waitDeadline, phase == .waitingForHeadphones else { return nil }
        let remaining = max(0, waitDeadline.timeIntervalSince(now))
        return "\(Int(remaining / 60)) Min \(Int(remaining) % 60) Sek"
    }

    var fireTimeText: String? {
        guard let fireDate else { return nil }
        return Self.timeFormatter.string(from: fireDate)
    }

    // MARK: - Hilfsfunktionen

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Naechstes Auftreten der gewaehlten Uhrzeit -- heute, sonst morgen.
    static func nextOccurrence(of time: Date, after reference: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let todayMatch = calendar.nextDate(
            after: reference.addingTimeInterval(-1),
            matching: DateComponents(hour: components.hour, minute: components.minute),
            matchingPolicy: .nextTime
        ) else {
            return reference.addingTimeInterval(60)
        }
        return todayMatch
    }

    private static func restoreSelectedTime(from settings: SettingsStore) -> Date {
        guard let stored = settings.lastAlarmComponents else {
            return Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
        }
        return Calendar.current.date(bySettingHour: stored.hour, minute: stored.minute, second: 0, of: .now) ?? .now
    }
}
