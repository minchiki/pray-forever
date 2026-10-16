import SwiftUI

/// «Вы не спите?» — через 5 минут после задания. Не нажал за минуту — будильник звонит снова.
struct WakeCheckView: View {
    let check: AlarmInstance
    @EnvironmentObject private var coordinator: AlarmCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(check.alarmTime.timeIntervalSince(context.date).rounded(.up)))
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "eye.fill")
                    .font(.system(size: 56))
                Text("wake.title")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("wake.body")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .opacity(0.8)
                Text("\(remaining)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Button(action: coordinator.confirmAwake) {
                    Text("wake.confirm")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(.white)
                .foregroundStyle(.black)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
    }
}

/// Изменение настроек, которое ослабляет будильник и требует испытания.
struct GuardedChange: Identifiable {
    let id = UUID()
    let apply: () -> Void
}

extension View {
    /// Показывает испытание из 10 раундов перед применением защищённого изменения.
    func guardedChallenge(_ pending: Binding<GuardedChange?>) -> some View {
        fullScreenCover(item: pending) { change in
            ChallengeGameView(
                onComplete: {
                    change.apply()
                    pending.wrappedValue = nil
                },
                onCancel: { pending.wrappedValue = nil }
            )
        }
    }
}

extension AlarmCoordinator {
    /// Применяет изменение сразу или требует испытания, если оно ослабляет близкий будильник.
    func perform(weakening: Bool, pending: Binding<GuardedChange?>, _ change: @escaping () -> Void) {
        if weakening && changesLocked {
            pending.wrappedValue = GuardedChange(apply: change)
        } else {
            change()
        }
    }
}
