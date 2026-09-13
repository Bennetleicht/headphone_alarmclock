import SwiftUI

/// Vollbild-Ansicht waehrend des Weckens -- und waehrend des Wartens auf
/// Kopfhoerer, damit sofort klar ist, warum es still bleibt.
struct RingingOverlay: View {
    @ObservedObject var scheduler: AlarmScheduler
    @ObservedObject var routeMonitor: AudioRouteMonitor

    @State private var pulse = false

    private var isWaiting: Bool { scheduler.phase == .waitingForHeadphones }
    private var tint: Color { isWaiting ? Theme.danger : Theme.accent }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(
                colors: [tint.opacity(0.28), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )
            .ignoresSafeArea()
            .scaleEffect(pulse ? 1.12 : 0.94)

            VStack(spacing: 26) {
                Spacer()

                Image(systemName: isWaiting ? "headphones" : "alarm.fill")
                    .font(.system(size: 74, weight: .light))
                    .foregroundStyle(tint)
                    .scaleEffect(pulse ? 1.06 : 0.96)

                VStack(spacing: 10) {
                    Text(isWaiting ? "Wecker wartet" : "Aufwachen!")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)

                    Text(scheduler.fireTimeText ?? "")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(message)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isWaiting ? Theme.danger : Theme.secondaryText)
                    .padding(.horizontal, 34)
                    .fixedSize(horizontal: false, vertical: true)

                if isWaiting, let wait = scheduler.waitCountdownText {
                    Text("Wartefenster endet in \(wait)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        scheduler.snooze()
                    } label: {
                        Text("Schlummern")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .foregroundStyle(Theme.primaryText)
                    }
                    .buttonStyle(.plain)

                    Button {
                        scheduler.stopAndDisarm()
                    } label: {
                        Text("Wecker beenden")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(tint)
                            )
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var message: String {
        if isWaiting {
            return "Keine Kopfhoerer verbunden. TrainAlarm weicht bewusst nicht auf den iPhone-Lautsprecher aus - verbinde die Kopfhoerer, dann klingelt es sofort."
        }
        if let output = routeMonitor.safety.primaryOutput {
            return "Der Weckton laeuft ueber \(output.name)."
        }
        return "Der Weckton laeuft ueber deine Kopfhoerer."
    }
}
