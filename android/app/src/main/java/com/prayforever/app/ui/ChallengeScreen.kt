package com.prayforever.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.prayforever.app.R
import com.prayforever.app.core.ChallengeGenerator
import com.prayforever.app.core.ChallengeTask
import com.prayforever.app.core.PauseChallenge
import com.prayforever.app.core.StroopColor
import kotlinx.coroutines.delay
import kotlin.random.Random

/** Испытание из 10 раундов поверх всего экрана. Ошибка откатывает прогресс на 2 раунда. */
@Composable
fun ChallengeDialog(
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DialogSystemBars()
        ChallengeScreen(onComplete, onCancel)
    }
}

@Composable
private fun ChallengeScreen(
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val random = remember { Random(System.nanoTime()) }
    val kinds = remember { ChallengeGenerator.plan(PauseChallenge.ROUNDS, random) }
    var challenge by remember { mutableStateOf(PauseChallenge()) }
    var round by remember { mutableIntStateOf(0) }
    var task by remember { mutableStateOf(ChallengeGenerator.make(kinds[0], random)) }
    var wrong by remember { mutableIntStateOf(0) }

    fun handle(success: Boolean) {
        challenge = if (success) challenge.success() else challenge.failure()
        haptics.performHapticFeedback(if (success) HapticFeedbackType.TextHandleMove else HapticFeedbackType.LongPress)
        if (challenge.isFinished) return onComplete()
        if (!success) wrong += 1
        task = ChallengeGenerator.make(kinds[minOf(challenge.completed, kinds.size - 1)], random)
        round += 1
    }

    Scaffold(containerColor = MaterialTheme.colorScheme.background) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).imePadding()) {
            Column(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.pause_challenge_title), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = onCancel) { Text(stringResource(R.string.common_cancel)) }
                }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row {
                        Text(
                            stringResource(R.string.pause_challenge_round, minOf(challenge.completed + 1, PauseChallenge.ROUNDS), PauseChallenge.ROUNDS),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.weight(1f),
                        )
                        if (challenge.mistakes > 0) {
                            Text(
                                stringResource(R.string.pause_challenge_mistakes, challenge.mistakes),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    LinearProgressIndicator(
                        progress = { challenge.completed.toFloat() / PauseChallenge.ROUNDS },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                key(round) { Round(task, ::handle) }
            }
            WrongBanner(wrong, Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun WrongBanner(
    trigger: Int,
    modifier: Modifier,
) {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        visible = true
        delay(1500)
        visible = false
    }
    AnimatedVisibility(visible, modifier.padding(bottom = 24.dp), enter = fadeIn(), exit = fadeOut()) {
        Surface(color = MaterialTheme.colorScheme.error, shape = RoundedCornerShape(50)) {
            Text(
                stringResource(R.string.pause_challenge_wrong, PauseChallenge.PENALTY),
                color = MaterialTheme.colorScheme.onError,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            )
        }
    }
}

@Composable
private fun Round(
    task: ChallengeTask,
    onResult: (Boolean) -> Unit,
) {
    when (task) {
        is ChallengeTask.Math -> TextAnswerRound(stringResource(R.string.pause_task_math), task.question, KeyboardType.Number, task, onResult)
        is ChallengeTask.Code -> TextAnswerRound(stringResource(R.string.pause_task_code), task.code, KeyboardType.Ascii, task, onResult)
        is ChallengeTask.Memory -> MemoryRound(task, onResult)
        is ChallengeTask.Order -> OrderRound(task.numbers, onResult)
        is ChallengeTask.OddOneOut -> OddOneOutRound(task, onResult)
        is ChallengeTask.Stroop -> StroopRound(task, onResult)
    }
}

@Composable
private fun Prompt(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun TextAnswerRound(
    prompt: String,
    display: String,
    keyboard: KeyboardType,
    task: ChallengeTask,
    onResult: (Boolean) -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Prompt(prompt)
        Text(display, fontSize = 40.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, maxLines = 1)
        AnswerField(keyboard) { onResult(task.accepts(it)) }
    }
}

@Composable
private fun AnswerField(
    keyboard: KeyboardType,
    submit: (String) -> Unit,
) {
    var answer by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    val send = { if (answer.isNotBlank()) submit(answer) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = answer,
            onValueChange = { answer = it },
            placeholder = { Text(stringResource(R.string.pause_answer), Modifier.fillMaxWidth(), textAlign = TextAlign.Center) },
            singleLine = true,
            textStyle = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center),
            keyboardOptions =
                KeyboardOptions(
                    keyboardType = keyboard,
                    capitalization = KeyboardCapitalization.Characters,
                    autoCorrectEnabled = false,
                    imeAction = ImeAction.Done,
                ),
            keyboardActions = KeyboardActions(onDone = { send() }),
            modifier = Modifier.fillMaxWidth().focusRequester(focus),
        )
        Button(onClick = send, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
            Text(stringResource(R.string.pause_check))
        }
    }
}

@Composable
private fun MemoryRound(
    task: ChallengeTask.Memory,
    onResult: (Boolean) -> Unit,
) {
    var remaining by remember { mutableIntStateOf(MEMORY_SHOW_SECONDS) }
    LaunchedEffect(Unit) {
        while (remaining > 0) {
            delay(1000)
            remaining -= 1
        }
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
        if (remaining > 0) {
            Prompt(stringResource(R.string.pause_task_memory_show))
            Text(task.digits, fontSize = 48.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, letterSpacing = 6.sp)
            Text("$remaining", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            Prompt(stringResource(R.string.pause_task_memory_enter))
            AnswerField(KeyboardType.Number) { onResult(task.accepts(it)) }
        }
    }
}

@Composable
private fun OrderRound(
    numbers: List<Int>,
    onResult: (Boolean) -> Unit,
) {
    var next by remember { mutableIntStateOf(1) }
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Prompt(stringResource(R.string.pause_task_order))
        LazyVerticalGrid(GridCells.Fixed(3), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            itemsIndexed(numbers) { _, number ->
                val done = number < next
                Tile(
                    text = "$number",
                    enabled = !done,
                    highlighted = done,
                    fontSize = 28,
                ) {
                    if (number != next) return@Tile onResult(false)
                    next += 1
                    if (next > numbers.size) onResult(true)
                }
            }
        }
    }
}

@Composable
private fun OddOneOutRound(
    task: ChallengeTask.OddOneOut,
    onResult: (Boolean) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Prompt(stringResource(R.string.pause_task_odd))
        LazyVerticalGrid(GridCells.Fixed(5), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(task.symbols) { index, symbol ->
                Tile(text = symbol, fontSize = 28) { onResult(task.acceptsIndex(index)) }
            }
        }
    }
}

