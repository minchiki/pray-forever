package com.prayforever.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class PauseChallengeTest {
    @Test
    fun planHasTenRoundsAndEveryKind() {
        val plan = ChallengeGenerator.plan(PauseChallenge.ROUNDS, Random(42))
        assertEquals(10, plan.size)
        ChallengeTask.Kind.entries.forEach { assertTrue("missing $it", it in plan) }
    }

    @Test
    fun mistakeSendsBackTwoRoundsButNotBelowZero() {
        var challenge = PauseChallenge().failure()
        assertEquals(0, challenge.completed)
        repeat(5) { challenge = challenge.success() }
        challenge = challenge.failure()
        assertEquals(3, challenge.completed)
        assertEquals(2, challenge.mistakes)
        assertFalse(challenge.isFinished)
    }

    @Test
    fun finishesAfterTenSuccesses() {
        var challenge = PauseChallenge()
        repeat(12) { challenge = challenge.success() }
        assertTrue(challenge.isFinished)
        assertEquals(PauseChallenge.ROUNDS, challenge.completed)
    }

    @Test
    fun mathAnswersArePositiveAndChecked() {
        val random = Random(7)
        repeat(300) {
            val task = ChallengeGenerator.make(ChallengeTask.Kind.MATH, random) as ChallengeTask.Math
            assertTrue(task.answer > 0)
            assertTrue(task.accepts(" ${task.answer} "))
            assertFalse(task.accepts("${task.answer + 1}"))
        }
    }

    @Test
    fun codeAndMemoryAnswersIgnoreCaseAndSpaces() {
        assertTrue(ChallengeTask.Code("K7Q M2X").accepts("k7qm2x"))
        assertTrue(ChallengeTask.Code("K7Q M2X").accepts("K7Q-M2X"))
        assertFalse(ChallengeTask.Code("K7Q M2X").accepts("K7QM2Y"))
        assertTrue(ChallengeTask.Memory("031945").accepts("031 945"))
        assertFalse(ChallengeTask.Memory("031945").accepts("31945"))
    }

    @Test
    fun oddOneOutHasExactlyOneDifferentSymbol() {
        val task = ChallengeGenerator.make(ChallengeTask.Kind.ODD_ONE_OUT, Random(3)) as ChallengeTask.OddOneOut
        assertEquals(ChallengeGenerator.ODD_GRID_SIZE, task.symbols.size)
        assertEquals(1, task.symbols.count { it == task.symbols[task.oddIndex] })
        assertTrue(task.acceptsIndex(task.oddIndex))
    }

    @Test
    fun stroopInkDiffersFromWordAndIsAnOption() {
        val random = Random(11)
        repeat(50) {
            val task = ChallengeGenerator.make(ChallengeTask.Kind.STROOP, random) as ChallengeTask.Stroop
            assertNotEquals(task.word, task.ink)
            assertTrue(task.ink in task.options)
            assertEquals(4, task.options.toSet().size)
        }
    }

    @Test
    fun orderUsesAllNumbers() {
        val task = ChallengeGenerator.make(ChallengeTask.Kind.ORDER, Random(5)) as ChallengeTask.Order
        assertEquals((1..ChallengeGenerator.ORDER_COUNT).toList(), task.numbers.sorted())
    }
}

class LabelMatcherTest {
    private fun labels(vararg pairs: Pair<String, Double>) = pairs.map { LabelMatcher.Label(it.first, it.second) }

    @Test
    fun rugIsRecognized() {
        assertEquals(
            LabelMatcher.Decision.Match(TaskKind.RUG),
            LabelMatcher.decide(labels("rug" to 0.72, "textile" to 0.4, "floor" to 0.3), TaskKind.RUG),
        )
    }

    @Test
    fun mlKitTextileLabelsRecognizeRug() {
        assertEquals(
            LabelMatcher.Decision.Match(TaskKind.RUG),
            LabelMatcher.decide(labels("Textile" to 0.82, "Pattern" to 0.71, "Wool" to 0.3), TaskKind.RUG),
        )
    }

    @Test
    fun sinkIsRecognized() {
        assertEquals(
            LabelMatcher.Decision.Match(TaskKind.SINK),
            LabelMatcher.decide(labels("bathroom_faucet" to 0.5, "sink" to 0.61), TaskKind.SINK),
        )
    }

    @Test
    fun anyTaskPicksBestKind() {
        assertEquals(
            LabelMatcher.Decision.Match(TaskKind.SINK),
            LabelMatcher.decide(labels("Sink" to 0.8, "Textile" to 0.1), TaskKind.ANY),
        )
    }

    @Test
    fun wrongObjectForSelectedTaskIsRejected() {
        assertEquals(LabelMatcher.Decision.NoMatch, LabelMatcher.decide(labels("sink" to 0.9), TaskKind.RUG))
    }

    @Test
    fun unrelatedPhotoIsRejected() {
        assertEquals(
            LabelMatcher.Decision.NoMatch,
            LabelMatcher.decide(labels("Dog" to 0.9, "Field" to 0.6, "Sky" to 0.5), TaskKind.ANY),
        )
    }

    @Test
    fun photoOfScreenIsRejected() {
        assertEquals(
            LabelMatcher.Decision.ScreenOrPrint,
            LabelMatcher.decide(labels("Textile" to 0.9, "Web page" to 0.7), TaskKind.RUG),
        )
        assertEquals(
            LabelMatcher.Decision.ScreenOrPrint,
            LabelMatcher.decide(labels("rug" to 0.6, "computer_monitor" to 0.7), TaskKind.RUG),
        )
    }

    @Test
    fun weakTextileLabelsAloneAreNotEnough() {
        assertEquals(
            LabelMatcher.Decision.NoMatch,
            LabelMatcher.decide(labels("textile" to 0.3, "pattern" to 0.2), TaskKind.RUG),
        )
    }

    @Test
    fun tokenMatchingIsWholeWord() {
        assertFalse(LabelMatcher.matches("automatic", setOf("mat")))
        assertTrue(LabelMatcher.matches("prayer_rug", setOf("rug")))
        assertTrue(LabelMatcher.matches("Carpets", setOf("carpet")))
    }
}

class ImageQualityTest {
    private val size = 32

    private fun image(value: (Int, Int) -> Int): ImageQuality = ImageQuality.of(IntArray(size * size) { value(it % size, it / size) }, size, size)

    @Test
    fun blackFrameIsTooDark() = assertEquals(ImageQuality.Issue.TOO_DARK, image { _, _ -> 3 }.issue)

    @Test
    fun whiteFrameIsTooBright() = assertEquals(ImageQuality.Issue.TOO_BRIGHT, image { _, _ -> 252 }.issue)

    @Test
    fun flatGrayFrameIsUniform() = assertEquals(ImageQuality.Issue.UNIFORM, image { _, _ -> 128 }.issue)

    @Test
    fun smoothGradientIsBlurry() = assertEquals(ImageQuality.Issue.BLURRY, image { x, _ -> 60 + x * 4 }.issue)

    @Test
    fun detailedFrameIsAccepted() = assertNull(image { x, y -> if ((x / 2 + y / 2) % 2 == 0) 40 else 210 }.issue)
}
