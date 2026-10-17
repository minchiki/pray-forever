import XCTest
@testable import Sajda

final class ArabicTextTests: XCTestCase {
    func testNormalizeStripsDiacriticsAndUnifiesLetters() {
        XCTAssertEqual(ArabicText.normalize("الرَّحْمَٰنِ"), "الرحمن")
        XCTAssertEqual(ArabicText.normalize("إِلَٰهِ"), "اله")
        XCTAssertEqual(ArabicText.normalize("أَحَدٌ"), "احد")
        XCTAssertEqual(ArabicText.normalize("الْجِنَّةِ"), "الجنه")
    }

    func testStripDiacriticsKeepsLetters() {
        XCTAssertEqual(ArabicText.stripDiacritics("الْجِنَّةِ وَالنَّاسِ"), "الجنة والناس")
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

    func testEveryWordHasItsOwnTransliteration() {
        for surah in Surah.allCases {
            for ayah in surah.ayat + [Surah.basmala] {
                let words = ayah.arabic.split(separator: " ").count
                XCTAssertEqual(ayah.latin.split(separator: " ").count, words, "\(surah.rawValue) \(ayah.number)")
                XCTAssertEqual(ayah.cyrillic.split(separator: " ").count, words, "\(surah.rawValue) \(ayah.number)")
            }
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

    func testSeveralMissedWordsDoNotBreakAlignment() {
        var tracker = RecitationTracker(surah: .asr)

        tracker.hear("والعصر ان الانسان لفي خسر الا الذين بالحق وتواصوا بالصبر")

        XCTAssertTrue(tracker.isComplete)
        XCTAssertEqual(tracker.skipped, [7, 8, 9, 10])
    }

    func testRecognizedRatioCountsOnlyRecognizedWords() {
        var tracker = RecitationTracker(surah: .ikhlas)
        XCTAssertEqual(tracker.recognizedRatio, 1)

        tracker.hear("قل هو")
        tracker.tick(RecitationTracker.stuckVoiceLimit, voiceActive: true, paced: false)

        XCTAssertEqual(tracker.position, 3)
        XCTAssertEqual(tracker.recognizedRatio, 2.0 / 3.0, accuracy: 0.001)
    }

    func testRestartFromAyahClearsLaterProgressAndIgnoresOldText() {
        var tracker = RecitationTracker(surah: .nas)
        tracker.hear("قل اعوذ برب الناس ملك الناس اله الناس من شر الخناس")
        XCTAssertEqual(tracker.skipped, [10])

        tracker.restart(fromAyah: 3)
        XCTAssertEqual(tracker.position, 8)
        XCTAssertTrue(tracker.skipped.isEmpty)
        XCTAssertEqual(tracker.currentAyah, 3)

        // Уже распознанный текст не засчитывается заново — нужно прочитать аят ещё раз.
        tracker.hear("قل اعوذ برب الناس ملك الناس اله الناس من شر الخناس من")
        XCTAssertEqual(tracker.position, 9)
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
        tracker.hear("قل هو")

        tracker.tick(RecitationTracker.stuckVoiceLimit, voiceActive: true, paced: false)
        XCTAssertEqual(tracker.position, 3)
        XCTAssertEqual(tracker.skipped, [2])

        tracker.hear("قل هو احد")
        XCTAssertEqual(tracker.position, 4)
    }

    func testRandomSpeechNeverAdvancesByTime() {
        var tracker = RecitationTracker(surah: .fatiha)

        for _ in 0..<600 { tracker.tick(0.1, voiceActive: true, paced: false) }

        XCTAssertEqual(tracker.position, 0)
    }

    func testTalkingWithoutProgressStalls() {
        var tracker = RecitationTracker(surah: .ikhlas)

        tracker.tick(RecitationTracker.stallLimit - 1, voiceActive: true, paced: false)
        XCTAssertFalse(tracker.isStalled)
        XCTAssertFalse(tracker.isSilentTooLong)
        tracker.tick(1, voiceActive: true, paced: false)
        XCTAssertTrue(tracker.isStalled)

        tracker.hear("قل")
        XCTAssertFalse(tracker.isStalled)
    }

    func testOnlyOneWordInARowCanBeSkippedByTime() {
        var tracker = RecitationTracker(surah: .ikhlas)
        tracker.hear("قل هو")

        tracker.tick(RecitationTracker.stuckVoiceLimit, voiceActive: true, paced: false)
        tracker.tick(RecitationTracker.stuckVoiceLimit * 5, voiceActive: true, paced: false)

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
