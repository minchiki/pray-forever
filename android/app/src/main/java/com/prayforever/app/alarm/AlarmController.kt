package com.prayforever.app.alarm

import android.annotation.SuppressLint
import android.content.Context
import com.prayforever.app.R
import com.prayforever.app.core.AlarmInstance
import com.prayforever.app.core.AlarmPlanner
import com.prayforever.app.core.AlarmPolicy
import com.prayforever.app.core.AppSettings
import com.prayforever.app.core.Prayer
import com.prayforever.app.core.PrayerTimeCalculator
import com.prayforever.app.core.SavedLocation
import com.prayforever.app.core.Surah
import com.prayforever.app.data.SettingsStore
import com.prayforever.app.location.LocationService
import com.prayforever.app.widget.PrayerWidget
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

/**
 * Центральная логика будильника: расписание, звонок, выключение. Порт `AlarmCoordinator.swift`.
 * Все методы вызываются в главном потоке (Activity, BroadcastReceiver, Service).
 */
@SuppressLint("StaticFieldLeak") // Держит только applicationContext — утечки активности нет.
object AlarmController {
    private const val PLANNING_DAYS = 3

    private lateinit var app: Context
    lateinit var store: SettingsStore
        private set

    private val _activeAlarm = MutableStateFlow<AlarmInstance?>(null)

    /** Срабатывание, для которого показывается полноэкранное задание. */
    val activeAlarm: StateFlow<AlarmInstance?> = _activeAlarm.asStateFlow()

    private val _recitation = MutableStateFlow<Surah?>(null)

    /** Фото засчитано, теперь нужно прочитать эту суру вслух. */
    val recitation: StateFlow<Surah?> = _recitation.asStateFlow()

    private val _wakeCheck = MutableStateFlow<AlarmInstance?>(null)

    /** Проверка «не уснул», ожидающая нажатия. */
    val wakeCheck: StateFlow<AlarmInstance?> = _wakeCheck.asStateFlow()

    private val _instances = MutableStateFlow<List<AlarmInstance>>(emptyList())
    val instances: StateFlow<List<AlarmInstance>> = _instances.asStateFlow()

    private val _locationError = MutableStateFlow<String?>(null)
    val locationError: StateFlow<String?> = _locationError.asStateFlow()

    /** Часовой пояс берётся при каждом расчёте: пользователь мог перелететь. */
    private val calculator get() = PrayerTimeCalculator()

    fun init(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        store = SettingsStore(app)
        Notifications.createChannels(app)
        refresh()
    }

    private fun now() = System.currentTimeMillis()

    private fun dismissed(): Set<String> = store.dismissedIds().keys

    // Расписание

    val nextAlarm: AlarmInstance?
        get() {
            val now = now()
            val dismissed = dismissed()
            return _instances.value.firstOrNull { it.alarmEnabled && it.alarmTime > now && it.id !in dismissed }
        }

    fun todayTimes(): Map<Prayer, Long>? = calculator.times(LocalDate.now(), store.settings.value)

    /** Ближайший намаз (время намаза ещё не наступило). */
    fun nextPrayer(now: Long = now()): AlarmInstance? = _instances.value.firstOrNull { it.prayerTime > now && !it.isWakeCheck }

    fun refresh(now: Long = now()) {
        val settings = store.settings.value
        val dismissed = dismissed()
        val checks = AlarmPolicy.liveWakeChecks(store.wakeChecks, dismissed, now)
        store.wakeChecks = checks
        _instances.value =
            (calculator.instances(now, PLANNING_DAYS, settings, lookBack = AlarmPlanner.MAX_RING_DURATION) + checks)
                .sortedBy { it.prayerTime }
        val pause = settings.activePause(now)
        // На паузе планируем только то, что после её окончания — будильники вернутся сами.
        val schedulable =
            if (pause != null) {
                calculator.instances(pause, PLANNING_DAYS, settings).filter { it.prayerTime >= pause }
            } else {
                _instances.value
            }
        // События времени намаза нужны и виджету (переключить «следующий»), уведомление — только если включено.
        val events = AlarmPlanner.plan(schedulable, dismissed, notifyAtPrayerTime = true, pauseEnd = pause, now = now)
        AlarmScheduler.apply(app, store, events)
        PrayerWidget.requestUpdate(app)
        tick(now)
    }

