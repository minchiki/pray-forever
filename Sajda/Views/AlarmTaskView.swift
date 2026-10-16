import SwiftUI

/// Полноэкранное задание: звук играет, пока камера не распознает коврик или раковину.
struct AlarmTaskView: View {
    let alarm: AlarmInstance

    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @StateObject private var camera = CameraController()

    @State private var isVerifying = false
    @State private var result: ObjectVerifier.Result?
    @State private var showEmergency = false

    private let verifier = ObjectVerifier()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer
            VStack(spacing: 0) {
                header
                Spacer()
                if let result, !result.isSuccess { failureBanner(result) }
                controls
            }
            if result?.isSuccess == true { successOverlay }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showEmergency) { emergencySheet }
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.state {
        case .running, .idle:
            CameraPreview(session: camera.session).ignoresSafeArea()
        case .denied:
            messageLayer(icon: "camera.fill", text: "camera.denied", showSettings: true)
        case .unavailable:
            messageLayer(icon: "camera.fill", text: "camera.unavailable", showSettings: false)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(alarm.isTest ? String(localized: "alarm.test") : alarm.prayer.localizedName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(store.settings.task.instruction)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var controls: some View {
        VStack(spacing: 18) {
            ShutterButton(isBusy: isVerifying, action: capture)
                .disabled(camera.state != .running)
            Button { showEmergency = true } label: {
                Text("emergency.button")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(minHeight: 44)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func failureBanner(_ result: ObjectVerifier.Result) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.message).font(.headline)
                Text("verify.retry").font(.subheadline).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72))
            Text("verify.success").font(.title2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7).ignoresSafeArea())
        .transition(.opacity)
    }

    private func messageLayer(icon: String, text: LocalizedStringKey, showSettings: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44))
            Text(text).multilineTextAlignment(.center)
            if showSettings {
                Button("common.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private var emergencySheet: some View {
        VStack(spacing: 20) {
            Text("emergency.title").font(.title2.weight(.semibold))
            Text("emergency.body")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            HoldToStopButton {
                showEmergency = false
                coordinator.emergencyStop()
            }
            .padding(.top, 8)
            Button("common.cancel") { showEmergency = false }
                .foregroundStyle(.white)
                .frame(minHeight: 44)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.1).ignoresSafeArea())
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func capture() {
        isVerifying = true
        withAnimation { result = nil }
        camera.capture { image in
            guard let image else {
                isVerifying = false
                withAnimation { result = .notRecognized }
                return
            }
            Task {
                let outcome = await verifier.verify(image, orientation: .up, task: store.settings.task)
                isVerifying = false
                withAnimation { result = outcome }
                if outcome.isSuccess {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    coordinator.completeTask()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
