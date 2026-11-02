package com.prayforever.app.ui

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.prayforever.app.R
import com.prayforever.app.alarm.AlarmController
import com.prayforever.app.core.AlarmInstance
import com.prayforever.app.core.AlarmPolicy
import com.prayforever.app.core.RecitationChoice
import com.prayforever.app.recitation.RecitationSession
import com.prayforever.app.recognition.ObjectVerifier
import com.prayforever.app.ui.theme.PrayerTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil

/**
 * Звонящий будильник и проверка «не уснул». Показывается поверх экрана блокировки; «Назад» не закрывает.
 * Если человек уходит с экрана во время чтения суры, сигнал возвращается (как на iOS).
 */
class AlarmActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { PrayerTheme { AlarmRoot(::finish) } }
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) AlarmController.recitationFailed()
    }
}

@Composable
private fun AlarmRoot(finish: () -> Unit) {
    val active by AlarmController.activeAlarm.collectAsStateWithLifecycle()
    val wakeCheck by AlarmController.wakeCheck.collectAsStateWithLifecycle()
    BackHandler { }
    LaunchedEffect(active, wakeCheck) {
        if (active == null && wakeCheck == null) finish()
    }
    // Звонящий будильник важнее проверки «не уснул».
    active?.let { AlarmTaskScreen(it) } ?: wakeCheck?.let { WakeCheckScreen(it) }
}

/** Полноэкранное задание: звук играет, пока камера не распознает коврик или раковину. Затем — чтение суры. */
@Composable
private fun AlarmTaskScreen(alarm: AlarmInstance) {
    val surah by AlarmController.recitation.collectAsStateWithLifecycle()
    Crossfade(surah, label = "task") { current ->
        if (current != null) {
            RecitationScreen(current, practice = null) { outcome ->
                when (outcome) {
                    RecitationSession.Outcome.COMPLETED -> AlarmController.recitationCompleted()
                    RecitationSession.Outcome.SILENT -> AlarmController.recitationFailed()
                }
            }
        } else {
            PhotoTask(alarm)
        }
    }
}

@Composable
private fun PhotoTask(alarm: AlarmInstance) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    val verifier = remember { ObjectVerifier(context) }
    val handle = remember { CameraHandle() }
    var camera by remember { mutableStateOf(CameraState.IDLE) }
    var verifying by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<ObjectVerifier.Result?>(null) }
    var emergency by remember { mutableStateOf(false) }
    val openSettings = rememberOpenAppSettings()

    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { verifier.close() } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        when (camera) {
            CameraState.DENIED -> Message(stringResource(R.string.camera_denied), showSettings = true, openSettings)
            CameraState.UNAVAILABLE -> Message(stringResource(R.string.camera_unavailable), showSettings = false, openSettings)
            else -> CameraPreview(handle, active = result !is ObjectVerifier.Result.Success, onState = { camera = it }, modifier = Modifier.fillMaxSize())
        }
        Column(Modifier.fillMaxSize()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.75f), Color.Transparent)))
                    .statusBarsPadding()
                    .padding(horizontal = 24.dp, vertical = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    if (alarm.isTest) stringResource(R.string.alarm_test) else context.prayerName(alarm.prayer),
                    color = Color.White,
                    fontSize = 34.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    stringResource(settings.task.instruction),
                    color = Color.White.copy(alpha = 0.9f),
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                )
            }
            Spacer(Modifier.weight(1f))
            AnimatedVisibility(result != null && result !is ObjectVerifier.Result.Success, enter = fadeIn(), exit = fadeOut()) {
                Row(
                    Modifier
                        .padding(16.dp)
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(16.dp))
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Cancel, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(result?.let { stringResource(it.message) }.orEmpty(), color = Color.White, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.verify_retry), color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))))
                    .navigationBarsPadding()
                    .padding(top = 20.dp, bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                ShutterButton(verifying, enabled = camera == CameraState.RUNNING) {
                    verifying = true
                    result = null
                    scope.launch {
                        val photo = handle.takePhoto(context)
                        val outcome = photo?.let { verifier.verify(it, settings.task) } ?: ObjectVerifier.Result.NotRecognized
                        verifying = false
                        result = outcome
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        if (outcome is ObjectVerifier.Result.Success) {
                            delay(900)
                            AlarmController.photoVerified()
                            result = null
                        }
                    }
                }
                TextButton(onClick = { emergency = true }, modifier = Modifier.heightIn(min = 44.dp)) {
                    Text(stringResource(R.string.emergency_button), color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        if (result is ObjectVerifier.Result.Success) {
            Column(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.7f)),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(72.dp))
                Spacer(Modifier.size(16.dp))
                Text(
                    stringResource(if (settings.recitation == RecitationChoice.OFF) R.string.verify_success else R.string.verify_photoOk),
                    color = Color.White,
                    style = MaterialTheme.typography.titleLarge,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
    if (emergency) EmergencyDialog(alarm) { emergency = false }
}

private val ObjectVerifier.Result.message: Int
    get() =
        when (this) {
            is ObjectVerifier.Result.Success -> R.string.verify_success
            ObjectVerifier.Result.TooDark -> R.string.verify_tooDark
            ObjectVerifier.Result.TooBright -> R.string.verify_tooBright
            ObjectVerifier.Result.Uniform -> R.string.verify_uniform
            ObjectVerifier.Result.Blurry -> R.string.verify_blurry
            ObjectVerifier.Result.ScreenOrPrint -> R.string.verify_screen
            ObjectVerifier.Result.NotRecognized -> R.string.verify_notRecognized
        }

@Composable
private fun Message(
    text: String,
    showSettings: Boolean,
    openSettings: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Filled.CameraAlt, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp))
        Spacer(Modifier.size(16.dp))
        Text(text, color = Color.White, textAlign = TextAlign.Center)
        if (showSettings) {
            Spacer(Modifier.size(16.dp))
            Button(onClick = openSettings) { Text(stringResource(R.string.common_openSettings)) }
        }
    }
}

