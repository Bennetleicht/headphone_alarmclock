import AVFoundation
import Foundation

/// Kapselt die Konfiguration der `AVAudioSession`.
///
/// Zwei Betriebsarten:
///
/// * **keepAlive** -- der Wecker ist scharf, es laeuft digitale Stille. Mit
///   `.mixWithOthers`, damit laufende Musik oder ein Podcast nicht abgewuergt
///   werden, nur weil der Wecker gestellt ist.
/// * **ringing** -- es wird geweckt. Jetzt ohne `.mixWithOthers`, dafuer mit
///   `.duckOthers`: fremde Wiedergabe wird leiser, der Weckton setzt sich durch.
///
/// In beiden Faellen ist die Kategorie `.playback`. Das ist der entscheidende
/// Punkt fuer die Anforderung "klingelt auch bei stummgeschaltetem iPhone":
/// `.playback` ignoriert den Stummschalter bzw. den Action-Button.
enum AudioSessionMode {
    case keepAlive
    case ringing
}

final class AudioSessionController {

    private let session = AVAudioSession.sharedInstance()

    /// Optionen, absteigend nach Wunsch sortiert.
    ///
    /// Hintergrund: `.allowBluetooth` (HFP) ist laut Apple-Dokumentation nur
    /// fuer aufnehmende Kategorien vorgesehen. In Kombination mit `.playback`
    /// quittiert iOS das je nach Version mit einem Fehler. Die Aufgabenstellung
    /// verlangt die Option ausdruecklich, also wird sie zuerst versucht -- und
    /// bei einem Fehler sauber auf die naechstkleinere Variante zurueckgefallen,
    /// statt die Session ganz unkonfiguriert zu lassen.
    ///
    /// `.allowAirPlay` fehlt hier bewusst: AirPlay wuerde den Weckton auf einen
    /// Lautsprecher im Raum schicken -- genau das soll nicht passieren.
    private static func optionLadder(for mode: AudioSessionMode) -> [AVAudioSession.CategoryOptions] {
        let sharing: AVAudioSession.CategoryOptions = (mode == .keepAlive) ? .mixWithOthers : .duckOthers
        return [
            [.allowBluetooth, .allowBluetoothA2DP, sharing],
            [.allowBluetoothA2DP, sharing],
            [sharing],
            [],
        ]
    }

    /// Konfiguriert die Session fuer den gewuenschten Modus und aktiviert sie.
    /// - Throws: Der letzte Fehler, falls keine einzige Optionskombination greift.
    func activate(mode: AudioSessionMode) throws {
        var lastError: Error?

        for options in Self.optionLadder(for: mode) {
            do {
                try session.setCategory(.playback, mode: .default, options: options)
                AppLog.engine.info("AudioSession: .playback mit Optionen \(options.rawValue, privacy: .public) gesetzt (Modus: \(String(describing: mode), privacy: .public))")
                lastError = nil
                break
            } catch {
                lastError = error
                AppLog.engine.warning("AudioSession: Optionen \(options.rawValue, privacy: .public) abgelehnt (\(error.localizedDescription, privacy: .public)) -- versuche naechste Stufe")
            }
        }

        if let lastError { throw lastError }

        // Kurze I/O-Puffer: der Failsafe wirkt genau so schnell, wie der
        // Hardware-Puffer durchlaeuft. 5 ms statt der Standard-23 ms.
        try? session.setPreferredIOBufferDuration(0.005)

        try session.setActive(true, options: [])
    }

    /// Gibt die Session frei, damit andere Apps die Audio-Hoheit zurueckbekommen.
    func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            AppLog.engine.info("AudioSession deaktiviert")
        } catch {
            AppLog.engine.error("AudioSession konnte nicht deaktiviert werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Systemlautstaerke der aktuellen Route (0.0 ... 1.0).
    var systemOutputVolume: Float { session.outputVolume }

    var sampleRate: Double { session.sampleRate }
}
