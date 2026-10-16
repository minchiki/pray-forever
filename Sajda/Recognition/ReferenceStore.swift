import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Эталонные фото «своего» коврика и раковины. Сравнение через Vision feature print, без сети.
struct ReferenceStore {
    /// Пороги расстояния между feature print: ревизия 2 (iOS 17+) нормирована, ревизия 1 — нет.
    static let thresholdRevision2: Float = 0.62
    static let thresholdRevision1: Float = 14
    static let maxSide = 1024

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("references", isDirectory: true)
    }

    private func url(for kind: TaskKind) -> URL {
        directory.appendingPathComponent("\(kind.rawValue).jpg")
    }

    func hasReference(_ kind: TaskKind) -> Bool {
        FileManager.default.fileExists(atPath: url(for: kind).path)
    }

    func save(_ image: CGImage, kind: TaskKind) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url(for: kind) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(target, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    func remove(_ kind: TaskKind) {
        try? FileManager.default.removeItem(at: url(for: kind))
    }

    func matches(_ image: CGImage, orientation: CGImagePropertyOrientation, kind: TaskKind) -> Bool {
        guard let reference = load(kind),
              let refPrint = featurePrint(reference, orientation: .up),
              let photoPrint = featurePrint(image, orientation: orientation) else { return false }
        var distance: Float = .greatestFiniteMagnitude
        guard (try? photoPrint.computeDistance(&distance, to: refPrint)) != nil else { return false }
        let threshold = refPrint.requestRevision >= 2 ? Self.thresholdRevision2 : Self.thresholdRevision1
        return distance <= threshold
    }

    private func load(_ kind: TaskKind) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: kind) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func featurePrint(_ image: CGImage, orientation: CGImagePropertyOrientation) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }
}
