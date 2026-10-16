import SwiftUI

/// Эталонные фото: распознавание надёжнее узнаёт именно ваш коврик/раковину.
struct ReferencePhotosView: View {
    @State private var capturing: TaskKind?
    @State private var refreshID = UUID()
    private let references = ReferenceStore()

    var body: some View {
        Form {
            Section {
                ForEach([TaskKind.rug, .sink]) { kind in
                    row(kind)
                }
            } footer: {
                Text("references.footer")
            }
        }
        .id(refreshID)
        .navigationTitle(Text("settings.references"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $capturing) { kind in
            ReferenceCaptureView(kind: kind) {
                capturing = nil
                refreshID = UUID()
            }
        }
    }

    private func row(_ kind: TaskKind) -> some View {
        let saved = references.hasReference(kind)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.localizedName)
                Text(saved ? LocalizedStringKey("references.saved") : LocalizedStringKey("references.none"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if saved {
                Button(role: .destructive) {
                    references.remove(kind)
                    refreshID = UUID()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("common.delete"))
            }
            Button(saved ? LocalizedStringKey("references.retake") : LocalizedStringKey("references.take")) {
                capturing = kind
            }
                .buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
    }
}

private struct ReferenceCaptureView: View {
    let kind: TaskKind
    let close: () -> Void

    @StateObject private var camera = CameraController()
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.state == .denied {
                Text("camera.denied").foregroundStyle(.white).padding(32)
            } else {
                CameraPreview(session: camera.session).ignoresSafeArea()
            }
            VStack {
                HStack {
                    Button("common.cancel", action: close)
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                    Spacer()
                }
                .padding(.horizontal, 20)
                Text(kind.instruction)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
                if let error {
                    Text(error)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
                ShutterButton(isBusy: isBusy, action: capture)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func capture() {
        isBusy = true
        error = nil
        camera.capture { image in
            defer { isBusy = false }
            guard let image else { return }
            if let issue = ImageQuality.analyze(image)?.issue {
                error = Self.message(for: issue)
                return
            }
            do {
                try ReferenceStore().save(image, kind: kind)
                close()
            } catch {
                self.error = String(localized: "references.saveError")
            }
        }
    }

    private static func message(for issue: ImageQuality.Issue) -> String {
        switch issue {
        case .tooDark: return ObjectVerifier.Result.tooDark.message
        case .tooBright: return ObjectVerifier.Result.tooBright.message
        case .uniform: return ObjectVerifier.Result.uniform.message
        case .blurry: return ObjectVerifier.Result.blurry.message
        }
    }
}
