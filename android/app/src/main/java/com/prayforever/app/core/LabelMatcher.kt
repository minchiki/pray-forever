package com.prayforever.app.core

/**
 * Сопоставляет метки классификатора с заданием (коврик / раковина). Порт `LabelMatcher.swift`.
 * Словари дополнены метками ML Kit: в нём нет «rug»/«carpet», коврик узнаётся по текстильным меткам.
 */
object LabelMatcher {
    data class Label(
        val identifier: String,
        val confidence: Double,
    )

    sealed interface Decision {
        data class Match(
            val kind: TaskKind,
        ) : Decision

        data object ScreenOrPrint : Decision

        data object NoMatch : Decision
    }

    const val STRONG_THRESHOLD = 0.30
    const val SCORE_THRESHOLD = 0.50
    const val WEAK_WEIGHT = 0.5
    const val NEGATIVE_THRESHOLD = 0.35
    const val MIN_CONFIDENCE = 0.05

    val RUG_STRONG = setOf("rug", "carpet", "carpeting", "mat", "doormat", "kilim", "tapestry", "prayer")
    val RUG_WEAK =
        setOf(
            "textile",
            "fabric",
            "cloth",
            "quilt",
            "blanket",
            "embroidery",
            "velvet",
            "wool",
            "upholstery",
            "pattern",
            "ornament",
            "paisley",
            "fringe",
            "lace",
            // ML Kit
            "needlework",
            "quilting",
            "doily",
            "tablecloth",
            "placemat",
            "cotton",
        )
    val SINK_STRONG =
        setOf(
            "sink",
            "faucet",
            "washbasin",
            "basin",
            "tap",
            "lavatory",
            "bathroom",
            "washroom",
            "restroom",
            "bathtub",
            "shower",
        )
    val SINK_WEAK =
        setOf(
            "tile",
            "ceramic",
            "porcelain",
            "plumbing",
            "soap",
            "towel",
            "mirror",
            "water",
            "countertop",
            "kitchen",
            "toilet",
            "drain",
        )

    /** Снимок экрана, монитора или распечатки — не засчитываем. */
    val NEGATIVE =
        setOf(
            "screen",
            "monitor",
            "display",
            "television",
            "tv",
            "computer",
            "laptop",
            "screenshot",
            "cellphone",
            "smartphone",
            "tablet",
            "document",
            "poster",
            // ML Kit
            "web",
            "phone",
            "newspaper",
            "receipt",
            "menu",
            "presentation",
            "whiteboard",
            "blackboard",
        )

    fun decide(
        labels: List<Label>,
        task: TaskKind,
    ): Decision {
        val relevant = labels.filter { it.confidence >= MIN_CONFIDENCE }
        if (relevant.any { it.confidence >= NEGATIVE_THRESHOLD && matches(it.identifier, NEGATIVE) }) {
            return Decision.ScreenOrPrint
        }
        val candidates = if (task == TaskKind.ANY) listOf(TaskKind.RUG, TaskKind.SINK) else listOf(task)
        val best = candidates.map { it to score(relevant, it) }.maxByOrNull { it.second } ?: return Decision.NoMatch
        if (best.second < SCORE_THRESHOLD && strongest(relevant, best.first) < STRONG_THRESHOLD) return Decision.NoMatch
        return Decision.Match(best.first)
    }

    fun score(
        labels: List<Label>,
        kind: TaskKind,
    ): Double {
        val (strong, weak) = sets(kind)
        val strongMax = labels.filter { matches(it.identifier, strong) }.maxOfOrNull { it.confidence } ?: 0.0
        val weakSum = labels.filter { matches(it.identifier, weak) }.sumOf { it.confidence }
        return strongMax + minOf(weakSum, 1.0) * WEAK_WEIGHT
    }

    private fun strongest(
        labels: List<Label>,
        kind: TaskKind,
    ): Double = labels.filter { matches(it.identifier, sets(kind).first) }.maxOfOrNull { it.confidence } ?: 0.0

    private fun sets(kind: TaskKind): Pair<Set<String>, Set<String>> =
        when (kind) {
            TaskKind.RUG -> RUG_STRONG to RUG_WEAK
            TaskKind.SINK -> SINK_STRONG to SINK_WEAK
            TaskKind.ANY -> (RUG_STRONG + SINK_STRONG) to (RUG_WEAK + SINK_WEAK)
        }

    /** Сравнение по целым словам идентификатора ("bathroom_faucet", "Web page" → отдельные слова). */
    fun matches(
        identifier: String,
        keywords: Set<String>,
    ): Boolean {
        val tokens = identifier.lowercase().split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        return tokens.any { it in keywords || singular(it) in keywords }
    }

    private fun singular(word: String): String = if (word.length > 3 && word.endsWith("s")) word.dropLast(1) else word
}