    private fun currentDue(
        now: Long,
        dismissed: Set<String>,
    ): AlarmInstance? {
        if (store.settings.value.activePause(now) != null) return null
        val ringing = store.ringingInstance
        // Часы могли перевести назад — будильник «из будущего» не звонит.
        if (ringing != null && ringing.id !in dismissed && ringing.alarmTime <= now && now < ringing.alarmTime + AlarmPlanner.MAX_RING_DURATION) {
            return ringing
        }
        return AlarmPlanner.dueInstance(_instances.value, dismissed, now)
    }

    /** Вызывается раз в секунду, пока работает сервис будильника или открыто приложение, и на каждое событие. */
    fun tick(now: Long = now()) {
        val dismissed = dismissed()
        updateWakeCheck(now, dismissed)
        val due = currentDue(now, dismissed)
        val active = _activeAlarm.value
        if (due != null) {
            // Пока читают суру, сигнал молчит — иначе микрофон слышит будильник.
            if (active?.id != due.id || (AlarmService.mode.value != AlarmService.Mode.RINGING && _recitation.value == null)) {
                ring(due)
            }
        } else if (active != null) {
            // Время звонка истекло (час), никто не выключил — тихо завершаем.
            finish(active, markDismissed = active.id !in dismissed)
        }
    }

    // Звонок

    private fun ring(instance: AlarmInstance) {
        if (_activeAlarm.value?.id != instance.id) _recitation.value = null
        _wakeCheck.value = null
        _activeAlarm.value = instance
        store.ringingInstance = instance
        AlarmService.ring(app, instance)
    }

    // Проверка «не уснул»

    private fun updateWakeCheck(
        now: Long,
        dismissed: Set<String>,
    ) {
        val pending =
            if (_activeAlarm.value == null) AlarmPolicy.pendingWakeCheck(store.wakeChecks, dismissed, now) else null
        if (pending?.id == _wakeCheck.value?.id) return
        _wakeCheck.value = pending
        if (pending != null) {
            AlarmService.wakeCheck(app, pending)
        } else if (_activeAlarm.value == null) {
            AlarmService.stop(app)
        }
    }

    /** Пользователь подтвердил, что не спит. */
    fun confirmAwake() {
        val check = _wakeCheck.value ?: return
        store.markDismissed(check.id)
        _wakeCheck.value = null
        if (_activeAlarm.value == null) AlarmService.stop(app)
        refresh()
    }

    // Защита от обхода

    /** Ослабить будильник (выключить, сдвинуть) сейчас можно только через испытание. */
    val changesLocked: Boolean
        get() = AlarmPolicy.changesLocked(_instances.value, dismissed(), _activeAlarm.value != null, now())

    val emergencyRemaining: Int get() = AlarmPolicy.emergencyRemaining(store.emergencyUses, now())

    val nextEmergencyDate: Long? get() = AlarmPolicy.nextEmergencyDate(store.emergencyUses, now())

    /** true — изменение нужно подтвердить испытанием. */
    fun needsChallenge(change: (AppSettings) -> AppSettings): Boolean {
        val current = store.settings.value
        return changesLocked && AlarmPolicy.weakens(change(current), current)
    }

    /** Выключение будильника намаза: без испытания можно выключить только один намаз. */
    fun disablingNeedsChallenge(prayer: Prayer): Boolean = AlarmPolicy.disablingNeedsChallenge(prayer, store.settings.value) || changesLocked

    fun updateSettings(change: (AppSettings) -> AppSettings) {
        store.update(change)
        refresh()
    }

    // Пауза

