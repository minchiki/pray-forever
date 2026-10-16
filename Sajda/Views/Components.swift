import SwiftUI
import UIKit

enum Theme {
    static let cornerRadius: CGFloat = 20
    static let card = Color(.secondarySystemGroupedBackground)
    static let background = Color(.systemGroupedBackground)
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

enum Countdown {
    private static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .short
        f.allowedUnits = [.hour, .minute]
        f.zeroFormattingBehavior = .dropLeading
        return f
    }()

    private static let secondsFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .short
        f.allowedUnits = [.second]
        return f
    }()

    static func string(from now: Date, to target: Date) -> String {
        let interval = max(0, target.timeIntervalSince(now))
        let formatter = interval < 60 ? secondsFormatter : formatter
        let value = formatter.string(from: interval < 60 ? interval : interval + 59) ?? ""
        return String(format: String(localized: "common.in"), value)
    }
}

/// Кнопка аварийного отключения: нужно удерживать несколько секунд.
struct HoldToStopButton: View {
    let holdDuration: Double
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isHolding { begin() } }
                    .onEnded { _ in cancel() }
            )
            Text("emergency.hold \(Int(holdDuration))")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func begin() {
        isHolding = true
        let start = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            let value = Date().timeIntervalSince(start) / holdDuration
            progress = min(1, value)
            if value >= 1 {
                t.invalidate()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                action()
            }
        }
    }

    private func cancel() {
        isHolding = false
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

/// Крупная круглая кнопка затвора.
struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 5).frame(width: 84, height: 84)
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Circle().fill(Color.white).frame(width: 68, height: 68)
                }
            }
        }
        .disabled(isBusy)
        .accessibilityLabel(Text("camera.shutter"))
    }
}
