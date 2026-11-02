package com.prayforever.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ArabicTextTest {
    @Test
    fun normalizeStripsDiacriticsAndUnifiesLetters() {
        assertEquals("الرحمن", ArabicText.normalize("الرَّحْمَٰنِ"))
        assertEquals("اله", ArabicText.normalize("إِلَٰهِ"))
        assertEquals("احد", ArabicText.normalize("أَحَدٌ"))
        assertEquals("الجنه", ArabicText.normalize("الْجِنَّةِ"))
    }

    @Test
    fun stripDiacriticsKeepsLetters() {
        assertEquals("الجنة والناس", ArabicText.stripDiacritics("الْجِنَّةِ وَالنَّاسِ"))
    }

    @Test
    fun wordsSplitOnSpacesAndPunctuation() {
        assertEquals(listOf("قل", "هو", "الله", "احد"), ArabicText.words("قُلْ هُوَ، اللَّهُ  أَحَدٌ."))
    }

    @Test
    fun fuzzyMatchToleratesSmallRecognitionErrors() {
        assertTrue(ArabicText.matches("ملك", ArabicText.normalize("مَالِكِ")))
        assertTrue(ArabicText.matches("رحيم", ArabicText.normalize("الرَّحِيمِ")))
    }

    @Test
    fun fuzzyMatchRejectsDifferentWords() {
        assertFalse(ArabicText.matches("لن", "لم"))
        assertFalse(ArabicText.matches("الفلق", "الناس"))
        assertFalse(ArabicText.matches("الخناس", "الوسواس"))
    }
}

class SurahTest {
    @Test
    fun ayahCountsMatchMushaf() {
        val expected =
            mapOf(
                Surah.FATIHA to 7,
                Surah.IKHLAS to 4,
                Surah.FALAQ to 5,
                Surah.NAS to 6,
                Surah.KAWTHAR to 3,
                Surah.ASR to 3,
                Surah.KAFIRUN to 6,
            )
        for (surah in Surah.entries) {
            assertEquals(surah.key, expected[surah], surah.ayat.size)
            assertEquals(surah.key, (1..surah.ayat.size).toList(), surah.ayat.map { it.number })
        }
    }

    @Test
    fun everyWordHasItsOwnTransliteration() {
        for (surah in Surah.entries) {
            for (ayah in surah.ayat + Surah.BASMALA) {
                val words = ayah.arabicWords.size
                assertEquals("${surah.key} ${ayah.number}", words, ayah.transliterationWords(false).size)
                assertEquals("${surah.key} ${ayah.number}", words, ayah.transliterationWords(true).size)
            }
            assertTrue(RecitationTracker(surah).words.all { it.key.isNotEmpty() })
        }
    }

    @Test
    fun recitationChoice() {
        assertNull(RecitationChoice.OFF.pick())
        assertNotNull(RecitationChoice.RANDOM.pick())
        assertEquals(Surah.NAS, RecitationChoice.NAS.pick())
    }

    /** Тексты сур на Android сгенерированы из Swift-файла — они не должны разойтись. */
    @Test
    fun surahTextsMatchIosSource() {
        val swift = File("../../Sajda/Recitation/Surah.swift").readText()
        for (ayah in Surah.entries.flatMap { it.ayat } + Surah.BASMALA) {
            assertTrue(ayah.arabic, swift.contains("\"${ayah.arabic}\""))
            assertTrue(ayah.latin, swift.contains("\"${ayah.latin}\""))
            assertTrue(ayah.cyrillic, swift.contains("\"${ayah.cyrillic}\""))
        }
    }

    @Test
    fun everySoundFileExistsInSharedResources() {
        for (sound in AlarmSound.entries) {
            assertTrue(sound.fileName, File("../../Sajda/Resources/Sounds/${sound.fileName}").isFile)
        }
    }
}

