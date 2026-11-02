package com.prayforever.app.core

/**
 * Чистая логика проверки чтения: какое слово суры сейчас ожидается и что уже прочитано.
 * Порт `RecitationTracker.swift`; время — в секундах.
 */
class RecitationTracker(
    val surah: Surah,
) {
    data class Word(
        val display: String,
        val key: String,
        val ayah: Int,
    )

    enum class WordState { READ, SKIPPED, CURRENT, UPCOMING }

    val words: List<Word>
    val ayahRanges: List<IntRange>

    /** Слова басмалы в аль-Фатихе: по ханафитскому мазхабу её читают про себя, поэтому её можно пропустить. */
    private val optionalPrefix: Int

    var position = 0
        private set
    private val skippedSet = mutableSetOf<Int>()
    val skipped: Set<Int> get() = skippedSet
    var silentTime = 0.0
        private set

    /** Сколько времени чтение не продвигается. */
    var stalledTime = 0.0
        private set
    private var voiceTimeOnWord = 0.0

    /** Распознавание выдаёт весь текст текущей сессии, поэтому сопоставляем его с позиции начала сессии. */
    private var sessionStart = 0
    private var sessionOffset = 0
    private var lastHeardCount = 0

    init {
        val list = mutableListOf<Word>()
        val ranges = mutableListOf<IntRange>()
        surah.ayat.forEachIndexed { index, ayah ->
            val start = list.size
            ayah.arabicWords.forEach { list += Word(it, ArabicText.normalize(it), index) }
            ranges += start until list.size
        }
        words = list
        ayahRanges = ranges
        optionalPrefix = if (surah == Surah.FATIHA) ranges.firstOrNull()?.count() ?: 0 else 0
    }

    val isComplete: Boolean get() = position >= words.size
    val isSilentTooLong: Boolean get() = silentTime >= SILENCE_LIMIT
    val isStalled: Boolean get() = stalledTime >= STALL_LIMIT
    val currentAyah: Int get() = if (isComplete) ayahRanges.size - 1 else words[position].ayah
    val progress: Double get() = if (words.isEmpty()) 1.0 else position.toDouble() / words.size

    /** Доля слов, которые действительно распознаны (а не засчитаны по времени). */
    val recognizedRatio: Double
        get() {
            val done = minOf(position, words.size)
            if (done == 0) return 1.0
            return (done - skippedSet.count { it < done }).toDouble() / done
        }

    /** Перед текущим словом подряд распознаны настоящие слова (не пропущенные и не басмала по умолчанию). */
    private val canAutoSkip: Boolean
        get() {
            val needed = RECOGNIZED_BEFORE_AUTO_SKIP
            if (position < needed) return false
            return (position - needed until position).none { it in skippedSet }
        }

    /** Начать чтение заново с аята. Уже распознанный текст сессии повторно не засчитывается. */
    fun restart(fromAyah: Int) {
        val range = ayahRanges.getOrNull(fromAyah) ?: return
        val start = range.first
        position = start
        skippedSet.retainAll { it < start }
        voiceTimeOnWord = 0.0
        silentTime = 0.0
        stalledTime = 0.0
        sessionStart = start
        sessionOffset = lastHeardCount
    }

    fun state(index: Int): WordState =
        when {
            index == position -> WordState.CURRENT
            index > position -> WordState.UPCOMING
            index in skippedSet -> WordState.SKIPPED
            else -> WordState.READ
        }

    /** Новая сессия распознавания начинается с пустого текста. */
    fun beginSession() {
        sessionStart = position
        sessionOffset = 0
        lastHeardCount = 0
    }

    /** Обрабатывает распознанный текст текущей сессии. Возвращает true, если чтение продвинулось. */
    fun hear(transcript: String): Boolean {
        val heard = ArabicText.words(transcript)
        lastHeardCount = heard.size
        var cursor = sessionStart
        val missed = mutableListOf<Int>()
        for (word in heard.drop(sessionOffset)) {
            if (cursor >= words.size) break
            val base = if (cursor < optionalPrefix) optionalPrefix else cursor
            val fuzzyLimit = minOf(words.size - 1, base + LOOKAHEAD)
            val exactLimit = minOf(words.size - 1, base + EXACT_LOOKAHEAD)
            // Точное совпадение важнее нечёткого: «الحمد» не должно засчитаться как «الرحمن».
            val hit =
                (cursor..exactLimit).firstOrNull { words[it].key == word }
                    ?: (cursor..fuzzyLimit).firstOrNull { ArabicText.matches(word, words[it].key) }
                    ?: continue
            missed += (cursor until hit)
            cursor = hit + 1
        }
        if (cursor <= position) return false
        skippedSet += missed.filter { it >= position && it >= optionalPrefix }
        position = cursor
        voiceTimeOnWord = 0.0
        silentTime = 0.0
        stalledTime = 0.0
        return true
    }

    /**
     * @param voiceActive в микрофоне сейчас слышен голос.
     * @param paced распознавания нет — слова засчитываются по времени звучания голоса.
     */
    fun tick(
        dt: Double,
        voiceActive: Boolean,
        paced: Boolean,
    ) {
        if (isComplete) return
        silentTime = if (voiceActive) 0.0 else silentTime + dt
        stalledTime += dt
        if (!voiceActive) return
        voiceTimeOnWord += dt
        val limit = if (paced) PACED_SECONDS_PER_WORD else STUCK_VOICE_LIMIT
        if (voiceTimeOnWord < limit) return
        if (!paced) {
            if (!canAutoSkip) return
            skippedSet += position
        }
        position += 1
        voiceTimeOnWord = 0.0
        // Уже распознанный текст не должен повторно сопоставляться с новой позиции.
        sessionStart = position
        sessionOffset = lastHeardCount
    }

    companion object {
        /** На сколько слов вперёд можно «перепрыгнуть», если распознавание пропустило слово. */
        const val LOOKAHEAD = 2

        /** Точное совпадение надёжнее, поэтому для него окно шире. */
        const val EXACT_LOOKAHEAD = 5

        /** Голос слышен, а слово всё не распознаётся — засчитываем его, чтобы не застрять. */
        const val STUCK_VOICE_LIMIT = 6.0
        const val RECOGNIZED_BEFORE_AUTO_SKIP = 2

        /** Без распознавания речи слово засчитывается за это время звучания голоса. */
        const val PACED_SECONDS_PER_WORD = 0.6

        /** Тишина дольше этого — будильник звонит снова. */
        const val SILENCE_LIMIT = 30.0
        const val SILENCE_WARNING = 15.0

        /** Голос звучит, а чтение не продвигается так долго — значит, читают не суру. */
        const val STALL_LIMIT = 60.0
    }
}

