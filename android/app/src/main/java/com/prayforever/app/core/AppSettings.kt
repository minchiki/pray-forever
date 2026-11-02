package com.prayforever.app.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.random.Random

@Serializable
enum class CalculationMethodOption {
    @SerialName("russia")
    RUSSIA,

    @SerialName("muslimWorldLeague")
    MUSLIM_WORLD_LEAGUE,

    @SerialName("egyptian")
    EGYPTIAN,

    @SerialName("karachi")
    KARACHI,

    @SerialName("ummAlQura")
    UMM_AL_QURA,

    @SerialName("dubai")
    DUBAI,

    @SerialName("moonsightingCommittee")
    MOONSIGHTING_COMMITTEE,

    @SerialName("northAmerica")
    NORTH_AMERICA,

    @SerialName("kuwait")
    KUWAIT,

    @SerialName("qatar")
    QATAR,

    @SerialName("singapore")
    SINGAPORE,

    @SerialName("turkey")
    TURKEY,

    @SerialName("tehran")
    TEHRAN,
}

@Serializable
enum class MadhabOption {
    @SerialName("shafi")
    SHAFI,

    @SerialName("hanafi")
    HANAFI,
}

@Serializable
enum class TaskKind(
    val key: String,
) {
    @SerialName("rug")
    RUG("rug"),

    @SerialName("sink")
    SINK("sink"),

    @SerialName("any")
    ANY("any"),
}

@Serializable
enum class AlarmSound(
    val key: String,
) {
    @SerialName("pulse")
    PULSE("pulse"),

    @SerialName("bell")
    BELL("bell"),

    @SerialName("siren")
    SIREN("siren"),

    @SerialName("clock")
    CLOCK("clock"),

    @SerialName("smoke")
    SMOKE("smoke"),

    @SerialName("klaxon")
    KLAXON("klaxon"),

    @SerialName("hilo")
    HILO("hilo"),

    @SerialName("glitch")
    GLITCH("glitch"),

    @SerialName("buzzer")
    BUZZER("buzzer"),
    ;

    val fileName: String get() = "alarm_$key.wav"
}

/** Какую суру нужно прочитать вслух после фото. */
@Serializable
enum class RecitationChoice(
    val key: String,
) {
    @SerialName("off")
    OFF("off"),

    @SerialName("random")
    RANDOM("random"),

    @SerialName("fatiha")
    FATIHA("fatiha"),

    @SerialName("ikhlas")
    IKHLAS("ikhlas"),

    @SerialName("falaq")
    FALAQ("falaq"),

    @SerialName("nas")
    NAS("nas"),

    @SerialName("kawthar")
    KAWTHAR("kawthar"),

    @SerialName("asr")
    ASR("asr"),

    @SerialName("kafirun")
    KAFIRUN("kafirun"),
    ;

    /** Конкретная сура (для RANDOM — null, её выбирает [pick]). */
    val surah: Surah? get() = Surah.entries.firstOrNull { it.key == key }

    fun pick(random: Random = Random.Default): Surah? =
        when (this) {
            OFF -> null
            RANDOM -> Surah.entries.random(random)
            else -> surah
        }
}

@Serializable
data class SavedLocation(
    val latitude: Double,
    val longitude: Double,
    val name: String? = null,
) {
    init {
        require(latitude in -90.0..90.0 && longitude in -180.0..180.0) { "Coordinates out of range" }
    }
}

/** Настройки (имена полей — как в iOS-версии). Неизвестные поля и значения при чтении заменяются значениями по умолчанию. */
@Serializable
data class AppSettings(
    val method: CalculationMethodOption = CalculationMethodOption.RUSSIA,
    val madhab: MadhabOption = MadhabOption.HANAFI,
    val alarmEnabled: Map<String, Boolean> = Prayer.entries.associate { it.key to true },
    val offsetMinutes: Map<String, Int> = emptyMap(),
    val delayMinutes: Int = 5,
    val sound: AlarmSound = AlarmSound.PULSE,
    val task: TaskKind = TaskKind.ANY,
    /** После фото нужно прочитать суру вслух. */
    val recitation: RecitationChoice = RecitationChoice.FATIHA,
    val notifyAtPrayerTime: Boolean = true,
    /** На Android — защита от оптимизации батареи; поле общее с iOS («работа в фоне»). */
    val keepAlive: Boolean = true,
    /** Проверка «не уснул» через 5 минут после выполненного задания. */
    val wakeCheck: Boolean = true,
    val location: SavedLocation? = null,
    /** Вся система на паузе до этого момента (после прохождения испытания), миллисекунды Unix. */
    val pausedUntil: Long? = null,
) {
    fun isAlarmEnabled(prayer: Prayer): Boolean = alarmEnabled[prayer.key] ?: true

    fun offset(prayer: Prayer): Int = offsetMinutes[prayer.key] ?: 0

    /** Конец паузы, если она ещё действует. */
    fun activePause(now: Long): Long? = pausedUntil?.takeIf { it > now }

    /** Значения вне допустимых диапазонов (например, из старых или повреждённых данных) приводятся к границам. */
    fun sanitized(): AppSettings =
        copy(
            delayMinutes = delayMinutes.coerceIn(DELAY_RANGE),
            offsetMinutes = offsetMinutes.mapValues { it.value.coerceIn(OFFSET_RANGE) },
        )

    companion object {
        val DELAY_RANGE = 0..60
        val OFFSET_RANGE = -30..30
    }
}
