package com.prayforever.app.core

import kotlin.random.Random

/** Цвета для раунда «Струп»: нужно выбрать цвет текста, а не прочитанное слово. */
enum class StroopColor(
    val key: String,
) {
    RED("red"),
    GREEN("green"),
    BLUE("blue"),
    YELLOW("yellow"),
    PURPLE("purple"),
    ORANGE("orange"),
}

/** Одно задание мини-игры. */
sealed interface ChallengeTask {
    enum class Kind { MATH, MEMORY, ORDER, ODD_ONE_OUT, STROOP, CODE }

    /** Пример вида «7 × 8 + 13». */
    data class Math(
        val question: String,
        val answer: Int,
    ) : ChallengeTask

    /** Запомнить цифры, пока они видны, затем ввести. */
    data class Memory(
        val digits: String,
    ) : ChallengeTask

    /** Нажать числа по возрастанию. */
    data class Order(
        val numbers: List<Int>,
    ) : ChallengeTask

    /** Найти единственный отличающийся символ. */
    data class OddOneOut(
        val symbols: List<String>,
        val oddIndex: Int,
    ) : ChallengeTask

    /** Слово одного цвета написано другим цветом — выбрать цвет текста. */
    data class Stroop(
        val word: StroopColor,
        val ink: StroopColor,
        val options: List<StroopColor>,
    ) : ChallengeTask

    /** Перепечатать код. */
    data class Code(
        val code: String,
    ) : ChallengeTask

    /** Проверка текстового ответа (пример, память, код). Пробелы, дефисы и регистр не важны. */
    fun accepts(text: String): Boolean {
        val cleaned = text.uppercase().filter { !it.isWhitespace() && it != '-' }
        return when (this) {
            is Math -> cleaned.toIntOrNull() == answer
            is Memory -> cleaned == digits
            is Code -> cleaned == code.filter { !it.isWhitespace() }
            else -> false
        }
    }

    fun acceptsIndex(index: Int): Boolean = this is OddOneOut && index == oddIndex

    fun acceptsColor(color: StroopColor): Boolean = this is Stroop && color == ink
}

/** Генератор заданий. Принимает [Random], чтобы в тестах был детерминизм. */
object ChallengeGenerator {
    const val CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const val MEMORY_LENGTH = 6
    const val CODE_LENGTH = 6
    const val ORDER_COUNT = 12
    const val ODD_GRID_SIZE = 25
    val ODD_PAIRS =
        listOf(
            "O" to "Q",
            "E" to "F",
            "b" to "d",
            "p" to "q",
            "M" to "N",
            "C" to "G",
            "6" to "8",
            "V" to "Y",
            "ш" to "щ",
            "З" to "Э",
        )

    /** Каждый тип минимум один раз, остальные — случайные, порядок перемешан. */
    fun plan(
        rounds: Int,
        random: Random,
    ): List<ChallengeTask.Kind> {
        val all = ChallengeTask.Kind.entries
        val extra = List(maxOf(0, rounds - all.size)) { all.random(random) }
        return (all + extra).shuffled(random).take(rounds)
    }

    fun make(
        kind: ChallengeTask.Kind,
        random: Random,
    ): ChallengeTask =
        when (kind) {
            ChallengeTask.Kind.MATH -> math(random)
            ChallengeTask.Kind.MEMORY ->
                ChallengeTask.Memory(List(MEMORY_LENGTH) { random.nextInt(0, 10) }.joinToString(""))
            ChallengeTask.Kind.ORDER -> ChallengeTask.Order((1..ORDER_COUNT).shuffled(random))
            ChallengeTask.Kind.ODD_ONE_OUT -> {
                val (base, odd) = ODD_PAIRS.random(random)
                val oddIndex = random.nextInt(ODD_GRID_SIZE)
                ChallengeTask.OddOneOut(List(ODD_GRID_SIZE) { if (it == oddIndex) odd else base }, oddIndex)
            }
            ChallengeTask.Kind.STROOP -> {
                val colors = StroopColor.entries.shuffled(random)
                val word = colors[0]
                val ink = colors[1]
                val options = (listOf(ink, word) + colors.drop(2).take(2)).shuffled(random)
                ChallengeTask.Stroop(word, ink, options)
            }
            ChallengeTask.Kind.CODE -> {
                val raw = String(CharArray(CODE_LENGTH) { CODE_ALPHABET[random.nextInt(CODE_ALPHABET.length)] })
                ChallengeTask.Code("${raw.take(3)} ${raw.takeLast(3)}")
            }
        }

    private fun math(random: Random): ChallengeTask {
        val a = random.nextInt(6, 15)
        val b = random.nextInt(3, 10)
        val c = random.nextInt(11, 60)
        return when (random.nextInt(3)) {
            0 -> ChallengeTask.Math("$a × $b + $c", a * b + c)
            1 -> {
                // Ответ всегда положительный — на цифровой клавиатуре нет минуса.
                val minus = random.nextInt(1, minOf(59, a * b - 1) + 1)
                ChallengeTask.Math("$a × $b − $minus", a * b - minus)
            }
            else -> ChallengeTask.Math("($a + $c) × $b", (a + c) * b)
        }
    }
}

/** Прогресс испытания: 10 раундов, ошибка откатывает на 2 раунда назад. */
data class PauseChallenge(
    val completed: Int = 0,
    val mistakes: Int = 0,
) {
    val isFinished: Boolean get() = completed >= ROUNDS

    fun success(): PauseChallenge = copy(completed = minOf(ROUNDS, completed + 1))

    fun failure(): PauseChallenge = copy(mistakes = mistakes + 1, completed = maxOf(0, completed - PENALTY))

    companion object {
        const val ROUNDS = 10
        const val PENALTY = 2
    }
}
