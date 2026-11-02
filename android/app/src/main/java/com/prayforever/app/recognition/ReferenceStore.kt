package com.prayforever.app.recognition

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.Embedding
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.imageembedder.ImageEmbedder
import com.prayforever.app.core.TaskKind
import java.io.File

/**
 * Эталонные фото «своего» коврика и раковины. Сравнение по эмбеддингу MobileNet V3 (MediaPipe),
 * на устройстве, без сети — аналог VNFeaturePrint на iOS.
 */
class ReferenceStore(
    private val context: Context,
) {
    private val directory = File(context.filesDir, "references")
    private var embedder: ImageEmbedder? = null
    private val cache = mutableMapOf<TaskKind, Embedding>()

    private fun file(kind: TaskKind) = File(directory, "${kind.key}.jpg")

    fun hasReference(kind: TaskKind): Boolean = file(kind).isFile

    /**
     * Сохраняет фото (JPEG, сторона до 1024 px) и сразу считает его эмбеддинг.
     * @return false — фото сохранено, но сравнивать с ним на этом устройстве не получится (модель недоступна).
     */
    fun save(
        image: Bitmap,
        kind: TaskKind,
    ): Boolean {
        directory.mkdirs()
        val temp = File(directory, "${kind.key}.tmp")
        temp.outputStream().use { check(image.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it)) }
        check(temp.renameTo(file(kind)) || (file(kind).delete() && temp.renameTo(file(kind))))
        cache.remove(kind)
        return embed(image)?.also { cache[kind] = it } != null
    }

    fun remove(kind: TaskKind) {
        file(kind).delete()
        cache.remove(kind)
    }

    /** Похоже ли фото на эталон. Нет эталона или модель недоступна — false. */
    fun matches(
        image: Bitmap,
        kind: TaskKind,
    ): Boolean {
        if (!hasReference(kind)) return false
        val reference = cache[kind] ?: BitmapFactory.decodeFile(file(kind).path)?.let { embed(it) }?.also { cache[kind] = it }
        val photo = embed(image) ?: return false
        reference ?: return false
        return ImageEmbedder.cosineSimilarity(reference, photo) >= SIMILARITY_THRESHOLD
    }

    private fun embed(image: Bitmap): Embedding? =
        runCatching {
            val model =
                embedder ?: ImageEmbedder
                    .createFromOptions(
                        context,
                        ImageEmbedder.ImageEmbedderOptions
                            .builder()
                            .setBaseOptions(BaseOptions.builder().setModelAssetPath(MODEL).build())
                            .setL2Normalize(true)
                            .build(),
                    ).also { embedder = it }
            model
                .embed(BitmapImageBuilder(image).build())
                .embeddingResult()
                .embeddings()
                .first()
        }.onFailure { Log.w(TAG, "Embedding failed", it) }.getOrNull()

    fun close() {
        embedder?.close()
        embedder = null
    }

    companion object {
        private const val TAG = "ReferenceStore"
        private const val MODEL = "image_embedder.tflite"
        private const val JPEG_QUALITY = 85

        /**
         * Порог косинусной близости. Калибровка на этой же модели (scripts/calibrate_reference_threshold.py):
         * тот же коврик при повороте, кадрировании, другом свете — 0.62…0.94; другой коврик — 0.26;
         * 278 посторонних изображений — не выше 0.26.
         */
        const val SIMILARITY_THRESHOLD = 0.55
    }
}
