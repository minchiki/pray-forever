package com.prayforever.app.core

/** Разбор координат, введённых вручную: точка или запятая, пробелы по краям, проверка диапазонов. */
object CoordinateParser {
    fun parse(
        latitude: String,
        longitude: String,
    ): Pair<Double, Double>? {
        val lat = number(latitude) ?: return null
        val lon = number(longitude) ?: return null
        if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
        return lat to lon
    }

    private fun number(text: String): Double? =
        text
            .trim()
            .replace(',', '.')
            .toDoubleOrNull()
            ?.takeIf { it.isFinite() }
}
