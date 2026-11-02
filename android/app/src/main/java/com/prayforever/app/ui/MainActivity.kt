package com.prayforever.app.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.prayforever.app.alarm.AlarmController
import com.prayforever.app.core.AppSettings
import com.prayforever.app.core.Surah
import com.prayforever.app.ui.theme.PrayerTheme
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { PrayerTheme { PrayerAppUi() } }
    }

    override fun onResume() {
        super.onResume()
        AlarmController.refresh()
        // Звонок мог начаться, пока приложение было в фоне: оттуда система не даёт открыть экран задания.
        if (AlarmController.activeAlarm.value != null || AlarmController.wakeCheck.value != null) {
            startActivity(Intent(this, AlarmActivity::class.java))
        }
    }
}

/** Экраны приложения (кроме звонящего будильника — он в [AlarmActivity]). */
enum class Screen { HOME, SETTINGS, OFFSETS, LOCATION, REFERENCES, PAUSE, PRACTICE }

/**
 * Ослабление будильника за час до звонка — только через испытание.
 * Экран просит [Guard] применить изменение; если нужно, сначала показывается мини-игра.
 */
class Guard(
    private val request: (() -> Unit) -> Unit,
) {
    fun run(
        needsChallenge: Boolean,
        change: () -> Unit,
    ) = if (needsChallenge) request(change) else change()

    /** Изменение настроек: испытание, если оно ослабляет близкий будильник. */
    fun update(change: (AppSettings) -> AppSettings) = run(AlarmController.needsChallenge(change)) { AlarmController.updateSettings(change) }
}

val LocalGuard = staticCompositionLocalOf<Guard> { error("Guard is not provided") }

/** Простая навигация стеком: экранов немного, системная «Назад» снимает верхний. */
class Navigator(
    private val stack: MutableList<Screen>,
) {
    val current: Screen get() = stack.last()

    fun open(screen: Screen) {
        stack += screen
    }

    fun back(): Boolean {
        if (stack.size <= 1) return false
        stack.removeAt(stack.lastIndex)
        return true
    }

    fun home() {
        while (stack.size > 1) stack.removeAt(stack.lastIndex)
    }
}

@Composable
private fun PrayerAppUi() {
    val context = LocalContext.current
    val onboarded by AlarmController.store.onboarded.collectAsStateWithLifecycle()
    val active by AlarmController.activeAlarm.collectAsStateWithLifecycle()
    val wakeCheck by AlarmController.wakeCheck.collectAsStateWithLifecycle()
    var pending by remember { mutableStateOf<(() -> Unit)?>(null) }
    val guard = remember { Guard { pending = it } }
    val saved = rememberSaveable { arrayListOf(Screen.HOME.name) }
    val stack = remember { mutableStateListOf<Screen>().apply { addAll(saved.map(Screen::valueOf)) } }
    val navigator = remember { Navigator(stack) }
    var practiceSurah by rememberSaveable { mutableStateOf<Surah?>(null) }

    LaunchedEffect(stack.toList()) {
        saved.clear()
        saved.addAll(stack.map { it.name })
    }

    // Пока приложение на экране, контроллер тикает сам (как таймер на iOS).
    LaunchedEffect(Unit) {
        while (true) {
            AlarmController.tick()
            delay(1000)
        }
    }

    // Будильник или проверка «не уснул» — поверх всего, в отдельной активности над экраном блокировки.
    LaunchedEffect(active?.id, wakeCheck?.id) {
        if (active != null || wakeCheck != null) {
            pending = null
            practiceSurah = null
            navigator.home()
            context.startActivity(Intent(context, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    CompositionLocalProvider(LocalGuard provides guard) {
        if (!onboarded) {
            OnboardingScreen()
            return@CompositionLocalProvider
        }
        BackHandler(enabled = stack.size > 1) { navigator.back() }
        when (navigator.current) {
            Screen.HOME -> HomeScreen(navigator)
            Screen.SETTINGS -> SettingsScreen(navigator)
            Screen.OFFSETS -> OffsetsScreen(navigator)
            Screen.LOCATION -> LocationPickerScreen(navigator)
            Screen.REFERENCES -> ReferencePhotosScreen(navigator)
            Screen.PAUSE -> PauseScreen(navigator)
            Screen.PRACTICE -> PracticeScreen(navigator) { practiceSurah = it }
        }
        practiceSurah?.let { surah ->
            PracticeRecitation(surah) { practiceSurah = null }
        }
        pending?.let { change ->
            ChallengeDialog(
                onComplete = {
                    pending = null
                    change()
                },
                onCancel = { pending = null },
            )
        }
    }
}
