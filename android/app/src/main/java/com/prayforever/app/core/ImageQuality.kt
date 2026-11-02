package com.prayforever.app.core

import kotlin.math.sqrt

/** Быстрые проверки кадра до распознавания: чёрный экран, засвет, закрытый объектив, смаз. */
data class ImageQuality(
    val mean: Double,
    val stdDev: Double,
    /** Дисперсия лапласиана (нормализованная, 0...1 шкала яркости). */
    val sharpness: Double,
) {
    enum class Issue { TOO_DARK, TOO_BRIGHT, UNIFORM, BLURRY }

    val issue: Issue?
        get() =
            when {
                mean < MIN_MEAN -> Issue.TOO_DARK
                mean > MAX_MEAN -> Issue.TOO_BRIGHT
                stdDev < MIN_STD_DEV -> Issue.UNIFORM
                sharpness < MIN_SHARPNESS -> Issue.BLURRY
                else -> null
            }

    companion object {
        const val SAMPLE_SIZE = 96
        const val MIN_MEAN = 0.10
        const val MAX_MEAN = 0.96
        const val MIN_STD_DEV = 0.035
        const val MIN_SHARPNESS = 0.00035

        /** @param gray яркость пикселей 0...255, построчно, размер width*height. */
        fun of(
            gray: IntArray,
            width: Int,
            height: Int,
        ): ImageQuality {
            require(gray.size == width * height && width > 2 && height > 2)
            val values = DoubleArray(gray.size) { gray[it] / 255.0 }
            val mean = values.average()
            val variance = values.sumOf { (it - mean) * (it - mean) } / values.size

            val lap = DoubleArray((width - 2) * (height - 2))
            var k = 0
            for (y in 1 until height - 1) {
                for (x in 1 until width - 1) {
                    val i = y * width + x
                    lap[k++] = values[i - width] + values[i + width] + values[i - 1] + values[i + 1] - 4 * values[i]
                }
            }
            val lapMean = lap.average()
            val lapVar = lap.sumOf { (it - lapMean) * (it - lapMean) } / lap.size
            return ImageQuality(mean, sqrt(variance), lapVar)
        }
    }
}
