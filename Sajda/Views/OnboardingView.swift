import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 24)
            Image("RugMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("app.name").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("onboarding.subtitle").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 20) {
                point(icon: "location", title: "onboarding.p1.title", text: "onboarding.p1.text")
                point(icon: "alarm", title: "onboarding.p2.title", text: "onboarding.p2.text")
                point(icon: "camera", title: "onboarding.p3.title", text: "onboarding.p3.text")
            }
            Spacer()
            Button(action: start) {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text("onboarding.start").font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(isWorking)
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
    }

    private func point(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        isWorking = true
        Task {
            await coordinator.requestPermissions()
            await coordinator.updateLocation()
            store.hasOnboarded = true
            isWorking = false
        }
    }
}
