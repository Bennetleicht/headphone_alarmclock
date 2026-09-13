import AVFoundation
import Combine
import Foundation

/// Erzeugt den Weckton und garantiert, dass er ausschliesslich ueber private
/// Ausgaben laeuft.
///
/// ## Aufbau
///
/// ```
///   AVAudioSourceNode  ->  mainMixerNode  ->  outputNode
///   (Ton-Synthese)         (Pegel)            (Hardware)
/// ```
///
/// Der Ton wird nicht aus einer Datei abgespielt, sondern im Render-Block
/// berechnet. Das hat drei Vorteile:
///
/// 1. Kein Audio-Asset noetig -- das Projekt bleibt unter Linux vollstaendig
///    editierbar.
/// 2. Der Pegel laesst sich sample-genau steuern, inklusive der Rampe fuer
///    sanftes Aufwachen.
/// 3. **Der Failsafe sitzt im Render-Block selbst.** Wird das Tor geschlossen,
///    schreibt der naechste Render-Durchlauf Stille -- unabhaengig davon, was
///    die restliche App gerade tut.
///
/// ## Hintergrundbetrieb
///
/// Solange der Wecker scharf ist, laeuft die Engine mit einem unhoerbaren
/// Traegersignal weiter (siehe `keepAliveAmplitude`). Das haelt die App im
/// Hintergrund am Leben, sodass der Timer die Weckzeit zuverlaessig erreicht.
/// Dieses Vorgehen ist fuer Sideloading gedacht; im App Store wuerde Apple es
/// pruefen (siehe README).
@MainActor
final class AlarmAudioEngine: ObservableObject {

    // MARK: - Beobachtbarer Zustand

    @Published private(set) var isEngineRunning = false
    @Published private(set) var isRinging = false
    @Published private(set) var isTestPlaying = false
    /// Zeitpunkt, an dem der Failsafe zuletzt eingegriffen hat.
    @Published private(set) var lastFailsafeTrip: Date?

    /// Wird aufgerufen, wenn der Not-Aus waehrend des Klingelns gegriffen hat.
    var onFailsafeTripped: (@MainActor () -> Void)?

    // MARK: - Interna

    private let gate = AudioGate()
    private let session = AudioSessionController()
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var rampTimer: Timer?
    private var watchdogTimer: Timer?
    private var testStopWorkItem: DispatchWorkItem?
    private let observerBag = EngineObserverBag()

    /// Ziel-Lautstaerke des Wecktons (0.0 ... 1.0).
    private var targetVolume: Float = 0.85
    private var gentleWakeUp = true
    private var gentleWakeUpDuration: TimeInterval = 20

    init() {
        installFailsafeObserver()
        installMediaServicesObserver()
        installConfigurationObserver()
    }

    // MARK: - Failsafe

    /// Registriert den Not-Aus.
    ///
    /// `queue: nil` ist hier entscheidend: Der Block wird **synchron auf dem
    /// Thread des Absenders** ausgefuehrt, nicht erst beim naechsten Durchlauf
    /// der Main-Runloop. Damit ist das Tor bereits zu, bevor iOS die neue Route
    /// ueberhaupt zu Ende eingerichtet hat.
    private func installFailsafeObserver() {
        observerBag.add(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [gate = self.gate, weak self] _ in
            let isSafe = AudioRouteMonitor.evaluateCurrentRoute().isSafeForAlarm
            if !isSafe {
                // NOT-AUS. Synchron, allokationsfrei, vor jedem Actor-Hop.
                gate.close()
                AppLog.engine.error("FAILSAFE: Route nicht mehr privat - Wiedergabe sofort gestoppt")
            }
            Task { @MainActor in self?.routeChanged(isSafe: isSafe) }
        })

