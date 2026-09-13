import AVFoundation
import Combine
import Foundation

/// Echtzeit-Ueberwachung der Audio-Ausgabe-Route.
///
/// Die Klasse beantwortet durchgehend die eine Frage, um die sich diese App
/// dreht: *Landet Ton gerade garantiert nur im Ohr -- oder koennte er im Abteil
/// zu hoeren sein?*
@MainActor
final class AudioRouteMonitor: ObservableObject {

    /// Aktuelle Bewertung der Route.
    @Published private(set) var safety: RouteSafety = .empty
    /// Systemlautstaerke der aktuellen Route (Hardware-Regler, 0.0 ... 1.0).
    @Published private(set) var systemVolume: Float = 0
    /// Zeitstempel der letzten Routenaenderung -- fuer die Statusanzeige.
    @Published private(set) var lastChange: Date = .now

    private var volumeObservation: NSKeyValueObservation?

    /// Haelt die Block-Observer. `NotificationCenter` entfernt die naemlich
    /// nicht von selbst; die Ablage in einem eigenen, nicht-isolierten Objekt
    /// erlaubt das Aufraeumen im `deinit`, ohne den Main-Actor zu beruehren.
    private let observerBag = ObserverBag()

    init() {
        refresh()
        systemVolume = AVAudioSession.sharedInstance().outputVolume
        startObserving()
    }

    // MARK: - Beobachtung

    private func startObserving() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observerBag.add(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            Task { @MainActor in self?.handleRouteChange(rawReason: rawReason) }
        })

        // Nach einem Reset der Medien-Dienste ist jede vorherige Konfiguration
        // hinfaellig -- die Route muss neu bewertet werden.
        observerBag.add(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppLog.route.warning("Medien-Dienste wurden zurueckgesetzt")
                self?.refresh()
            }
        })

        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in self?.systemVolume = value }
        }
    }

    private func handleRouteChange(rawReason: UInt) {
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) ?? .unknown
        AppLog.route.info("Routenwechsel: \(Self.describe(reason), privacy: .public)")
        refresh()
        lastChange = .now
    }

    /// Liest die Route neu ein und bewertet sie.
    func refresh() {
        safety = Self.evaluateCurrentRoute()
    }

    // MARK: - Bewertung

    /// Bewertet die **aktuelle** Route. Bewusst `nonisolated` und synchron:
    /// der Failsafe muss diese Frage im Notification-Handler beantworten
    /// koennen, ohne vorher auf den Main-Actor zu wechseln.
    nonisolated static func evaluateCurrentRoute() -> RouteSafety {
        let trustUSB = SettingsStore.trustUSBAudioValue
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(AudioOutput.init(port:))

        // Strenge Auslegung: Es reicht nicht, dass *irgendwo* ein Kopfhoerer
        // haengt. Jede aktive Ausgabe muss privat sein -- sonst laeuft der Ton
        // parallel ueber den Lautsprecher.
        let safe = !outputs.isEmpty && outputs.allSatisfy {
            $0.classification.isPrivateListening(trustUSB: trustUSB)
        }

        return RouteSafety(outputs: outputs, isSafeForAlarm: safe)
    }

    // MARK: - Anzeige-Hilfen

    /// Ueberschrift fuer die grosse Statuskarte.
    var headline: String {
        guard let output = safety.primaryOutput else { return "Kein Kopfhoerer erkannt!" }
        if safety.isSafeForAlarm {
            return output.name
        }
        switch output.classification {
        case .builtInSpeaker: return "Kein Kopfhoerer erkannt!"
        case .carAudio: return "Auto-Audio aktiv"
        case .externalWireless: return "AirPlay aktiv"
        case .usbAudio: return "USB-Audio nicht freigegeben"
        default: return "Ausgabe nicht sicher"
        }
    }

    /// Zweite Zeile der Statuskarte.
    var detail: String {
        guard let output = safety.primaryOutput else {
            return "Der Wecker bleibt stumm, bis Kopfhoerer verbunden sind."
        }
        if safety.isSafeForAlarm {
            return "\(output.classification.germanLabel) verbunden - Wecken ist moeglich."
        }
        switch output.classification {
        case .builtInSpeaker:
            return "Ton wuerde ueber den iPhone-Lautsprecher laufen. Wecker bleibt stumm."
        case .carAudio:
            return "Freisprecheinrichtung ist kein privater Kopfhoerer. Wecker bleibt stumm."
        case .externalWireless:
            return "Kabellose Uebertragung an ein externes Geraet. Wecker bleibt stumm."
        case .usbAudio:
            return "USB-Audio erkannt - in den Einstellungen freigeben, falls es ein Headset ist."
        default:
            return "Ausgabe \"\(output.name)\" ist nicht als Kopfhoerer eingestuft."
        }
    }

    var symbolName: String {
        safety.primaryOutput?.classification.symbolName ?? "exclamationmark.triangle.fill"
    }

    private static func describe(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .newDeviceAvailable: return "neues Geraet verfuegbar"
        case .oldDeviceUnavailable: return "Geraet getrennt"
        case .categoryChange: return "Kategoriewechsel"
        case .override: return "Route ueberschrieben"
        case .wakeFromSleep: return "Aufwachen"
        case .noSuitableRouteForCategory: return "keine passende Route"
        case .routeConfigurationChange: return "Konfigurationsaenderung"
        case .unknown: return "unbekannt"
        @unknown default: return "unbekannt (neu)"
        }
    }
}

/// Kleiner Behaelter fuer `NotificationCenter`-Block-Observer.
///
/// Eigenes Objekt, damit das Abmelden im `deinit` stattfinden kann: der
/// `deinit` eines `@MainActor`-Typs darf keine isolierten Eigenschaften lesen.
private final class ObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        lock.lock()
        tokens.append(token)
        lock.unlock()
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
