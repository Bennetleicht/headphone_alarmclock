import AVFoundation
import Foundation

/// Einstufung einer Audio-Ausgabe-Route danach, ob sie "privat" ist -- also
/// ausschliesslich in den Ohren der Nutzerin bzw. des Nutzers landet und nicht
/// im ganzen Zugabteil.
enum OutputClassification: Equatable {

    /// AirPods, Over-Ear-Bluetooth-Kopfhoerer, Bluetooth-Headsets.
    case bluetoothHeadphones
    /// Klinke / Lightning / kabelgebundene EarPods (`.headphones`).
    case wiredHeadphones
    /// USB-C-Headsets. iOS meldet sie als `.usbAudio`; dahinter kann theoretisch
    /// auch ein USB-Lautsprecher stecken, deshalb per Einstellung abschaltbar.
    case usbAudio
    /// Eingebauter Lautsprecher oder Hoerkapsel -- fuer diese App tabu.
    case builtInSpeaker
    /// Auto-Freisprecheinrichtung: technisch Bluetooth, akustisch ein Lautsprecher.
    case carAudio
    /// AirPlay / HDMI -- ebenfalls potenziell laut im Raum.
    case externalWireless
    /// Alles, was sich nicht eindeutig zuordnen laesst.
    case unknown

    /// Die zentrale Sicherheitsfrage: Darf hierueber der Weckton laufen?
    ///
    /// - Parameter trustUSB: Ob USB-Audio als Kopfhoerer gewertet werden soll.
    func isPrivateListening(trustUSB: Bool) -> Bool {
        switch self {
        case .bluetoothHeadphones, .wiredHeadphones:
            return true
        case .usbAudio:
            return trustUSB
        case .builtInSpeaker, .carAudio, .externalWireless, .unknown:
            return false
        }
    }

    var symbolName: String {
        switch self {
        case .bluetoothHeadphones: return "airpodspro"
        case .wiredHeadphones: return "headphones"
        case .usbAudio: return "cable.connector"
        case .builtInSpeaker: return "iphone"
        case .carAudio: return "car.fill"
        case .externalWireless: return "airplayaudio"
        case .unknown: return "questionmark.circle"
        }
    }

    var germanLabel: String {
        switch self {
        case .bluetoothHeadphones: return "Bluetooth-Kopfhoerer"
        case .wiredHeadphones: return "Kabel-Kopfhoerer"
        case .usbAudio: return "USB-C-Headset"
        case .builtInSpeaker: return "iPhone-Lautsprecher"
        case .carAudio: return "Auto-Audio"
        case .externalWireless: return "AirPlay / HDMI"
        case .unknown: return "Unbekannte Ausgabe"
        }
    }

    /// Bildet einen `AVAudioSession.Port` auf die App-interne Einstufung ab.
    static func classify(_ port: AVAudioSession.Port) -> OutputClassification {
        switch port {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetoothHeadphones
        case .headphones:
            return .wiredHeadphones
        case .usbAudio:
            return .usbAudio
        case .builtInSpeaker, .builtInReceiver:
            return .builtInSpeaker
        case .carAudio:
            return .carAudio
        case .airPlay, .HDMI:
            return .externalWireless
        default:
            return .unknown
        }
    }
}

/// Eine konkrete Ausgabe-Route, wie sie in
/// `AVAudioSession.sharedInstance().currentRoute.outputs` steht.
struct AudioOutput: Identifiable, Equatable {
    let id: String
    let name: String
    let portType: AVAudioSession.Port
    let classification: OutputClassification

    init(port: AVAudioSessionPortDescription) {
        self.id = port.uid
        self.name = port.portName
        self.portType = port.portType
        self.classification = OutputClassification.classify(port.portType)
    }
}

/// Gesamtbewertung der aktuellen Route.
struct RouteSafety: Equatable {
    /// Alle aktuell aktiven Ausgaben.
    var outputs: [AudioOutput]
    /// `true`, wenn mindestens eine Ausgabe existiert und **jede** davon privat ist.
    var isSafeForAlarm: Bool

    /// Die fuer die Anzeige interessanteste Ausgabe (bevorzugt die private).
    var primaryOutput: AudioOutput? {
        outputs.first(where: { $0.classification != .builtInSpeaker }) ?? outputs.first
    }

    static let empty = RouteSafety(outputs: [], isSafeForAlarm: false)
}
