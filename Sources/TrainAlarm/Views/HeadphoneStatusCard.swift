import SwiftUI

/// Die grosse Live-Statusanzeige: Ist die Ausgabe gerade privat?
struct HeadphoneStatusCard: View {
    @ObservedObject var routeMonitor: AudioRouteMonitor
    @State private var pulse = false

    private var isSafe: Bool { routeMonitor.safety.isSafeForAlarm }
    private var tint: Color { isSafe ? Theme.accent : Theme.danger }
    private var tintDim: Color { isSafe ? Theme.accentDim : Theme.dangerDim }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(tintDim)
                        .frame(width: 62, height: 62)
                    Circle()
                        .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 62, height: 62)
                        .scaleEffect(pulse && !isSafe ? 1.18 : 1.0)
                        .opacity(pulse && !isSafe ? 0 : 1)
                    Image(systemName: routeMonitor.symbolName)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(isSafe ? "Kopfhoerer verbunden" : "Nicht bereit")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(tint)

                    Text(routeMonitor.headline)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }

            Text(routeMonitor.detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if routeMonitor.safety.outputs.count > 1 {
                // Mehrere gleichzeitige Ausgaben: dann muss jede einzelne
                // privat sein, sonst laeuft der Ton parallel im Raum.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(routeMonitor.safety.outputs) { output in
                        HStack(spacing: 8) {
                            Image(systemName: output.classification.symbolName)
                                .font(.system(size: 11))
                                .frame(width: 16)
                            Text("\(output.name) - \(output.classification.germanLabel)")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            SystemVolumeHint(volume: routeMonitor.systemVolume, isSafe: isSafe)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(tintDim.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1.2)
        )
        .animation(.easeInOut(duration: 0.25), value: isSafe)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

/// Warnt, wenn die Hardware-Lautstaerke so niedrig steht, dass der Weckton
/// untergehen wuerde. Die App kann die Systemlautstaerke nicht selbst setzen --
/// aber sie kann darauf hinweisen.
private struct SystemVolumeHint: View {
    let volume: Float
    let isSafe: Bool

    private var isTooQuiet: Bool { isSafe && volume < 0.25 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isTooQuiet ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                .font(.system(size: 11))
            Text("Systemlautstaerke \(Int(volume * 100)) %"
                 + (isTooQuiet ? " - zu leise zum Wecken" : ""))
                .font(.system(size: 12, weight: isTooQuiet ? .semibold : .regular))
        }
        .foregroundStyle(isTooQuiet ? Theme.warning : Theme.tertiaryText)
    }
}
