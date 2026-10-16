import SwiftUI

@main
struct SajdaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var coordinator = AlarmCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.store)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: coordinator.appBecameActive()
            case .background: AlarmCoordinator.scheduleBackgroundRefresh()
            default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Group {
            if store.hasOnboarded {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .onChange(of: store.settings) { _ in coordinator.settingsChanged() }
        .fullScreenCover(item: Binding(get: { coordinator.activeAlarm }, set: { _ in })) { alarm in
            AlarmTaskView(alarm: alarm)
                .environmentObject(coordinator)
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
    }
}
