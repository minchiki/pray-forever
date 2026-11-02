package com.prayforever.app.recitation

import android.content.Context
import com.prayforever.app.R
import com.prayforever.app.core.RecitationTracker
import com.prayforever.app.core.Surah
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.ceil

/** Связывает микрофон с проверкой чтения и сообщает, чем всё закончилось. Порт `RecitationSession.swift`. */
class RecitationSession(
    private val context: Context,
    surah: Surah,
    /** На тренировке тишина не наказывается. */
    private val failsOnSilence: Boolean,
) {
    enum class Outcome { COMPLETED, SILENT }

    val tracker = RecitationTracker(surah)
    val listener = RecitationListener(context)

    /** Счётчик изменений трекера — Compose перерисовывает экран, когда он меняется. */
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version.asStateFlow()

    /** Короткое сообщение над панелью (например, «прочитайте ещё раз»). */
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    var onFinish: ((Outcome) -> Unit)? = null
    var onRetry: (() -> Unit)? = null

    private var job: Job? = null
    private var finished = false
    private var strictRetries = 0

    fun start(scope: CoroutineScope) {
        if (job != null || finished) return
        listener.onNewSession = { tracker.beginSession() }
        listener.onTranscript = { text ->
            if (tracker.hear(text)) {
                changed()
                checkFinished()
            }
        }
        listener.start()
        job =
            scope.launch {
                var last = System.nanoTime()
                while (isActive) {
                    delay(TICK_MILLIS)
                    val now = System.nanoTime()
                    tick((now - last) / 1e9)
                    last = now
                }
            }
    }

    fun stop() {
        job?.cancel()
        job = null
        listener.stop()
    }

    /** Начать с выбранного аята (на тренировке — нажатием на аят). */
    fun restart(fromAyah: Int) {
        if (finished) return
        tracker.restart(fromAyah)
        changed()
    }

    /** Секунды до повторного звонка, если человек замолчал (null — предупреждать рано). */
    val silenceCountdown: Int?
        get() {
            if (!failsOnSilence || tracker.silentTime < RecitationTracker.SILENCE_WARNING) return null
            return maxOf(0, ceil(RecitationTracker.SILENCE_LIMIT - tracker.silentTime).toInt())
        }

    private fun changed() {
        _version.value += 1
    }

    private fun tick(dt: Double) {
        when (listener.mode.value) {
            RecitationListener.Mode.STARTING -> return
            RecitationListener.Mode.MANUAL -> tracker.tick(dt, voiceActive = true, paced = true)
            RecitationListener.Mode.VOICE -> tracker.tick(dt, listener.voiceActive.value, paced = true)
            RecitationListener.Mode.SPEECH -> tracker.tick(dt, listener.voiceActive.value, paced = false)
        }
        changed()
        checkFinished()
    }

    private fun checkFinished() {
        if (finished) return
        val speech = listener.mode.value == RecitationListener.Mode.SPEECH
        val outcome =
            when {
                tracker.isComplete -> {
                    // Слова засчитаны по времени, а не распознаны — похоже, суру не читали. В будильнике — заново.
                    if (failsOnSilence && speech && strictRetries < MAX_STRICT_RETRIES &&
                        tracker.recognizedRatio < MIN_RECOGNIZED_RATIO
                    ) {
                        strictRetries += 1
                        tracker.restart(0)
                        changed()
                        onRetry?.invoke()
                        _notice.value = context.getString(R.string.recitation_retry)
                        return
                    }
                    Outcome.COMPLETED
                }
                failsOnSilence && (tracker.isSilentTooLong || (speech && tracker.isStalled)) -> Outcome.SILENT
                else -> return
            }
        finished = true
        stop()
        onFinish?.invoke(outcome)
    }

    fun clearNotice() {
        _notice.value = null
    }

    companion object {
        /** В будильнике суру нужно действительно прочитать: если распознано меньше — читать заново. */
        const val MIN_RECOGNIZED_RATIO = 0.7

        /** Больше стольких повторов не требуем — вдруг микрофон плохо слышит именно этого человека. */
        const val MAX_STRICT_RETRIES = 2
        private const val TICK_MILLIS = 100L
    }
}
