import Foundation

/// Echtzeit-sicheres Tor zwischen App-Logik und Audio-Render-Thread.
///
/// ## Warum das so gebaut ist
///
/// Der Render-Block eines `AVAudioSourceNode` laeuft auf dem Audio-Thread mit
/// harter Echtzeit-Anforderung. Dort sind Locks, Allokationen, Swift-Runtime-
/// Aufrufe und Objective-C-Messaging verboten -- ein blockierter Audio-Thread
/// erzeugt Aussetzer.
///
/// Gleichzeitig muss der Failsafe (Kopfhoerer getrennt -> sofort still) aus
/// einem beliebigen Thread heraus greifen koennen, und zwar **synchron**, bevor
/// irgendein Hop auf den Main-Actor passiert.
///
/// Loesung: zwei einzelne, korrekt ausgerichtete 32-Bit-Woerter im Heap. Lesen
/// und Schreiben eines ausgerichteten 32-Bit-Wortes ist auf arm64 eine einzelne
/// Maschineninstruktion und damit unteilbar -- es kann also nie ein halb
/// geschriebener Wert gelesen werden. Mehr Garantie braucht dieses Tor nicht:
/// es gibt genau einen Schreiber pro Wort und der Leser nimmt einfach den
/// jeweils aktuellsten Wert.
final class AudioGate: @unchecked Sendable {

    /// 1 = Ton erlaubt, 0 = sofort stumm.
    private let openWord: UnsafeMutablePointer<Int32>
    /// Ziel-Lautstaerke (0.0 ... 1.0), als Bitmuster eines `Float` abgelegt.
    private let gainWord: UnsafeMutablePointer<UInt32>

    init() {
        openWord = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        gainWord = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        openWord.initialize(to: 0)
        gainWord.initialize(to: Float(0).bitPattern)
    }

    deinit {
        openWord.deinitialize(count: 1)
        openWord.deallocate()
        gainWord.deinitialize(count: 1)
        gainWord.deallocate()
    }

    // MARK: - Schreiben (beliebiger Thread)

    /// Oeffnet das Tor. Der Render-Block blendet den Ton in wenigen
    /// Millisekunden ein.
    func open() {
        openWord.pointee = 1
    }

    /// Schliesst das Tor. **Das ist der Not-Aus.** Der Aufruf ist synchron,
    /// allokationsfrei und darf aus jedem Thread erfolgen -- insbesondere direkt
    /// aus dem Handler von `AVAudioSession.routeChangeNotification`.
    func close() {
        openWord.pointee = 0
    }

    /// Setzt die Ziellautstaerke. Rampen (sanftes Aufwachen) werden von aussen
    /// gesteuert, indem dieser Wert schrittweise erhoeht wird.
    func setGain(_ value: Float) {
        gainWord.pointee = min(max(value, 0), 1).bitPattern
    }

    // MARK: - Lesen (Audio-Thread, echtzeitsicher)

    @inline(__always)
    var isOpen: Bool { openWord.pointee != 0 }

    @inline(__always)
    var gain: Float { Float(bitPattern: gainWord.pointee) }

    /// Der Wert, auf den der Render-Block zusteuert: 0, sobald das Tor zu ist.
    @inline(__always)
    var targetAmplitude: Float { isOpen ? Float(bitPattern: gainWord.pointee) : 0 }
}