@Composable
private fun StroopRound(
    task: ChallengeTask.Stroop,
    onResult: (Boolean) -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Prompt(stringResource(R.string.pause_task_stroop))
        Text(
            stringResource(task.word.title).uppercase(),
            color = stroopColor(task.ink),
            fontSize = 48.sp,
            fontWeight = FontWeight.Black,
            maxLines = 1,
        )
        task.options.forEach { option ->
            Tile(text = stringResource(option.title), fontSize = 18) { onResult(task.acceptsColor(option)) }
        }
    }
}

@Composable
private fun Tile(
    text: String,
    fontSize: Int,
    enabled: Boolean = true,
    highlighted: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .background(if (highlighted) colors.primary.copy(alpha = 0.18f) else colors.surfaceContainer, RoundedCornerShape(14.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, fontSize = fontSize.sp, fontWeight = FontWeight.SemiBold, color = if (highlighted) colors.primary else colors.onSurface)
    }
}

private fun stroopColor(color: StroopColor): Color =
    when (color) {
        StroopColor.RED -> Color(0xFFD92929)
        StroopColor.GREEN -> Color(0xFF219945)
        StroopColor.BLUE -> Color(0xFF2661E6)
        StroopColor.YELLOW -> Color(0xFFEDBA00)
        StroopColor.PURPLE -> Color(0xFF8C40CC)
        StroopColor.ORANGE -> Color(0xFFF2801A)
    }

private const val MEMORY_SHOW_SECONDS = 3