/**
 * Определяет, звучит ли голос: уровень заметно выше фонового шума.
 * Параметры по умолчанию — для уровня в dBFS (как на iOS); для RMS распознавателя Android свои.
 */
class VoiceActivityDetector(
    private val margin: Float = 10f,
    private val minimumLevel: Float = -50f,
) {
    var noiseFloor: Float? = null
        private set
    var isActive = false
        private set
    private var sinceVoice = Double.POSITIVE_INFINITY

    fun process(
        levelDB: Float,
        duration: Double,
    ): Boolean {
        val floor = noiseFloor ?: levelDB
        val newFloor =
            if (levelDB < floor) {
                levelDB
            } else {
                floor + (levelDB - floor) * minOf(1f, FLOOR_RISE_RATE * duration.toFloat())
            }
        noiseFloor = newFloor
        sinceVoice = if (levelDB > maxOf(newFloor + margin, minimumLevel)) 0.0 else sinceVoice + duration
        isActive = sinceVoice <= HANGOVER
        return isActive
    }

    companion object {
        /** Голос держится активным ещё немного после паузы между словами. */
        const val HANGOVER = 0.4

        /** Скорость, с которой оценка фона догоняет текущий уровень (доля в секунду). */
        const val FLOOR_RISE_RATE = 0.05f
    }
}