class RecitationTrackerTest {
    @Test
    fun fullRecitationCompletes() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        tracker.hear("قل هو الله احد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احد")
        assertTrue(tracker.isComplete)
        assertTrue(tracker.skipped.isEmpty())
    }

    @Test
    fun unrelatedSpeechDoesNotAdvance() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        assertFalse(tracker.hear("مرحبا كيف حالك"))
        assertEquals(0, tracker.position)
    }

    @Test
    fun missedWordIsSkippedAndMarked() {
        val tracker = RecitationTracker(Surah.NAS)
        tracker.hear("قل اعوذ برب الناس ملك الناس اله الناس من شر الخناس الذي يوسوس في صدور الناس من الجنه والناس")
        assertTrue(tracker.isComplete)
        assertEquals(setOf(10), tracker.skipped)
        assertEquals(RecitationTracker.WordState.SKIPPED, tracker.state(10))
    }

    @Test
    fun severalMissedWordsDoNotBreakAlignment() {
        val tracker = RecitationTracker(Surah.ASR)
        tracker.hear("والعصر ان الانسان لفي خسر الا الذين بالحق وتواصوا بالصبر")
        assertTrue(tracker.isComplete)
        assertEquals(setOf(7, 8, 9, 10), tracker.skipped)
    }

    @Test
    fun recognizedRatioCountsOnlyRecognizedWords() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        assertEquals(1.0, tracker.recognizedRatio, 0.0)
        tracker.hear("قل هو")
        tracker.tick(RecitationTracker.STUCK_VOICE_LIMIT, voiceActive = true, paced = false)
        assertEquals(3, tracker.position)
        assertEquals(2.0 / 3.0, tracker.recognizedRatio, 0.001)
    }

    @Test
    fun restartFromAyahClearsLaterProgressAndIgnoresOldText() {
        val tracker = RecitationTracker(Surah.NAS)
        tracker.hear("قل اعوذ برب الناس ملك الناس اله الناس من شر الخناس")
        assertEquals(setOf(10), tracker.skipped)

        tracker.restart(fromAyah = 3)
        assertEquals(8, tracker.position)
        assertTrue(tracker.skipped.isEmpty())
        assertEquals(3, tracker.currentAyah)

        tracker.hear("قل اعوذ برب الناس ملك الناس اله الناس من شر الخناس من")
        assertEquals(9, tracker.position)
    }

    @Test
    fun fatihaMayStartWithoutBasmala() {
        val tracker = RecitationTracker(Surah.FATIHA)
        tracker.hear("الحمد لله رب العالمين")
        assertEquals(8, tracker.position)
        assertEquals(2, tracker.currentAyah)
        assertTrue(tracker.skipped.isEmpty())
    }

    @Test
    fun newRecognitionSessionContinuesFromPosition() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        tracker.hear("قل هو الله احد")
        tracker.beginSession()
        tracker.hear("الله الصمد")
        assertEquals(6, tracker.position)
        assertEquals(2, tracker.currentAyah)
    }

    @Test
    fun pacedModeCountsWordsByVoiceTime() {
        val tracker = RecitationTracker(Surah.KAWTHAR)
        tracker.tick(RecitationTracker.PACED_SECONDS_PER_WORD, voiceActive = true, paced = true)
        assertEquals(1, tracker.position)
        tracker.tick(5.0, voiceActive = false, paced = true)
        assertEquals(1, tracker.position)
        assertTrue(tracker.skipped.isEmpty())
    }

    @Test
    fun silenceTriggersFailure() {
        val tracker = RecitationTracker(Surah.ASR)
        tracker.tick(RecitationTracker.SILENCE_LIMIT - 1, voiceActive = false, paced = false)
        assertFalse(tracker.isSilentTooLong)
        tracker.tick(1.0, voiceActive = false, paced = false)
        assertTrue(tracker.isSilentTooLong)
    }

    @Test
    fun stuckWordIsSkippedAfterLongVoiceAndOldTextIsNotReused() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        tracker.hear("قل هو")
        tracker.tick(RecitationTracker.STUCK_VOICE_LIMIT, voiceActive = true, paced = false)
        assertEquals(3, tracker.position)
        assertEquals(setOf(2), tracker.skipped)
        tracker.hear("قل هو احد")
        assertEquals(4, tracker.position)
    }

    @Test
    fun randomSpeechNeverAdvancesByTime() {
        val tracker = RecitationTracker(Surah.FATIHA)
        repeat(600) { tracker.tick(0.1, voiceActive = true, paced = false) }
        assertEquals(0, tracker.position)
    }

    @Test
    fun talkingWithoutProgressStalls() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        tracker.tick(RecitationTracker.STALL_LIMIT - 1, voiceActive = true, paced = false)
        assertFalse(tracker.isStalled)
        assertFalse(tracker.isSilentTooLong)
        tracker.tick(1.0, voiceActive = true, paced = false)
        assertTrue(tracker.isStalled)
        tracker.hear("قل")
        assertFalse(tracker.isStalled)
    }

    @Test
    fun onlyOneWordInARowCanBeSkippedByTime() {
        val tracker = RecitationTracker(Surah.IKHLAS)
        tracker.hear("قل هو")
        tracker.tick(RecitationTracker.STUCK_VOICE_LIMIT, voiceActive = true, paced = false)
        tracker.tick(RecitationTracker.STUCK_VOICE_LIMIT * 5, voiceActive = true, paced = false)
        assertEquals(3, tracker.position)
    }
}

class VoiceActivityDetectorTest {
    @Test
    fun loudSoundOverQuietBackgroundIsVoice() {
        val detector = VoiceActivityDetector()
        repeat(10) { assertFalse(detector.process(-60f, 0.02)) }
        assertTrue(detector.process(-30f, 0.02))
        repeat(30) { detector.process(-60f, 0.02) }
        assertFalse(detector.isActive)
    }
}