        observerBag.add(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [gate = self.gate, weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            if AVAudioSession.InterruptionType(rawValue: raw) == .began { gate.close() }
            Task { @MainActor in self?.handleInterruption(rawType: raw) }
        })
    }

    private func routeChanged(isSafe: Bool) {
        guard !isSafe else {
            // Route ist wieder sicher. Die Engine kann nach einem Wechsel
            // angehalten worden sein -- notfalls neu aufbauen.
            if isEngineRunning && !engine.isRunning { restartEngine() }
            return
        }
        guard isRinging || isTestPlaying else { return }
        lastFailsafeTrip = .now
        isTestPlaying = false
        if isRinging {
            isRinging = false
            onFailsafeTripped?()
        }
    }

    private func handleInterruption(rawType: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            AppLog.engine.info("Audio-Unterbrechung begonnen (z. B. Anruf)")
        case .ended:
            AppLog.engine.info("Audio-Unterbrechung beendet")
            if isEngineRunning { restartEngine() }
        @unknown default:
            break
        }
    }

    /// Haengt am jeweils aktuellen `AVAudioEngine`-Objekt und wird deshalb nach
    /// einem Neuaufbau erneut registriert.
    private func installConfigurationObserver() {
        let token = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppLog.engine.info("Engine-Konfiguration geaendert - Graph wird neu aufgebaut")
                self?.restartEngine()
            }
        }
        observerBag.replaceConfigurationObserver(with: token)
    }

    /// Wird genau einmal registriert.
    private func installMediaServicesObserver() {
        observerBag.add(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverFromMediaServicesReset() }
        })
    }

    // MARK: - Konfiguration

    func apply(settings: SettingsStore) {
        targetVolume = Float(settings.volume)
        gentleWakeUp = settings.gentleWakeUp
        gentleWakeUpDuration = settings.gentleWakeUpDuration
        // Laeuft der Ton gerade, wirkt die neue Lautstaerke sofort.
        if isRinging && rampTimer == nil { gate.setGain(targetVolume) }
        if isTestPlaying { gate.setGain(targetVolume) }
    }

    // MARK: - Lebenszyklus

    /// Startet den Hintergrundbetrieb: Engine laeuft, Tor bleibt zu.
    func startKeepAlive() {
        guard !isEngineRunning else { return }
        do {
            try session.activate(mode: .keepAlive)
            try buildAndStartEngine()
            isEngineRunning = true
            AppLog.engine.info("Keep-Alive gestartet (Engine laeuft, Tor geschlossen)")
        } catch {
            isEngineRunning = false
            AppLog.engine.error("Keep-Alive konnte nicht gestartet werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Faehrt alles herunter und gibt die Audio-Hoheit zurueck.
    func shutdown() {
        stopRinging(revertToKeepAlive: false)
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        engine.stop()
        isEngineRunning = false
        session.deactivate()
        AppLog.engine.info("Audio-Engine heruntergefahren")
    }

    // MARK: - Klingeln

    /// Startet den Weckton -- aber nur, wenn die Route privat ist.
    /// - Returns: `true`, wenn tatsaechlich Ton ausgegeben wird.
    @discardableResult
    func startRinging() -> Bool {
        let safety = AudioRouteMonitor.evaluateCurrentRoute()
        guard safety.isSafeForAlarm else {
            AppLog.engine.error("Klingeln verweigert: keine private Ausgabe-Route")
            return false
        }

        do {
            try session.activate(mode: .ringing)
        } catch {
            AppLog.engine.error("Session konnte nicht auf Klingel-Modus gesetzt werden: \(error.localizedDescription, privacy: .public)")
        }

        if !engine.isRunning {
            do { try buildAndStartEngine() } catch {
                AppLog.engine.error("Engine-Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        isEngineRunning = true

        // Die Route nach dem Kategoriewechsel erneut pruefen: `setCategory`
        // kann selbst einen Routenwechsel ausgeloest haben.
        guard AudioRouteMonitor.evaluateCurrentRoute().isSafeForAlarm else {
            AppLog.engine.error("Klingeln abgebrochen: Route hat sich beim Aktivieren geaendert")
            gate.close()
            return false
        }

        startGainRamp()
        gate.open()
        isRinging = true
        startWatchdog()
        AppLog.engine.info("Weckton gestartet auf \(safety.primaryOutput?.name ?? "?", privacy: .public)")
        return true
    }

    /// Beendet den Weckton.
    /// - Parameter revertToKeepAlive: Ob die Engine danach im Hintergrund
    ///   weiterlaufen soll (Wecker bleibt scharf bzw. schlummert).
    func stopRinging(revertToKeepAlive: Bool) {
        gate.close()
        rampTimer?.invalidate()
        rampTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        isRinging = false
        isTestPlaying = false
        testStopWorkItem?.cancel()
        testStopWorkItem = nil

        if revertToKeepAlive {
            try? session.activate(mode: .keepAlive)
        }
    }

    // MARK: - Testton

    /// Spielt den Weckton kurz zur Probe -- ebenfalls nur ueber Kopfhoerer.
    @discardableResult
    func playTestTone(seconds: TimeInterval = 3) -> Bool {
        guard !isRinging else { return false }
        guard AudioRouteMonitor.evaluateCurrentRoute().isSafeForAlarm else {
            AppLog.engine.notice("Testton verweigert: keine private Ausgabe-Route")
            return false
        }

        do {
            try session.activate(mode: .ringing)
            if !engine.isRunning { try buildAndStartEngine() }
            isEngineRunning = true
        } catch {
            AppLog.engine.error("Testton fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return false
        }

        rampTimer?.invalidate()
        rampTimer = nil
        gate.setGain(targetVolume)
        gate.open()
        isTestPlaying = true
        startWatchdog()

        testStopWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.stopTestTone() }
        }
        testStopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return true
    }

    func stopTestTone() {
        guard isTestPlaying else { return }
        gate.close()
        isTestPlaying = false
        testStopWorkItem?.cancel()
        testStopWorkItem = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if isEngineRunning { try? session.activate(mode: .keepAlive) }
    }

    // MARK: - Lautstaerke-Rampe

    private func startGainRamp() {
        rampTimer?.invalidate()
        rampTimer = nil

        guard gentleWakeUp, gentleWakeUpDuration > 0 else {
            gate.setGain(targetVolume)
            return
        }

        let startGain = max(0.08, targetVolume * 0.12)
        let start = Date()
        gate.setGain(startGain)

        // Der Render-Block glaettet jeden Sprung ueber ~4 ms, deshalb reicht
        // eine grobe Aktualisierung zehnmal pro Sekunde.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let progress = min(1, Date().timeIntervalSince(start) / self.gentleWakeUpDuration)
                // Quadratisch: unten fein aufgeloest, oben zuegig.
                let eased = Float(progress * progress)
                self.gate.setGain(startGain + (self.targetVolume - startGain) * eased)
                if progress >= 1 {
                    self.rampTimer?.invalidate()
                    self.rampTimer = nil
                }
            }
        }
        rampTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Watchdog

    /// Zweite Verteidigungslinie: prueft die Route auch dann, wenn gar keine
    /// Benachrichtigung kam (z. B. nach einem Reset der Medien-Dienste).
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRinging || self.isTestPlaying else { return }
                if !AudioRouteMonitor.evaluateCurrentRoute().isSafeForAlarm {
                    self.gate.close()
                    AppLog.engine.error("WATCHDOG: unsichere Route erkannt - Wiedergabe gestoppt")
                    self.routeChanged(isSafe: false)
                }
            }
        }
        watchdogTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Engine-Graph

    private func buildAndStartEngine() throws {
        engine.stop()
        if let old = sourceNode {
            engine.detach(old)
            sourceNode = nil
        }

        let hardwareRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : (session.sampleRate > 0 ? session.sampleRate : 48_000)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw AudioEngineError.unsupportedFormat
        }

        let node = makeSourceNode(sampleRate: sampleRate, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        sourceNode = node

        engine.prepare()
        try engine.start()
        AppLog.engine.info("Engine gestartet bei \(Int(sampleRate), privacy: .public) Hz")
    }

    private func restartEngine() {
        guard isEngineRunning else { return }
        do {
            try buildAndStartEngine()
        } catch {
            AppLog.engine.error("Neustart der Engine fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recoverFromMediaServicesReset() {
        AppLog.engine.warning("Medien-Dienste zurueckgesetzt - Session und Engine werden neu aufgebaut")
        gate.close()
        engine = AVAudioEngine()
        sourceNode = nil
        installConfigurationObserver()
        guard isEngineRunning else { return }
        let wasRinging = isRinging
        isRinging = false
        startKeepAliveAfterReset()
        if wasRinging { startRinging() }
    }

    private func startKeepAliveAfterReset() {
        isEngineRunning = false
        startKeepAlive()
    }

    // MARK: - Ton-Synthese

    /// Unhoerbarer Traeger (~ -96 dBFS, ein LSB bei 16 Bit).
    ///
    /// Reine digitale Stille kann dazu fuehren, dass iOS die App trotz
    /// Hintergrund-Audio suspendiert. Ein minimaler Restpegel verhindert das,
    /// ohne im Ohr wahrnehmbar zu sein.
    private static let keepAliveAmplitude: Float = 1.0 / 32_768.0

    private func makeSourceNode(sampleRate: Double, format: AVAudioFormat) -> AVAudioSourceNode {
        let sr = Float(sampleRate)
        let gate = self.gate

        // Muster: drei aufsteigende Toene, dann Pause. Wiederholt sich alle 2 s.
        let cycleLength: Float = 2.0
        let beepSpacing: Float = 0.20
        let beepDuration: Float = 0.135
        let beepCount = 3
        let attack: Float = 0.008
        let release: Float = 0.030

        // Zeitkonstante ~4 ms: hoerbar sofort, aber ohne Knacken.
        let slew: Float = 1 - expf(-1 / (0.004 * sr))
        let twoPi = 2 * Float.pi
        let keepAliveIncrement = twoPi * 1_000 / sr
        let keepAliveAmplitude = Self.keepAliveAmplitude

        var phase: Float = 0
        var keepAlivePhase: Float = 0
        var patternTime: Float = 0
        var currentGain: Float = 0
        var lastBeepIndex = -1

        return AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Nicht-verschachteltes Float-Format: Puffer 0 ist der linke Kanal.
            guard let channel0 = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                isSilence.pointee = true
                return noErr
            }

            for frame in 0..<Int(frameCount) {
                // --- Huellkurve aus dem Wecktonmuster ---
                var envelope: Float = 0
                let beepIndex = Int(patternTime / beepSpacing)
                if beepIndex < beepCount {
                    let inBeep = patternTime - Float(beepIndex) * beepSpacing
                    if inBeep < beepDuration {
                        if beepIndex != lastBeepIndex {
                            // Jeder Ton startet bei Phase 0 -- zusammen mit der
                            // Einblendung verhindert das Knackser.
                            phase = 0
                            lastBeepIndex = beepIndex
                        }
                        if inBeep < attack {
                            envelope = inBeep / attack
                        } else if inBeep > beepDuration - release {
                            envelope = (beepDuration - inBeep) / release
                        } else {
                            envelope = 1
                        }
                        // Aufsteigender Dreiklang: A5 - C#6 - E6.
                        let frequency: Float = beepIndex == 0 ? 880 : (beepIndex == 1 ? 1_108.73 : 1_318.51)
                        phase += twoPi * frequency / sr
                        if phase >= twoPi { phase -= twoPi }
                    }
                }

                // --- Tor: wird pro Sample gelesen, damit der Not-Aus sofort greift ---
                currentGain += (gate.targetAmplitude - currentGain) * slew

                // Grundton plus Oktave gibt dem Signal Durchsetzungskraft,
                // ohne schrill zu werden.
                let tone = (sinf(phase) * 0.78 + sinf(phase * 2) * 0.22) * envelope

                keepAlivePhase += keepAliveIncrement
                if keepAlivePhase >= twoPi { keepAlivePhase -= twoPi }

                channel0[frame] = tone * currentGain + sinf(keepAlivePhase) * keepAliveAmplitude

                patternTime += 1 / sr
                if patternTime >= cycleLength { patternTime -= cycleLength }
            }

            // Mono-Signal auf die uebrigen Kanaele kopieren. `memcpy` ist
            // echtzeitsicher, eine Schleife ueber die Kanalliste je Frame waere
            // unnoetig teuer.
            if buffers.count > 1 {
                let byteCount = Int(frameCount) * MemoryLayout<Float>.size
                for index in 1..<buffers.count {
                    if let destination = buffers[index].mData {
                        memcpy(destination, channel0, byteCount)
                    }
                }
            }
            return noErr
        }
    }
}

enum AudioEngineError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Das Audioformat der Ausgabe wird nicht unterstuetzt."
        }
    }
}

/// Behaelter fuer Block-Observer (siehe `ObserverBag` im Route-Monitor).
private final class EngineObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []
    private var configurationToken: NSObjectProtocol?

    func add(_ token: NSObjectProtocol) {
        lock.lock()
        tokens.append(token)
        lock.unlock()
    }

    /// Meldet den bisherigen Konfigurations-Observer ab und merkt sich den neuen.
    func replaceConfigurationObserver(with token: NSObjectProtocol) {
        lock.lock()
        let previous = configurationToken
        configurationToken = token
        lock.unlock()
        if let previous { NotificationCenter.default.removeObserver(previous) }
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        if let configurationToken { NotificationCenter.default.removeObserver(configurationToken) }
    }
}
