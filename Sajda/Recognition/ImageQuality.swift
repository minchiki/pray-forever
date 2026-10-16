import CoreGraphics
import Foundation

/// Быстрые проверки кадра до распознавания: чёрный экран, засвет, закрытый объектив, смаз.
struct ImageQuality: Equatable {
    enum Issue: Equatable { case tooDark, tooBright, uniform, blurry }

    static let sampleSize = 96
    static let minMean = 0.10
    static let maxMean = 0.96
    static let minStdDev = 0.035
    static let minSharpness = 0.00035

    let mean: Double
    let stdDev: Double
    /// Дисперсия лапласиана (нормализованная, 0...1 шкала яркости).
    let sharpness: Double

    var issue: Issue? {
        if mean < Self.minMean { return .tooDark }
        if mean > Self.maxMean { return .tooBright }
        if stdDev < Self.minStdDev { return .uniform }
        if sharpness < Self.minSharpness { return .blurry }
        return nil
    }

    /// - Parameter gray: яркость пикселей 0...255, построчно, размер width*height.
    init(gray: [UInt8], width: Int, height: Int) {
        precondition(gray.count == width * height && width > 2 && height > 2)
        let values = gray.map { Double($0) / 255 }
        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count

        var lap: [Double] = []
        lap.reserveCapacity((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let v = values[i - width] + values[i + width] + values[i - 1] + values[i + 1] - 4 * values[i]
                lap.append(v)
            }
        }
        let lapMean = lap.reduce(0, +) / Double(lap.count)
        let lapVar = lap.reduce(0) { $0 + ($1 - lapMean) * ($1 - lapMean) } / Double(lap.count)

        self.mean = mean
        self.stdDev = variance.squareRoot()
        self.sharpness = lapVar
    }

    static func analyze(_ image: CGImage) -> ImageQuality? {
        let size = sampleSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        return ImageQuality(gray: pixels, width: size, height: size)
    }
}
