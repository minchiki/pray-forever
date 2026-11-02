package com.prayforever.app.recognition

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import androidx.core.graphics.scale
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import com.prayforever.app.core.ImageQuality
import com.prayforever.app.core.LabelMatcher
import com.prayforever.app.core.TaskKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Распознавание полностью на устройстве: классификатор ML Kit + сравнение с эталонным фото. */
class ObjectVerifier(
    context: Context,
) {
    sealed interface Result {
        data class Success(
            val kind: TaskKind,
        ) : Result

        data object TooDark : Result

        data object TooBright : Result

        data object Uniform : Result

        data object Blurry : Result

        data object ScreenOrPrint : Result

        data object NotRecognized : Result
    }

    private val references = ReferenceStore(context)
    private val labeler =
        ImageLabeling.getClient(ImageLabelerOptions.Builder().setConfidenceThreshold(LabelMatcher.MIN_CONFIDENCE.toFloat()).build())

    suspend fun verify(
        image: Bitmap,
        task: TaskKind,
    ): Result =
        withContext(Dispatchers.Default) {
            when (quality(image)?.issue) {
                ImageQuality.Issue.TOO_DARK -> return@withContext Result.TooDark
                ImageQuality.Issue.TOO_BRIGHT -> return@withContext Result.TooBright
                ImageQuality.Issue.UNIFORM -> return@withContext Result.Uniform
                ImageQuality.Issue.BLURRY -> return@withContext Result.Blurry
                null -> Unit
            }
            when (val decision = LabelMatcher.decide(classify(image), task)) {
                LabelMatcher.Decision.ScreenOrPrint -> Result.ScreenOrPrint
                is LabelMatcher.Decision.Match -> Result.Success(decision.kind)
                LabelMatcher.Decision.NoMatch -> {
                    // Эталонное фото своего коврика/раковины позволяет засчитать нестандартный объект.
                    val kinds = if (task == TaskKind.ANY) listOf(TaskKind.RUG, TaskKind.SINK) else listOf(task)
                    kinds.firstOrNull { references.matches(image, it) }?.let { Result.Success(it) } ?: Result.NotRecognized
                }
            }
        }

    private suspend fun classify(image: Bitmap): List<LabelMatcher.Label> =
        try {
            labeler.process(InputImage.fromBitmap(image, 0)).await().map { LabelMatcher.Label(it.text, it.confidence.toDouble()) }
        } catch (e: Exception) {
            Log.w(TAG, "Labeling failed", e)
            emptyList()
        }

    fun close() {
        labeler.close()
        references.close()
    }

    companion object {
        private const val TAG = "ObjectVerifier"

        fun quality(image: Bitmap): ImageQuality? {
            val size = ImageQuality.SAMPLE_SIZE
            val small = image.scale(size, size)
            val pixels = IntArray(size * size)
            small.getPixels(pixels, 0, size, 0, 0, size, size)
            if (small !== image) small.recycle()
            val gray =
                IntArray(pixels.size) {
                    val c = pixels[it]
                    (0.299 * Color.red(c) + 0.587 * Color.green(c) + 0.114 * Color.blue(c)).toInt()
                }
            return runCatching { ImageQuality.of(gray, size, size) }.getOrNull()
        }
    }
}

/** Ожидание задачи Google Tasks API в корутине (без отдельной зависимости). */
suspend fun <T> Task<T>.await(): T =
    suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener { continuation.resumeWithException(it) }
        addOnCanceledListener { continuation.cancel() }
    }
