package com.prayforever.app.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.prayforever.app.R
import com.prayforever.app.core.Ayah
import com.prayforever.app.core.RecitationTracker.WordState
import com.prayforever.app.core.Surah
import com.prayforever.app.recitation.RecitationListener
import com.prayforever.app.recitation.RecitationSession
import com.prayforever.app.ui.theme.Brand
import com.prayforever.app.ui.theme.rememberQuranFont
import kotlinx.coroutines.delay

/** Кнопки экрана в режиме тренировки (без будильника). */
class PracticeActions(
    val close: () -> Unit,
    val retry: () -> Unit,
)

/**
 * Чтение суры вслух: каждое арабское слово с транскрипцией под ним, слова отмечаются по мере чтения.
 * Без [practice] — второй шаг задания будильника, с [practice] — тренировка.
 */
@Composable
fun RecitationScreen(
    surah: Surah,
    practice: PracticeActions?,
    onOutcome: (RecitationSession.Outcome) -> Unit,
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val session = remember(surah) { RecitationSession(context, surah, failsOnSilence = practice == null) }
    var completed by remember { mutableStateOf(false) }
    var hideText by remember { mutableStateOf(false) }
    var micReady by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
    }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { micReady = true }
    LaunchedEffect(Unit) { if (!micReady) micPermission.launch(Manifest.permission.RECORD_AUDIO) }

    DisposableEffect(session, micReady) {
        if (micReady) {
            session.onFinish = { outcome ->
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                if (outcome == RecitationSession.Outcome.COMPLETED) completed = true
                onOutcome(outcome)
            }
            session.onRetry = { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
            session.start(scope)
        }
        onDispose { session.stop() }
    }
    val version by session.version.collectAsStateWithLifecycle()
    val notice by session.notice.collectAsStateWithLifecycle()
    LaunchedEffect(notice) {
        if (notice != null) {
            delay(NOTICE_MILLIS)
            session.clearNotice()
        }
    }
    val tracker = session.tracker
    val ayahText = stringResource(R.string.recitation_ayah, tracker.currentAyah + 1, surah.ayat.size)

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Header(surah, practice, hideText, { hideText = !hideText }, tracker.progress.toFloat(), version)
            AyatList(surah, session, hideText, practice != null, version, Modifier.weight(1f))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            StatusPanel(session.listener, notice, session.silenceCountdown, ayahText, showsDiagnostics = practice != null)
        }
        if (completed) ResultScreen(session, practice)
    }
}

