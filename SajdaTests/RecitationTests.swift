import XCTest
@testable import Sajda

final class ArabicTextTests: XCTestCase {
    func testNormalizeStripsDiacriticsAndUnifiesLetters() {
        XCTAssertEqual(ArabicText.normalize("الرَّحْمَٰنِ"), "الرحمن")
        XCTAssertEqual(ArabicText.normalize("إِلَٰهِ"), "اله")
        XCTAssertEqual(ArabicText.normalize("أَحَدٌ"), "احد")
        XCTAssertEqual(ArabicText.normalize("الْجِنَّةِ"), "الجنه")
    }

    func testWordsSplitOnSpacesAndPunctuation() {
        XCTAssertEqual(ArabicText.words("قُلْ هُوَ، اللَّهُ  أَحَدٌ."), ["قل", "هو", "الله", "احد"])
    }

    func testFuzzyMatchToleratesSmallRecognitionErrors() {
        XCTAssertTrue(ArabicText.matches("ملك", ArabicText.normalize("مَالِكِ")))
        XCTAssertTrue(ArabicText.matches("رحيم", ArabicText.normalize("الرَّحِيمِ")))
    }

    func testFuzzyMatchRejectsDifferentWords() {
        XCTAssertFalse(ArabicText.matches("لن", "لم"))
        XCTAssertFalse(ArabicText.matches("الفلق", "الناس"))
        XCTAssertFalse(ArabicText.matches("الخناس", "الوسواس"))
    }
}

final class SurahTests: XCTestCase {
    func testAyahCountsMatchMushaf() {
        let expected: [Surah: Int] = [.fatiha: 7, .ikhlas: 4, .falaq: 5, .nas: 6, .kawthar: 3, .asr: 3, .kafirun: 6]
        for surah in Surah.allCases {
            XCTAssertEqual(surah.ayat.count, expected[surah], surah.rawValue)
            XCTAssertEqual(surah.ayat.map(\.number), Array(1...surah.ayat.count), surah.rawValue)
        }
    }

    func testEveryWordHasTextAndTransliteration() {
        for surah in Surah.allCases {
            let tracker = RecitationTracker(surah: surah)
            XCTAssertFalse(tracker.words.isEmpty)
            XCTAssertTrue(tracker.words.allSatisfy { !$0.key.isEmpty }, surah.rawValue)
            XCTAssertTrue(surah.ayat.allSatisfy { !$0.latin.isEmpty && !$0.cyrillic.isEmpty }, surah.rawValue)
        }
    }

    func testRecitationChoice() {
        XCTAssertNil(RecitationChoice.off.pick())
        XCTAssertNotNil(RecitationChoice.random.pick())
        XCTAssertEqual(RecitationChoice.nas.pick(), .nas)
    }

    func testOldSettingsDecodeWithRecitationDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"delayMinutes": 7}"#.utf8))
        XCTAssertEqual(settings.recitation, .fatiha)
        XCTAssertEqual(settings.delayMinutes, 7)
    }

    func testEverySoundFileIsBundled() {
        let bundle = Bundle(for: AlarmCoordinator.self)
        for sound in AlarmSound.allCases {
            XCTAssertNotNil(bundle.url(forResource: sound.fileName, withExtension: nil), sound.fileName)
        }
    }
}

final class RecitationTrackerTests: XCTestCase {
    func testFullRecitationCompletes() {
        var tracker = RecitationTracker(surah: .ikhlas)

        tracker.hear("قل هو الله احد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احد")

        XCTAssertTrue(tracker.isComplete)
        XCTAssertTrue(tracker.skipped.isEmpty)
    }

    func testUnrelatedSpeechDoesNotAdvance() {
        var tracker = RecitationTracker(surah: .ikhlas)

        XCTAssertFalse(tracker.hear("مرحبا كيف حالك"))
        XCTAssertEqual(tracker.position, 0)
    }

    func testMissedWordIsSkippedAndMarked() {
        var tracker = RecitationTracker(surah: .nas)

        tracker.hear("قل اعوذ برب الناس ملك الناس اله الناس من شر الخناس الذي يوسوس في صدور الناس من الجنه والناس")

        XCTAssertTrue(tracker.isComplete)
        XCTAssertEqual(tracker.skipped, [10])
        XCTAssertEqual(tracker.state(of: 10), .skipped)
    }

    func testFatihaMayStartWithoutBasmala() {
        var tracker = RecitationTracker(surah: .fatiha)

        tracker.hear("الحمد لله رب العالمين")

        XCTAssertEqual(tracker.position, 8)
        XCTAssertEqual(tracker.currentAyah, 2)
        XCTAssertTrue(tracker.skipped.isEmpty)
    }

    func testNewRecognitionSessionContinuesFromPosition() {
        var tracker = RecitationTracker(surah: .ikhlas)

        tracker.hear("قل هو الله احد")
        tracker.beginSession()
        tracker.hear("الله الصمد")

        XCTAssertEqual(tracker.position, 6)
        XCTAssertEqual(tracker.currentAyah, 2)
    }

    func testPacedModeCountsWordsByVoiceTime() {
        var tracker = RecitationTracker(surah: .kawthar)

        tracker.tick(RecitationTracker.pacedSecondsPerWord, voiceActive: true, paced: true)
        XCTAssertEqual(tracker.position, 1)

        tracker.tick(5, voiceActive: false, paced: true)
        XCTAssertEqual(tracker.position, 1)
        XCTAssertTrue(tracker.skipped.isEmpty)
    }

    func testSilenceTriggersFailure() {
        var tracker = RecitationTracker(surah: .asr)

        tracker.tick(RecitationTracker.silenceLimit - 1, voiceActive: false, paced: false)
        XCTAssertFalse(tracker.isSilentTooLong)
        tracker.tick(1, voiceActive: false, paced: false)
        XCTAssertTrue(tracker.isSilentTooLong)
    }

    func testStuckWordIsSkippedAfterLongVoiceAndOldTextIsNotReused() {
        var tracker = RecitationTracker(surah: .ikhlas)
        tracker.hear("قل")

        tracker.tick(RecitationTracker.stuckVoiceLimit, voiceActive: true, paced: false)
        XCTAssertEqual(tracker.position, 2)
        XCTAssertEqual(tracker.skipped, [1])

        tracker.hear("قل الله")
        XCTAssertEqual(tracker.position, 3)
    }
}

final class VoiceActivityDetectorTests: XCTestCase {
    func testLoudSoundOverQuietBackgroundIsVoice() {
        var detector = VoiceActivityDetector()
        for _ in 0..<10 { XCTAssertFalse(detector.process(levelDB: -60, duration: 0.02)) }

        XCTAssertTrue(detector.process(levelDB: -30, duration: 0.02))

        for _ in 0..<30 { _ = detector.process(levelDB: -60, duration: 0.02) }
        XCTAssertFalse(detector.isActive)
    }
}
