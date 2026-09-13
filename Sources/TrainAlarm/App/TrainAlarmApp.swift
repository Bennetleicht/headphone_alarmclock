import SwiftUI

@main
struct TrainAlarmApp: App {

    @StateObject private var settings: SettingsStore
    @StateObject private var routeMonitor: AudioRouteMonitor
    @StateObject private var engine: AlarmAudioEngine
    @StateObject private var notifications: NotificationManager
    @StateObject private var scheduler: AlarmScheduler

    init() {
        let settings = SettingsStore()
        let routeMonitor = AudioRouteMonitor()
        let engine = AlarmAudioEngine()
        let notifications = NotificationManager()
        let scheduler = AlarmScheduler(
            engine: engine,
            routeMonitor: routeMonitor,
            notifications: notifications,
            settings: settings
        )

        _settings = StateObject(wrappedValue: settings)
        _routeMonitor = StateObject(wrappedValue: routeMonitor)
        _engine = StateObject(wrappedValue: engine)
        _notifications = StateObject(wrappedValue: notifications)
        _scheduler = StateObject(wrappedValue: scheduler)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(routeMonitor)
                .environmentObject(engine)
                .environmentObject(notifications)
                .environmentObject(scheduler)
                .onAppear {
                    // Die Route beim Erscheinen frisch einlesen: waehrend die App
                    // im Hintergrund war, kann sich einiges geaendert haben.
                    routeMonitor.refresh()
                    engine.apply(settings: settings)
                }
        }
    }
}
