package com.prayforever.app.recitation

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat
import com.prayforever.app.R
import com.prayforever.app.core.VoiceActivityDetector
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Микрофон и распознавание чтения. Основной способ — распознаватель Android (арабский, на устройстве, если
 * есть модель); без распознавания — детектор голоса; без микрофона — ручной режим. Порт `RecitationListener.swift`.
 * Модель Tarteel на Android пока не перенесена (см. roadmap в README).
 */
class RecitationListener(
    private val context: Context,
) {
    enum class Mode { STARTING, SPEECH, VOICE, MANUAL }

    private val _mode = MutableStateFlow(Mode.STARTING)
    val mode: StateFlow<Mode> = _mode.asStateFlow()

    /** Громкость для индикатора, 0...1. */
    private val _level = MutableStateFlow(0.0)
    val level: StateFlow<Double> = _level.asStateFlow()

    private val _voiceActive = MutableStateFlow(false)
    val voiceActive: StateFlow<Boolean> = _voiceActive.asStateFlow()

    /** Что распознаватель услышал в текущей сессии (показывается на тренировке). */
    private val _transcript = MutableStateFlow("")
    val transcript: StateFlow<String> = _transcript.asStateFlow()

    /** Почему распознавание не работает. */
    private val _problem = MutableStateFlow<String?>(null)
    val problem: StateFlow<String?> = _problem.asStateFlow()

    var onTranscript: ((String) -> Unit)? = null

    /** Началась новая сессия распознавания (текст начинается заново). */
    var onNewSession: (() -> Unit)? = null

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var running = false
    private var everHeard = false
    private var failures = 0
    private var onDevice = false

    // RMS распознавателя — примерно от -2 до 10 дБ, поэтому пороги свои.
    private var speechDetector = VoiceActivityDetector(margin = SPEECH_MARGIN, minimumLevel = SPEECH_MIN_LEVEL)
    private var lastRms = 0L

    @Volatile private var recording = false
    private var recorderThread: Thread? = null

    fun start() {
        if (running) return
        running = true
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            _problem.value = context.getString(R.string.recitation_problem_denied)
            _mode.value = Mode.MANUAL
            return
        }
        onDevice =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        if (onDevice || SpeechRecognizer.isRecognitionAvailable(context)) {
            _mode.value = Mode.SPEECH
            startRecognition()
        } else {
            fallBackToVoice(context.getString(R.string.recitation_problem_unavailable))
        }
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        recognizer?.runCatching {
            cancel()
            destroy()
        }
        recognizer = null
        recording = false
        recorderThread?.join(JOIN_MILLIS)
        recorderThread = null
        _voiceActive.value = false
        _level.value = 0.0
        _transcript.value = ""
    }

    // Распознаватель Android

    private fun createRecognizer(): SpeechRecognizer =
        if (onDevice && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            SpeechRecognizer.createSpeechRecognizer(context)
        }

    private fun startRecognition() {
        if (!running) return
        recognizer?.destroy()
        val current = createRecognizer()
        recognizer = current
        current.setRecognitionListener(listener(current))
        val intent =
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, LANGUAGE)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, SILENCE_MILLIS)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, SILENCE_MILLIS)
            }
        _transcript.value = ""
        onNewSession?.invoke()
        current.startListening(intent)
    }

    private fun listener(owner: SpeechRecognizer) =
        object : RecognitionListener {
            /** Ответы от старого, уже заменённого распознавателя игнорируем. */
            private val stale get() = !running || recognizer !== owner

            override fun onReadyForSpeech(params: Bundle?) = Unit

            override fun onBeginningOfSpeech() = Unit

            override fun onRmsChanged(rmsdB: Float) {
                if (stale) return
                val now = System.nanoTime()
                val duration = if (lastRms == 0L) 0.05 else (now - lastRms) / 1e9
                lastRms = now
                handleLevel(speechDetector.process(rmsdB, duration), ((rmsdB + 2) / 12.0).coerceIn(0.0, 1.0))
            }

            override fun onBufferReceived(buffer: ByteArray?) = Unit

            override fun onEndOfSpeech() = Unit

            override fun onPartialResults(partialResults: Bundle?) {
                if (!stale) deliver(partialResults)
            }

            override fun onResults(results: Bundle?) {
                if (stale) return
                deliver(results)
                restartSoon()
            }

            override fun onEvent(
                eventType: Int,
                params: Bundle?,
            ) = Unit

            override fun onError(error: Int) {
                if (stale) return
                handleError(error)
            }
        }

    private fun deliver(bundle: Bundle?) {
        val text =
            bundle
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
        if (text.isEmpty()) return
        everHeard = true
        failures = 0
        _problem.value = null
        _transcript.value = text
        onTranscript?.invoke(text)
    }

    private fun handleError(error: Int) {
        when (error) {
            // Тишина или нераспознанная речь — обычное дело, просто начинаем новую сессию.
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT, SpeechRecognizer.ERROR_CLIENT -> restartSoon()
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                _problem.value = context.getString(R.string.recitation_problem_denied)
                stopRecognizer()
                _mode.value = Mode.MANUAL
            }
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY, SpeechRecognizer.ERROR_AUDIO -> {
                _problem.value = context.getString(R.string.recitation_problem_busy)
                countFailure()
            }
            else -> {
                Log.w(TAG, "Recognition error $error (onDevice=$onDevice)")
                // Модели на устройстве нет (или нет сети) — пробуем другой распознаватель.
                if (onDevice) onDevice = false
                _problem.value = context.getString(R.string.recitation_problem_unavailable)
                countFailure()
            }
        }
    }

    private fun countFailure() {
        if (!everHeard) failures += 1
        if (failures >= MAX_FAILURES_BEFORE_FALLBACK) {
            fallBackToVoice(_problem.value)
        } else {
            restartSoon()
        }
    }

    private fun restartSoon() {
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(::startRecognition, RESTART_DELAY)
    }

    private fun stopRecognizer() {
        recognizer?.runCatching { destroy() }
        recognizer = null
    }

    // Детектор голоса без распознавания

    private fun fallBackToVoice(problem: String?) {
        stopRecognizer()
        _problem.value = problem
        _mode.value = Mode.VOICE
        startRecorder()
    }

    @SuppressLint("MissingPermission")
    private fun startRecorder() {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val record =
            runCatching {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize * 2,
                )
            }.getOrNull()
        if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
            record?.release()
            _mode.value = Mode.MANUAL
            return
        }
        recording = true
        val detector = VoiceActivityDetector()
        recorderThread =
            Thread {
                val buffer = ShortArray(FRAME)
                record.startRecording()
                while (recording) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read <= 0) continue
                    var sum = 0.0
                    for (i in 0 until read) sum += buffer[i] * buffer[i].toDouble()
                    val rms = sqrt(sum / read) / Short.MAX_VALUE
                    val db = if (rms > 0) maxOf(-100.0, 20 * log10(rms)).toFloat() else -100f
                    val active = detector.process(db, read.toDouble() / SAMPLE_RATE)
                    handler.post { if (running) handleLevel(active, ((db + 60) / 50.0).coerceIn(0.0, 1.0)) }
                }
                record.stop()
                record.release()
            }.apply { start() }
    }

    private fun handleLevel(
        active: Boolean,
        level: Double,
    ) {
        if (active != _voiceActive.value) _voiceActive.value = active
        // Индикатору не нужна каждая порция звука — обновляем при заметном изменении.
        if (kotlin.math.abs(level - _level.value) > 0.03) _level.value = level
    }

    companion object {
        private const val TAG = "RecitationListener"
        private const val LANGUAGE = "ar-SA"
        private const val MAX_FAILURES_BEFORE_FALLBACK = 4
        private const val RESTART_DELAY = 300L
        private const val SILENCE_MILLIS = 4000
        private const val SAMPLE_RATE = 16_000
        private const val FRAME = 800
        private const val JOIN_MILLIS = 500L
        private const val SPEECH_MARGIN = 2.5f
        private const val SPEECH_MIN_LEVEL = 3f
    }
}
