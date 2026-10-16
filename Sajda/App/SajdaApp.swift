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
        .fullScreenCover(item: Binding(get: { overlay }, set: { _ in })) { overlay in
            Group {
                switch overlay {
                case .alarm(let alarm): AlarmTaskView(alarm: alarm)
                case .wakeCheck(let check): WakeCheckView(check: check)
                }
            }
            .environmentObject(coordinator)
            .environmentObject(store)
            .interactiveDismissDisabled()
        }
    }

    /// Звонящий будильник важнее проверки «не уснул».
    private var overlay: Overlay? {
        if let alarm = coordinator.activeAlarm { return .alarm(alarm) }
        if let check = coordinator.wakeCheck { return .wakeCheck(check) }
        return nil
    }

    private enum Overlay: Identifiable {
        case alarm(AlarmInstance)
        case wakeCheck(AlarmInstance)

        var id: String {
            switch self {
            case .alarm(let alarm): return "alarm-\(alarm.id)"
            case .wakeCheck(let check): return "check-\(check.id)"
            }
        }
    }
}
