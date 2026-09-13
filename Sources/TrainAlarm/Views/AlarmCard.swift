import SwiftUI

/// Weckzeit einstellen, Schnell-Timer, Scharfschalten.
struct AlarmCard: View {
    @ObservedObject var scheduler: AlarmScheduler
    @ObservedObject var routeMonitor: AudioRouteMonitor

    private static let quickTimers: [(label: String, minutes: Int)] = [
        ("+5 Min", 5),
        ("+15 Min", 15),
        ("+30 Min", 30),
        ("+45 Min", 45),
        ("+1 Std", 60),
        ("+2 Std", 120),
    ]

    var body: some View {
        Card {
            CardTitle(text: "Weckzeit", systemImage: "alarm")

            if scheduler.phase.isActive {
                activeState
            } else {
                picker
                quickTimerGrid
            }

            armButton
        }
    }

    // MARK: - Inaktiv

    private var picker: some View {
        DatePicker(
            "Weckzeit",
            selection: $scheduler.selectedTime,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .environment(\.locale, Locale(identifier: "de_DE"))
    }

    private var quickTimerGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Self.quickTimers, id: \.minutes) { timer in
                Button {
                    scheduler.arm(inMinutes: timer.minutes)
                } label: {
                    Text(timer.label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .foregroundStyle(Theme.primaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Aktiv

    private var activeState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(scheduler.fireTimeText ?? "--:--")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)

                if scheduler.phase == .snoozing {
                    Text("Schlummern")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.warningDim))
                        .foregroundStyle(Theme.warning)
                }
            }

            if let countdown = scheduler.countdownText {
                Label("in \(countdown)", systemImage: "hourglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            if scheduler.phase == .waitingForHeadphones {
                waitingBanner
            } else if !routeMonitor.safety.isSafeForAlarm {
                warningBanner(
                    icon: "exclamationmark.triangle.fill",
                    text: "Ohne Kopfhoerer bleibt der Wecker stumm. Verbinde sie rechtzeitig.",
                    tint: Theme.warning
                )
            } else {
                warningBanner(
                    icon: "checkmark.shield.fill",
                    text: "Bereit. Der Weckton laeuft ausschliesslich ueber die Kopfhoerer.",
                    tint: Theme.accent
                )
            }
        }
    }

    private var waitingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            warningBanner(
                icon: "exclamationmark.triangle.fill",
                text: "Weckzeit erreicht, aber keine Kopfhoerer. Es bleibt still - der Ton startet in dem Moment, in dem du sie verbindest.",
                tint: Theme.danger
            )
            if let wait = scheduler.waitCountdownText {
                Text("Wartefenster endet in \(wait)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func warningBanner(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }

    // MARK: - Hauptschalter

    private var armButton: some View {
        Button {
            if scheduler.phase.isActive {
                scheduler.disarm()
            } else {
                scheduler.arm()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: scheduler.phase.isActive ? "bell.slash.fill" : "bell.fill")
                Text(scheduler.phase.isActive ? "Wecker deaktivieren" : "Wecker aktivieren")
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(scheduler.phase.isActive ? Color.white.opacity(0.1) : Theme.accent)
            )
            .foregroundStyle(scheduler.phase.isActive ? Theme.primaryText : Color.black)
        }
        .buttonStyle(.plain)
    }
}