@Composable
private fun Header(
    surah: Surah,
    practice: PracticeActions?,
    hideText: Boolean,
    toggleHide: () -> Unit,
    progress: Float,
    version: Int,
) {
    val shown by animateFloatAsState(progress, label = "progress")
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth()) {
            if (practice != null) {
                IconButton(onClick = practice.close, modifier = Modifier.align(Alignment.CenterStart)) {
                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.practice_close))
                }
                FilterChip(
                    selected = hideText,
                    onClick = toggleHide,
                    label = { Text(stringResource(R.string.practice_hide)) },
                    leadingIcon = {
                        Icon(
                            if (hideText) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            contentDescription = null,
                            Modifier.size(18.dp),
                        )
                    },
                    modifier = Modifier.align(Alignment.CenterEnd),
                )
            }
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(surah.title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    stringResource(R.string.recitation_subtitle, surah.number, surah.ayat.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        LinearProgressIndicator(progress = { if (version >= 0) shown else 0f }, modifier = Modifier.fillMaxWidth(), color = Brand.Read)
        if (practice != null) {
            Text(
                stringResource(if (hideText) R.string.practice_hide_on else R.string.practice_tapAyah),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun AyatList(
    surah: Surah,
    session: RecitationSession,
    hideText: Boolean,
    practice: Boolean,
    version: Int,
    modifier: Modifier,
) {
    val tracker = session.tracker
    val listState = rememberLazyListState()
    val offset = if (surah.showsBasmala) 1 else 0
    LaunchedEffect(tracker.currentAyah) { listState.animateScrollToItem(tracker.currentAyah + offset) }
    LazyColumn(modifier, state = listState, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (surah.showsBasmala) {
            item { Words(Surah.BASMALA, states = null, hideUnread = false, center = true) }
        }
        itemsIndexed(surah.ayat) { index, ayah ->
            val isCurrent = index == tracker.currentAyah && !tracker.isComplete
            val states = remember(version, index) { tracker.ayahRanges[index].map(tracker::state) }
            val border by animateColorAsState(if (isCurrent) Brand.Read else Color.Transparent, label = "ayah")
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(20.dp))
                    .border(1.5.dp, border, RoundedCornerShape(20.dp))
                    .clickable(enabled = practice) { session.restart(index) }
                    .padding(14.dp),
            ) {
                Text(
                    "${ayah.number}",
                    style = MaterialTheme.typography.labelMedium,
                    color = if (isCurrent) Brand.Read else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Words(ayah, states, hideUnread = hideText, center = false)
            }
        }
    }
}

/** Слова справа налево: арабский сверху, транскрипция под ним. states == null — слова не проверяются (басмала). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Words(
    ayah: Ayah,
    states: List<WordState>?,
    hideUnread: Boolean,
    center: Boolean,
) {
    val context = LocalContext.current
    val quran = rememberQuranFont()
    val transliteration = ayah.transliterationWords(context.isRussian)
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = if (center) Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally) else Arrangement.spacedBy(4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            ayah.arabicWords.forEachIndexed { i, word ->
                val state = states?.getOrNull(i)
                val hidden = hideUnread && (state == WordState.UPCOMING || state == WordState.CURRENT)
                val arabicColor =
                    when (state) {
                        null, WordState.CURRENT -> MaterialTheme.colorScheme.onSurface
                        WordState.READ -> Brand.Read
                        WordState.SKIPPED -> Brand.Skipped
                        WordState.UPCOMING -> MaterialTheme.colorScheme.onSurfaceVariant
                    }
                Column(
                    Modifier
                        .background(
                            if (state == WordState.CURRENT) Brand.Read.copy(alpha = 0.12f) else Color.Transparent,
                            RoundedCornerShape(8.dp),
                        ).padding(horizontal = 5.dp, vertical = 3.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box {
                        Text(word, fontFamily = quran, fontSize = 26.sp, color = arabicColor, modifier = Modifier.alpha(if (hidden) 0f else 1f))
                        if (hidden) {
                            Box(
                                Modifier
                                    .matchParentSize()
                                    .padding(
                                        vertical = 8.dp,
                                    ).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(6.dp)),
                            )
                        }
                    }
                    Text(
                        transliteration.getOrElse(i) { "" },
                        fontSize = 11.sp,
                        fontWeight = if (state == WordState.CURRENT) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (hidden) Color.Transparent else arabicColor.copy(alpha = 0.85f),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** Нижняя панель: микрофон, подсказка, предупреждение о тишине, на тренировке — что услышано. */
@Composable
private fun StatusPanel(
    listener: RecitationListener,
    notice: String?,
    countdown: Int?,
    ayahText: String,
    showsDiagnostics: Boolean,
) {
    val mode by listener.mode.collectAsStateWithLifecycle()
    val voice by listener.voiceActive.collectAsStateWithLifecycle()
    val level by listener.level.collectAsStateWithLifecycle()
    val transcript by listener.transcript.collectAsStateWithLifecycle()
    val problem by listener.problem.collectAsStateWithLifecycle()
    val openSettings = rememberOpenAppSettings()
    val (title, subtitle) =
        when (mode) {
            RecitationListener.Mode.STARTING -> R.string.recitation_status_starting to R.string.recitation_hint_starting
            RecitationListener.Mode.SPEECH ->
                (if (voice) R.string.recitation_status_listening else R.string.recitation_status_read) to
                    R.string.recitation_hint_speech
            RecitationListener.Mode.VOICE -> R.string.recitation_status_read to R.string.recitation_hint_voice
            RecitationListener.Mode.MANUAL -> R.string.recitation_status_noMic to R.string.recitation_hint_manual
        }
    Card(Modifier.padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (mode == RecitationListener.Mode.STARTING) {
                CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.dp)
            } else {
                Box(
                    Modifier
                        .size(32.dp)
                        .scale(if (voice) 1f + level.toFloat() * 0.15f else 1f)
                        .background(if (voice) Brand.Read else MaterialTheme.colorScheme.surfaceVariant, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (mode == RecitationListener.Mode.MANUAL) Icons.Filled.MicOff else Icons.Filled.Mic,
                        contentDescription = null,
                        tint = if (voice) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(stringResource(title), style = MaterialTheme.typography.titleSmall)
                Text(stringResource(subtitle), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(ayahText, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        AnimatedVisibility(notice != null) {
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Replay, contentDescription = null, tint = Brand.Read, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(notice.orEmpty(), color = Brand.Read, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
            }
        }
        if (showsDiagnostics && mode == RecitationListener.Mode.SPEECH) {
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.recitation_heard),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(8.dp))
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    Text(transcript.ifEmpty { "—" }, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                }
            }
        }
        if (showsDiagnostics || mode != RecitationListener.Mode.SPEECH) {
            problem?.let { Text(it, color = Brand.Skipped, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp)) }
        }
        countdown?.let {
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.WarningAmber, contentDescription = null, tint = Brand.Skipped, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(
                    stringResource(R.string.recitation_silence, it),
                    color = Brand.Skipped,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        if (mode == RecitationListener.Mode.MANUAL) {
            TextButton(onClick = openSettings) { Text(stringResource(R.string.common_openSettings)) }
        }
    }
}

@Composable
private fun ResultScreen(
    session: RecitationSession,
    practice: PracticeActions?,
) {
    val tracker = session.tracker
    val total = tracker.words.size
    val recognized = total - tracker.skipped.size
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            Modifier.fillMaxSize().padding(24.dp).navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
        ) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Brand.Read, modifier = Modifier.size(64.dp))
            Text(stringResource(R.string.verify_success), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.practice_result, recognized, total), color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (practice != null) {
                if (recognized < total) {
                    Text(
                        stringResource(R.string.practice_result_hint),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.size(24.dp))
                Button(onClick = practice.retry, modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)) { Text(stringResource(R.string.practice_again)) }
                TextButton(onClick = practice.close, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.common_done)) }
            }
        }
    }
}

private const val NOTICE_MILLIS = 5000L
