package com.prayforever.app.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.core.content.edit
import com.prayforever.app.core.AlarmInstance
import com.prayforever.app.core.AppSettings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/** Хранит настройки и служебное состояние будильника в SharedPreferences (JSON, как UserDefaults на iOS). */
class SettingsStore(
    context: Context,
) {
    private val prefs: SharedPreferences = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private val _settings = MutableStateFlow(load(KEY_SETTINGS, AppSettings.serializer())?.sanitized() ?: AppSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    private val _onboarded = MutableStateFlow(prefs.getBoolean(KEY_ONBOARDED, false))
    val onboarded: StateFlow<Boolean> = _onboarded.asStateFlow()

    fun update(change: (AppSettings) -> AppSettings) {
        val next = change(_settings.value).sanitized()
        if (next == _settings.value) return
        _settings.value = next
        save(KEY_SETTINGS, AppSettings.serializer(), next)
    }

    fun setOnboarded() {
        _onboarded.value = true
        prefs.edit { putBoolean(KEY_ONBOARDED, true) }
    }

    // Отключённые (выполненные задания) срабатывания

    fun dismissedIds(): Map<String, Long> = load(KEY_DISMISSED, DISMISSED_SERIALIZER) ?: emptyMap()

    fun isDismissed(id: String): Boolean = id in dismissedIds()

    fun markDismissed(
        id: String,
        now: Long = System.currentTimeMillis(),
    ) {
        val pruned = dismissedIds().filterValues { now - it < DISMISSED_RETENTION }
        save(KEY_DISMISSED, DISMISSED_SERIALIZER, pruned + (id to now))
    }

    /** Текущее звонящее срабатывание — переживает перезапуск процесса. */
    var ringingInstance: AlarmInstance?
        get() = load(KEY_RINGING, AlarmInstance.serializer())
        set(value) {
            if (value == null) prefs.edit { remove(KEY_RINGING) } else save(KEY_RINGING, AlarmInstance.serializer(), value)
        }

    /** Проверки «не уснул». */
    var wakeChecks: List<AlarmInstance>
        get() = load(KEY_WAKE_CHECKS, ListSerializer(AlarmInstance.serializer())) ?: emptyList()
        set(value) = save(KEY_WAKE_CHECKS, ListSerializer(AlarmInstance.serializer()), value)

    /** Аварийные отключения (время, миллисекунды Unix). */
    var emergencyUses: List<Long>
        get() = load(KEY_EMERGENCY, ListSerializer(Long.serializer())) ?: emptyList()
        set(value) = save(KEY_EMERGENCY, ListSerializer(Long.serializer()), value)

    /** Коды запланированных событий AlarmManager — чтобы снять старые при пересборке плана. */
    var scheduledCodes: Set<Int>
        get() =
            prefs
                .getStringSet(KEY_SCHEDULED, emptySet())
                .orEmpty()
                .mapNotNull { it.toIntOrNull() }
                .toSet()
        set(value) = prefs.edit { putStringSet(KEY_SCHEDULED, value.map(Int::toString).toSet()) }

    private fun <T> save(
        key: String,
        serializer: KSerializer<T>,
        value: T,
    ) = prefs.edit { putString(key, JSON.encodeToString(serializer, value)) }

    /** Повреждённые данные не должны ронять будильник: читаем как отсутствующие. */
    private fun <T> load(
        key: String,
        serializer: KSerializer<T>,
    ): T? {
        val raw = prefs.getString(key, null) ?: return null
        return runCatching { JSON.decodeFromString(serializer, raw) }
            .onFailure { Log.w(TAG, "Cannot decode $key, using defaults", it) }
            .getOrNull()
    }

    companion object {
        private const val TAG = "SettingsStore"
        private const val FILE = "sajda"
        private const val KEY_SETTINGS = "sajda.settings.v1"
        private const val KEY_DISMISSED = "sajda.dismissed.v1"
        private const val KEY_RINGING = "sajda.ringing.v1"
        private const val KEY_ONBOARDED = "sajda.onboarded.v1"
        private const val KEY_WAKE_CHECKS = "sajda.wakechecks.v1"
        private const val KEY_EMERGENCY = "sajda.emergency.v1"
        private const val KEY_SCHEDULED = "sajda.scheduled.v1"
        private const val DISMISSED_RETENTION = 3 * 24 * 3600_000L
        private val DISMISSED_SERIALIZER = MapSerializer(String.serializer(), Long.serializer())

        val JSON =
            Json {
                ignoreUnknownKeys = true
                coerceInputValues = true
                encodeDefaults = true
            }
    }
}
