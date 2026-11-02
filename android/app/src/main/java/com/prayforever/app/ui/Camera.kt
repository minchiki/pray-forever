package com.prayforever.app.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/** Состояние камеры, как CameraController.State в iOS-версии. */
enum class CameraState { IDLE, RUNNING, DENIED, UNAVAILABLE }

/** Делает снимок с живой камеры и возвращает его в нормальной ориентации, уменьшенным до 1024 px. */
class CameraHandle {
    internal var capture: ImageCapture? = null

    suspend fun takePhoto(context: Context): Bitmap? {
        val use = capture ?: return null
        return suspendCancellableCoroutine { continuation ->
            use.takePicture(
                ContextCompat.getMainExecutor(context),
                object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        val bitmap = runCatching { normalized(image) }.getOrNull()
                        image.close()
                        continuation.resume(bitmap)
                    }

                    override fun onError(exception: ImageCaptureException) {
                        Log.w("Camera", "Capture failed", exception)
                        continuation.resume(null)
                    }
                },
            )
        }
    }

    private fun normalized(image: ImageProxy): Bitmap {
        val source = image.toBitmap()
        val scale = minOf(1f, MAX_SIDE / maxOf(source.width, source.height))
        val matrix =
            Matrix().apply {
                postScale(scale, scale)
                postRotate(image.imageInfo.rotationDegrees.toFloat())
            }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private companion object {
        const val MAX_SIDE = 1024f
    }
}

/**
 * Превью задней камеры. Разрешение запрашивается при первом показе.
 * @param active false — камера отпускается (например, во время чтения суры).
 */
@Composable
fun CameraPreview(
    handle: CameraHandle,
    active: Boolean,
    onState: (CameraState) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val launcher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            granted = it
            if (!it) onState(CameraState.DENIED)
        }
    LaunchedEffect(Unit) { if (!granted) launcher.launch(Manifest.permission.CAMERA) }
    if (!granted) return

    val previewView = remember { PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    AndroidView({ previewView }, modifier)

    DisposableEffect(active, lifecycle) {
        if (!active) return@DisposableEffect onDispose { }
        val future = ProcessCameraProvider.getInstance(context)
        var provider: ProcessCameraProvider? = null
        future.addListener({
            provider =
                runCatching { future.get() }.getOrNull() ?: run {
                    onState(CameraState.UNAVAILABLE)
                    return@addListener
                }
            val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            val capture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
            try {
                provider?.unbindAll()
                provider?.bindToLifecycle(lifecycle, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
                handle.capture = capture
                onState(CameraState.RUNNING)
            } catch (e: Exception) {
                Log.w("Camera", "Cannot bind camera", e)
                onState(CameraState.UNAVAILABLE)
            }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            handle.capture = null
            provider?.unbindAll()
        }
    }
}
