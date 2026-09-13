import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var routeMonitor: AudioRouteMonitor
    @EnvironmentObject private var engine: AlarmAudioEngine
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var scheduler: AlarmScheduler

    private var showsOverlay: Bool {
        scheduler.phase == .ringing || scheduler.phase == .waitingForHeadphones
    }

    var body: some View {
        ZStack {
            Theme.screenGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    HeadphoneStatusCard(routeMonitor: routeMonitor)
                    AlarmCard(scheduler: scheduler, routeMonitor: routeMonitor)
                    SoundCard(
                        settings: settings,
                        engine: engine,
                        routeMonitor: routeMonitor,
                        onSettingsChanged: { scheduler.settingsChanged() }
                    )
                    SettingsCard(
                        settings: settings,
                        routeMonitor: routeMonitor,
                        notifications: notifications,
                        onSettingsChanged: { scheduler.settingsChanged() }
                    )
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }

            if showsOverlay {
                RingingOverlay(scheduler: scheduler, routeMonitor: routeMonitor)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsOverlay)
        .preferredColorScheme(.dark)
        .task {
            await notifications.refreshAuthorization()
            if notifications.authorization == .unknown {
                await notifications.requestAuthorization()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("TrainAlarm")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
            }
            Text("Weckt nur ueber Kopfhoerer. Nie ueber den Lautsprecher.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if engine.isEngineRunning {
                Label("Hintergrundbetrieb aktiv", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent.opacity(0.85))
            }
            if let trip = engine.lastFailsafeTrip {
                Label(
                    "Failsafe zuletzt ausgeloest um \(trip.formatted(date: .omitted, time: .standard))",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.top, 6)
    }
}
