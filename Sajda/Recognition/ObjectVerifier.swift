import CoreGraphics
import ImageIO
import Vision

/// Распознавание полностью на устройстве: Vision (Core ML) классификатор + сравнение с эталонным фото.
struct ObjectVerifier {
    enum Result: Equatable {
        case success(TaskKind)
        case tooDark, tooBright, uniform, blurry
        case screenOrPrint
        case notRecognized

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .success: return String(localized: "verify.success")
            case .tooDark: return String(localized: "verify.tooDark")
            case .tooBright: return String(localized: "verify.tooBright")
            case .uniform: return String(localized: "verify.uniform")
            case .blurry: return String(localized: "verify.blurry")
            case .screenOrPrint: return String(localized: "verify.screen")
            case .notRecognized: return String(localized: "verify.notRecognized")
            }
        }
    }

    var references: ReferenceStore = ReferenceStore()
    var matcher = LabelMatcher()

    func verify(_ image: CGImage, orientation: CGImagePropertyOrientation, task: TaskKind) async -> Result {
        await Task.detached(priority: .userInitiated) {
            self.verifySync(image, orientation: orientation, task: task)
        }.value
    }

    private func verifySync(_ image: CGImage, orientation: CGImagePropertyOrientation, task: TaskKind) -> Result {
        guard let quality = ImageQuality.analyze(image) else { return .notRecognized }
        switch quality.issue {
        case .tooDark: return .tooDark
        case .tooBright: return .tooBright
        case .uniform: return .uniform
        case .blurry: return .blurry
        case nil: break
        }

        let labels = classify(image, orientation: orientation)
        let decision = matcher.decide(labels: labels, task: task)
        switch decision {
        case .screenOrPrint:
            return .screenOrPrint
        case .match(let kind):
            return .success(kind)
        case .noMatch:
            // Эталонное фото своего коврика/раковины позволяет засчитать нестандартный объект.
            let kinds: [TaskKind] = task == .any ? [.rug, .sink] : [task]
            for kind in kinds where references.matches(image, orientation: orientation, kind: kind) {
                return .success(kind)
            }
            return .notRecognized
        }
    }

    private func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [LabelMatcher.Label] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).map {
            LabelMatcher.Label(identifier: $0.identifier, confidence: Double($0.confidence))
        }
    }
}