    /** Вызывается только после успешного прохождения испытания. */
    fun pause(durationMillis: Long) {
        if (_activeAlarm.value != null) return
        updateSettings { it.copy(pausedUntil = now() + durationMillis) }
    }

    fun resume() = updateSettings { it.copy(pausedUntil = null) }

    fun startTestAlarm() = ring(AlarmInstance.test(now()))

    /** Фото распознано. Дальше — чтение суры, если оно включено. */
    fun photoVerified() {
        if (_activeAlarm.value == null || _recitation.value != null) return
        val surah =
            store.settings.value.recitation
                .pick() ?: return completeTask()
        _recitation.value = surah
        AlarmService.listen(app)
    }

    fun recitationCompleted() {
        if (_recitation.value != null) completeTask()
    }

    /** Человек замолчал или ушёл с экрана — сигнал снова звучит, задание начинается с фото. */
    fun recitationFailed() {
        val active = _activeAlarm.value ?: return
        if (_recitation.value == null) return
        _recitation.value = null
        ring(active)
    }

    /** Задание выполнено (фото распознано, сура прочитана). */
    fun completeTask() {
        val active = _activeAlarm.value ?: return
        if (store.settings.value.wakeCheck) {
            AlarmPolicy.wakeCheck(active, now())?.let { store.wakeChecks = store.wakeChecks + it }
        }
        finish(active, markDismissed = true)
    }

    /** Аварийное отключение. */
    fun emergencyStop() {
        val active = _activeAlarm.value ?: return
        if (!active.isTest) {
            if (emergencyRemaining <= 0) return
            store.emergencyUses = AlarmPolicy.recentEmergencyUses(store.emergencyUses, now()) + now()
        }
        finish(active, markDismissed = true)
    }

    private fun finish(
        instance: AlarmInstance,
        markDismissed: Boolean,
    ) {
        if (markDismissed) store.markDismissed(instance.id)
        store.ringingInstance = null
        _recitation.value = null
        _activeAlarm.value = null
        AlarmService.stop(app)
        refresh()
    }

    fun previewSound() = SoundPreview.play(app, store.settings.value.sound)

    // Геолокация

    suspend fun updateLocation() {
        val location = locateCurrent() ?: return
        updateSettings { it.copy(location = location) }
    }

    private val scope = MainScope()
    private val _locating = MutableStateFlow(false)

    /** Идёт определение места в фоне (экран может смениться, поиск не прерывается). */
    val locating: StateFlow<Boolean> = _locating.asStateFlow()

    fun requestLocationUpdate() {
        if (_locating.value) return
        _locating.value = true
        scope.launch {
            try {
                updateLocation()
            } finally {
                _locating.value = false
            }
        }
    }

    /** Определяет текущее место, но не сохраняет его: смену места рядом с будильником проверяет вызывающий. */
    suspend fun locateCurrent(): SavedLocation? =
        when (val result = LocationService.current(app)) {
            is LocationService.Result.Success -> {
                _locationError.value = null
                result.location
            }
            LocationService.Result.Denied -> {
                _locationError.value = app.getString(R.string.location_error_denied)
                null
            }
            LocationService.Result.Unavailable -> {
                _locationError.value = app.getString(R.string.location_error_generic)
                null
            }
        }

    fun clearLocationError() {
        _locationError.value = null
    }

    // События AlarmManager

    fun handleEvent(
        kind: AlarmPlanner.Kind,
        instanceId: String?,
    ) {
        refresh()
        when (kind) {
            AlarmPlanner.Kind.PRAYER_TIME -> {
                val instance = _instances.value.firstOrNull { it.id == instanceId } ?: return
                if (!instance.isWakeCheck && store.settings.value.notifyAtPrayerTime) {
                    Notifications.postPrayerTime(app, instance, store.settings.value.delayMinutes)
                }
            }
            AlarmPlanner.Kind.PAUSE_END -> Notifications.postPauseEnded(app)
            AlarmPlanner.Kind.ALARM -> Unit
        }
    }
}