@Composable
private fun EmergencyDialog(
    alarm: AlarmInstance,
    close: () -> Unit,
) {
    val context = LocalContext.current
    val remaining = AlarmController.emergencyRemaining
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DialogSystemBars(lightBackground = false)
        Column(
            Modifier.fillMaxSize().background(Color(0xFF1A1A1A)).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
        ) {
            Text(
                stringResource(R.string.emergency_title),
                color = Color.White,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(stringResource(R.string.emergency_body), color = Color.White.copy(alpha = 0.75f), textAlign = TextAlign.Center)
            if (alarm.isTest || remaining > 0) {
                HoldToStopButton(AlarmPolicy.EMERGENCY_HOLD_SECONDS) {
                    close()
                    AlarmController.emergencyStop()
                }
                Text(
                    stringResource(R.string.emergency_remaining, remaining, AlarmPolicy.EMERGENCY_LIMIT),
                    color = Color.White.copy(alpha = 0.6f),
                    style = MaterialTheme.typography.bodySmall,
                )
            } else {
                Text(stringResource(R.string.emergency_limit), color = Color.White, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                AlarmController.nextEmergencyDate?.let {
                    Text(
                        stringResource(R.string.emergency_next, context.formatDateTime(it)),
                        color = Color.White.copy(alpha = 0.6f),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            TextButton(onClick = close) { Text(stringResource(R.string.common_cancel), color = Color.White) }
        }
    }
}

/** «Вы не спите?» — через 5 минут после задания. Не нажал за минуту — будильник звонит снова. */
@Composable
private fun WakeCheckScreen(check: AlarmInstance) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(check.id) {
        while (true) {
            now = System.currentTimeMillis()
            delay(250)
        }
    }
    val remaining = maxOf(0, ceil((check.alarmTime - now) / 1000.0).toInt())
    Column(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Spacer(Modifier.weight(1f))
        Icon(Icons.Filled.Visibility, contentDescription = null, tint = Color.White, modifier = Modifier.size(56.dp))
        Text(stringResource(R.string.wake_title), color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(
            stringResource(R.string.wake_body),
            color = Color.White.copy(alpha = 0.8f),
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        Text("$remaining", color = Color.White, fontSize = 72.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        Button(
            onClick = AlarmController::confirmAwake,
            modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
        ) { Text(stringResource(R.string.wake_confirm), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
    }
}
