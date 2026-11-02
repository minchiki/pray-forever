package com.prayforever.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.prayforever.app.core.TaskKind
import com.prayforever.app.recognition.ObjectVerifier
import com.prayforever.app.recognition.ReferenceStore
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.random.Random

/** Модели на устройстве: эмбеддинг MediaPipe и классификатор ML Kit действительно загружаются и работают. */
@RunWith(AndroidJUnit4::class)
class OnDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = ReferenceStore(context)

    /** Узорчатая «плитка» — детерминированная картинка с деталями. */
    private fun pattern(seed: Int): Bitmap {
        val random = Random(seed)
        val bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint()
        canvas.drawColor(Color.rgb(random.nextInt(256), random.nextInt(256), random.nextInt(256)))
        repeat(60) {
            paint.color = Color.rgb(random.nextInt(256), random.nextInt(256), random.nextInt(256))
            val x = random.nextInt(512).toFloat()
            val y = random.nextInt(512).toFloat()
            canvas.drawCircle(x, y, random.nextInt(10, 60).toFloat(), paint)
        }
        return bitmap
    }

    @After
    fun cleanUp() {
        store.remove(TaskKind.RUG)
        store.close()
    }

    @Test
    fun referenceEmbeddingWorksAndMatchesSamePhoto() {
        // MediaPipe поставляет нативную библиотеку только для ARM: на x86_64 сравнение честно недоступно.
        assumeTrue(Build.SUPPORTED_ABIS.first().startsWith("arm"))
        val reference = pattern(1)
        assertTrue("embedding model must load", store.save(reference, TaskKind.RUG))
        assertTrue(store.matches(reference, TaskKind.RUG))
        assertFalse(store.matches(pattern(99), TaskKind.RUG))
    }

    @Test
    fun labelerRunsOnDevice() =
        runBlocking {
            val verifier = ObjectVerifier(context)
            val result = verifier.verify(pattern(7), TaskKind.RUG)
            verifier.close()
            assertNotNull(result)
        }
}
