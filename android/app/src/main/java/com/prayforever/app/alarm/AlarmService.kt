package com.prayforever.app.alarm

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.prayforever.app.core.AlarmInstance
import com.prayforever.app.core.AlarmSound
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json

/**
 * Foreground-сервис звонка. Держит процесс живым, пока будильник не выключен заданием:
 * громкий сигнал на потоке «Будильник» (звучит в беззвучном режиме), вибрация,
 * полноэкранное уведомление с заданием и тик контроллера раз в секунду.
 */
class AlarmService : Service() {
    enum class Mode { IDLE, RINGING, LISTENING, WAKE_CHECK }

    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val audio by lazy { getSystemService(AudioManager::class.java) }

    private val ticker =
        object : Runnable {
            override fun run() {
                AlarmController.tick()
                handler.postDelayed(this, TICK_MILLIS)
            }
        }

    /** Громкость будильника убавили кнопками — возвращаем максимум. */
    private val volumeObserver =
        object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                if (_mode.value == Mode.RINGING) enforceVolume()
            }
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        AlarmController.init(this)
        contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, volumeObserver)
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val instance =
            intent?.getStringExtra(EXTRA_INSTANCE)?.let {
                runCatching { json.decodeFromString(AlarmInstance.serializer(), it) }.getOrNull()
            }
        when (intent?.action) {
            ACTION_RING -> instance?.let { startRinging(it) } ?: stopSelf()
            ACTION_LISTEN -> startListening()
            ACTION_WAKE_CHECK -> startWakeCheck()
            // Система перезапустила сервис после гибели процесса: состояние восстановит контроллер.
            else -> {
                promote(Notifications.ringing(this, AlarmController.store.ringingInstance))
                AlarmController.tick()
                if (_mode.value == Mode.IDLE) stopSelf()
            }
        }
        return START_STICKY
    }

    private fun promote(notification: android.app.Notification) {
        val type =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED
            } else {
                0
            }
        ServiceCompat.startForeground(this, Notifications.ALARM_ID, notification, type)
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    private fun startRinging(instance: AlarmInstance) {
        promote(Notifications.ringing(this, instance))
        acquireWakeLock()
        if (_mode.value != Mode.RINGING || player?.isPlaying != true) {
            play(AlarmController.store.settings.value.sound, looping = true)
        }
        _mode.value = Mode.RINGING
        enforceVolume()
        vibrate()
    }

    /** Глушит сигнал: человек читает суру в микрофон. Сервис остаётся — задание ещё не выполнено. */
    private fun startListening() {
        if (_mode.value == Mode.IDLE) return stopSelf()
        stopSound()
        _mode.value = Mode.LISTENING
    }

    private fun startWakeCheck() {
        promote(Notifications.wakeCheck(this))
        acquireWakeLock()
        _mode.value = Mode.WAKE_CHECK
        play(AlarmController.store.settings.value.sound, looping = false)
        handler.postDelayed({ if (_mode.value == Mode.WAKE_CHECK) stopSound() }, PREVIEW_MILLIS)
    }

    private fun play(
        sound: AlarmSound,
        looping: Boolean,
    ) {
        stopSound()
        val attributes =
            AudioAttributes
                .Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        focusRequest =
            AudioFocusRequest
                .Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes)
                .build()
                .also { audio.requestAudioFocus(it) }
        player =
            try {
                MediaPlayer().apply {
                    assets.openFd(sound.fileName).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                    setAudioAttributes(attributes)
                    isLooping = looping
                    prepare()
                    start()
                }
            } catch (e: Exception) {
                // Звук не загрузился — будильник всё равно должен звучать: системная мелодия будильника.
                Log.e(TAG, "Cannot play ${sound.fileName}", e)
                fallbackPlayer(attributes, looping)
            }
    }

    private fun fallbackPlayer(
        attributes: AudioAttributes,
        looping: Boolean,
    ): MediaPlayer? =
        runCatching {
            MediaPlayer().apply {
                setDataSource(this@AlarmService, Settings.System.DEFAULT_ALARM_ALERT_URI)
                setAudioAttributes(attributes)
                isLooping = looping
                prepare()
                start()
            }
        }.getOrNull()

    private fun enforceVolume() {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        if (audio.getStreamVolume(AudioManager.STREAM_ALARM) < max) {
            runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, max, 0) }
        }
    }

    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }

    private fun vibrate() {
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
        @Suppress("DEPRECATION")
        vibrator().vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 600), 0), attributes)
    }

    private fun stopSound() {
        player?.runCatching {
            stop()
            release()
        }
        player = null
        vibrator().cancel()
        focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    @Suppress("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock =
            getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Prayer:alarm")
                .apply { acquire(MAX_WAKE_LOCK_MILLIS) }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopSound()
        contentResolver.unregisterContentObserver(volumeObserver)
        wakeLock?.takeIf { it.isHeld }?.release()
        _mode.value = Mode.IDLE
        super.onDestroy()
    }

    companion object {
        private const val TAG = "AlarmService"
        private const val ACTION_RING = "ring"
        private const val ACTION_LISTEN = "listen"
        private const val ACTION_WAKE_CHECK = "wake_check"
        private const val EXTRA_INSTANCE = "instance"
        private const val TICK_MILLIS = 1000L
        private const val PREVIEW_MILLIS = 3000L
        private const val MAX_WAKE_LOCK_MILLIS = 70 * 60_000L
        private val json = Json { ignoreUnknownKeys = true }

        private val _mode = MutableStateFlow(Mode.IDLE)
        val mode: StateFlow<Mode> = _mode.asStateFlow()

        fun ring(
            context: Context,
            instance: AlarmInstance,
        ) = start(context, ACTION_RING, instance)

        fun listen(context: Context) = start(context, ACTION_LISTEN, null)

        fun wakeCheck(
            context: Context,
            check: AlarmInstance,
        ) = start(context, ACTION_WAKE_CHECK, check)

        fun stop(context: Context) {
            if (_mode.value == Mode.IDLE) return
            _mode.value = Mode.IDLE
            context.stopService(Intent(context, AlarmService::class.java))
        }

        private fun start(
            context: Context,
            action: String,
            instance: AlarmInstance?,
        ) {
            val intent =
                Intent(context, AlarmService::class.java).setAction(action).apply {
                    instance?.let { putExtra(EXTRA_INSTANCE, json.encodeToString(AlarmInstance.serializer(), it)) }
                }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: IllegalStateException) {
                // Запуск из фона запрещён (бывает без разрешения на точные будильники) — остаётся уведомление.
                Log.e(TAG, "Cannot start alarm service", e)
                instance?.let { Notifications.postFallbackAlarm(context, it) }
            }
        }
    }
}
