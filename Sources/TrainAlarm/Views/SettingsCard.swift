import SwiftUI

/// Feineinstellungen.
struct SettingsCard: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var routeMonitor: AudioRouteMonitor
    @ObservedObject var notifications: NotificationManager
    let onSettingsChanged: () -> Void

    var body: some View {
        Card {
            CardTitle(text: "Einstellungen", systemImage: "slider.horizontal.3")

            toggle(
                title: "Sanftes Aufwachen",
                subtitle: "Der Weckton beginnt leise und wird ueber \(Int(settings.gentleWakeUpDuration)) Sekunden lauter.",
                isOn: Binding(
                    get: { settings.gentleWakeUp },
                    set: { settings.gentleWakeUp = $0; onSettingsChanged() }
                )
            )

            toggle(
                title: "USB-C-Headsets zulassen",
                subtitle: "iOS meldet USB-C-Kopfhoerer als \"USB-Audio\". Ausschalten, falls du dort auch Lautsprecher anschliesst.",
                isOn: Binding(
                    get: { settings.trustUSBAudio },
                    set: { settings.trustUSBAudio = $0; routeMonitor.refresh() }
                )
            )

            toggle(
                title: "Ton fuer Mitteilungen",
                subtitle: "Achtung: Mitteilungstoene steuert iOS selbst - sie koennen ueber den iPhone-Lautsprecher laufen.",
                isOn: Binding(
                    get: { settings.notificationSound },
                    set: { settings.notificationSound = $0 }
                ),
                tint: settings.notificationSound ? Theme.warning : Theme.accent
            )

            Divider().overlay(Theme.cardBorder)

            stepperRow(
                title: "Maximale Klingeldauer",
                value: Binding(
                    get: { settings.maxRingMinutes },
                    set: { settings.maxRingMinutes = $0 }
                ),
                range: 1...30,
                unit: "Min"
            )

            stepperRow(
                title: "Warten auf Kopfhoerer",
                value: Binding(
                    get: { settings.reconnectGraceMinutes },
                    set: { settings.reconnectGraceMinutes = $0 }
                ),
                range: 1...60,
                unit: "Min"
            )

            stepperRow(
                title: "Schlummerdauer",
                value: Binding(
                    get: { settings.snoozeMinutes },
                    set: { settings.snoozeMinutes = $0 }
                ),
                range: 1...30,
                unit: "Min"
            )

            if notifications.authorization == .denied {
                Text("Mitteilungen sind deaktiviert. Ohne sie faellt der sichtbare Hinweis weg, falls iOS die App beendet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle(title: String, subtitle: String, isOn: Binding<Bool>, tint: Color = Theme.accent) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(tint)
    }

    private func stepperRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        Stepper(value: value, in: range, step: 1) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
