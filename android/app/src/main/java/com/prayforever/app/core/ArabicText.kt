package com.prayforever.app.core

/** Нормализация арабского текста для сравнения распознанной речи с текстом суры. */
object ArabicText {
    private fun isDiacritic(cp: Int): Boolean = cp in 0x0610..0x061A || cp in 0x064B..0x065F || cp == 0x0670 || cp in 0x06D6..0x06ED || cp == 0x0640

    /** Убирает огласовки и знаки чтения, приводит варианты алифа, та марбуту и алиф максуру к базовым буквам. */
    fun normalize(word: String): String {
        val out = StringBuilder()
        word.codePoints().forEach { cp ->
            when {
                isDiacritic(cp) -> Unit
                cp == 0x0622 || cp == 0x0623 || cp == 0x0625 || cp == 0x0671 -> out.append('ا')
                cp == 0x0629 -> out.append('ه')
                cp == 0x0649 || cp == 0x0626 -> out.append('ي')
                cp == 0x0624 -> out.append('و')
                Character.isLetter(cp) -> out.appendCodePoint(cp)
            }
        }
        return out.toString()
    }

    /** Только убирает огласовки, буквы не меняет — так пишет текст модель распознавания. */
    fun stripDiacritics(text: String): String {
        val out = StringBuilder()
        text.codePoints().forEach { if (!isDiacritic(it)) out.appendCodePoint(it) }
        return out.toString()
    }

    /** Нормализованные слова фразы. */
    fun words(text: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()

        fun flush() {
            if (current.isNotEmpty()) {
                normalize(current.toString()).takeIf { it.isNotEmpty() }?.let(result::add)
                current.setLength(0)
            }
        }
        text.codePoints().forEach { cp ->
            if (Character.isWhitespace(cp) || isPunctuation(cp)) flush() else current.appendCodePoint(cp)
        }
        flush()
        return result
    }

    private fun isPunctuation(cp: Int): Boolean =
        when (Character.getType(cp).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
            Character.OTHER_PUNCTUATION,
            -> true
            else -> false
        }

    /** Нечёткое совпадение слов: распознавание часто ошибается на одну-две буквы. */
    fun matches(
        heard: String,
        expected: String,
    ): Boolean {
        if (heard == expected) return true
        val a = heard.codePoints().toArray()
        val b = expected.codePoints().toArray()
        val longest = maxOf(a.size, b.size)
        val shortest = minOf(a.size, b.size)
        val allowed =
            when {
                longest <= 3 -> if (shortest >= 3) 1 else 0
                longest <= 5 -> 1
                else -> 2
            }
        if (allowed == 0 || longest - shortest > allowed) return false
        return levenshtein(a, b) <= allowed
    }

    fun levenshtein(
        a: IntArray,
        b: IntArray,
    ): Int {
        if (a.isEmpty()) return b.size
        if (b.isEmpty()) return a.size
        var previous = IntArray(b.size + 1) { it }
        for (i in a.indices) {
            val current = IntArray(b.size + 1)
            current[0] = i + 1
            for (j in b.indices) {
                current[j + 1] = minOf(previous[j + 1] + 1, current[j] + 1, previous[j] + if (a[i] == b[j]) 0 else 1)
            }
            previous = current
        }
        return previous[b.size]
    }
}
