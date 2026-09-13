import SwiftUI

/// Lautstaerke des Wecktons und Probelauf ueber die Kopfhoerer.
struct SoundCard: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: AlarmAudioEngine
    @ObservedObject var routeMonitor: AudioRouteMonitor
    let onSettingsChanged: () -> Void

    private var canTest: Bool {
        routeMonitor.safety.isSafeForAlarm && !engine.isRinging
    }

    var body: some View {
        Card {
            CardTitle(text: "Weckton", systemImage: "waveform")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Lautstaerke")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text("\(Int(settings.volume * 100)) %")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }

                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                    Slider(
                        value: Binding(
                            get: { settings.volume },
                            set: { settings.volume = $0; onSettingsChanged() }
                        ),
                        in: 0.1...1.0
                    )
                    .tint(Theme.accent)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Button {
                if engine.isTestPlaying {
                    engine.stopTestTone()
                } else {
                    engine.apply(settings: settings)
                    engine.playTestTone()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: engine.isTestPlaying ? "stop.fill" : "play.fill")
                    Text(engine.isTestPlaying ? "Testton stoppen" : "Testton abspielen")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(canTest || engine.isTestPlaying ? Theme.accentDim : Color.white.opacity(0.05))
                )
                .foregroundStyle(canTest || engine.isTestPlaying ? Theme.accent : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(!canTest && !engine.isTestPlaying)

            if !canTest && !engine.isTestPlaying {
                Text("Testton nur mit verbundenen Kopfhoerern - auch hier weicht die App nicht auf den Lautsprecher aus.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
