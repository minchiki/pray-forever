import XCTest
@testable import Sajda

final class LabelMatcherTests: XCTestCase {
    private let matcher = LabelMatcher()

    private func labels(_ pairs: [(String, Double)]) -> [LabelMatcher.Label] {
        pairs.map { LabelMatcher.Label(identifier: $0.0, confidence: $0.1) }
    }

    func testRugIsRecognized() {
        let result = matcher.decide(labels: labels([("rug", 0.72), ("textile", 0.4), ("floor", 0.3)]), task: .rug)
        XCTAssertEqual(result, .match(.rug))
    }

    func testSinkIsRecognized() {
        let result = matcher.decide(labels: labels([("bathroom_faucet", 0.5), ("sink", 0.61)]), task: .sink)
        XCTAssertEqual(result, .match(.sink))
    }

    func testAnyTaskPicksBestKind() {
        let result = matcher.decide(labels: labels([("sink", 0.8), ("textile", 0.1)]), task: .any)
        XCTAssertEqual(result, .match(.sink))
    }

    func testWrongObjectForSelectedTaskIsRejected() {
        let result = matcher.decide(labels: labels([("sink", 0.9)]), task: .rug)
        XCTAssertEqual(result, .noMatch)
    }

    func testUnrelatedPhotoIsRejected() {
        let result = matcher.decide(labels: labels([("dog", 0.9), ("grass", 0.6), ("sky", 0.5)]), task: .any)
        XCTAssertEqual(result, .noMatch)
    }

    func testPhotoOfScreenIsRejected() {
        let result = matcher.decide(labels: labels([("rug", 0.6), ("computer_monitor", 0.7)]), task: .rug)
        XCTAssertEqual(result, .screenOrPrint)
    }

    func testWeakTextileLabelsAloneAreNotEnough() {
        let result = matcher.decide(labels: labels([("textile", 0.3), ("pattern", 0.2)]), task: .rug)
        XCTAssertEqual(result, .noMatch)
    }

    func testTokenMatchingIsWholeWord() {
        XCTAssertFalse(LabelMatcher.matches("automatic", ["mat"]))
        XCTAssertTrue(LabelMatcher.matches("prayer_rug", ["rug"]))
        XCTAssertTrue(LabelMatcher.matches("Carpets", ["carpet"]))
    }
}

final class ImageQualityTests: XCTestCase {
    private let size = 32

    private func image(_ value: (Int, Int) -> UInt8) -> ImageQuality {
        let pixels = (0..<size).flatMap { y in (0..<size).map { x in value(x, y) } }
        return ImageQuality(gray: pixels, width: size, height: size)
    }

    func testBlackFrameIsTooDark() {
        XCTAssertEqual(image { _, _ in 3 }.issue, .tooDark)
    }

    func testWhiteFrameIsTooBright() {
        XCTAssertEqual(image { _, _ in 252 }.issue, .tooBright)
    }

    func testFlatGrayFrameIsUniform() {
        XCTAssertEqual(image { _, _ in 128 }.issue, .uniform)
    }

    func testSmoothGradientIsBlurry() {
        let quality = image { x, _ in UInt8(60 + x * 4) }
        XCTAssertEqual(quality.issue, .blurry)
    }

    func testDetailedFrameIsAccepted() {
        let quality = image { x, y in ((x / 2 + y / 2) % 2 == 0) ? 40 : 210 }
        XCTAssertNil(quality.issue)
    }
}
