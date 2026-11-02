package com.prayforever.app.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.outlined.AlarmOff
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.prayforever.app.R
import com.prayforever.app.alarm.AlarmController
import com.prayforever.app.alarm.AlarmScheduler
import com.prayforever.app.alarm.Notifications
import com.prayforever.app.core.AlarmInstance
import com.prayforever.app.core.Prayer
import com.prayforever.app.location.LocationService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(navigator: Navigator) {
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    val instances by AlarmController.instances.collectAsStateWithLifecycle()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(settings.location?.name ?: stringResource(R.string.app_name), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                actions = {
                    IconButton(onClick = { navigator.open(Screen.PRACTICE) }) {
                        Icon(Icons.AutoMirrored.Outlined.MenuBook, contentDescription = stringResource(R.string.practice_title))
                    }
                    IconButton(onClick = { navigator.open(Screen.SETTINGS) }) {
                        Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.settings_title))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            settings.activePause(now)?.let { PauseBanner(it) { AlarmController.resume() } }
            ReliabilityWarnings(settings.keepAlive)
            if (settings.location == null) {
                LocationPromptCard(navigator)
            } else {
                val next = instances.firstOrNull { it.prayerTime > now && !it.isWakeCheck }
                NextPrayerCard(next, now)
                TodayList(next?.prayer?.takeIf { next.prayerTime - now < 24 * 3600_000L }, now)
            }
        }
    }
}

@Composable
private fun NextPrayerCard(
    next: AlarmInstance?,
    now: Long,
) {
    val context = LocalContext.current
    Card {
        if (next == null) {
            Text(stringResource(R.string.home_noData), color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@Card
        }
        Text(stringResource(R.string.home_next), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(context.prayerName(next.prayer), fontSize = 40.sp, fontWeight = FontWeight.Bold)
        Text(
            context.formatTime(next.prayerTime),
            fontSize = 64.sp,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
        )
        Text(context.countdown(now, next.prayerTime), style = MaterialTheme.typography.titleMedium)
        HorizontalDivider(Modifier.padding(vertical = 12.dp), color = MaterialTheme.colorScheme.outlineVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (next.alarmEnabled) Icons.Filled.Alarm else Icons.Outlined.AlarmOff,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                if (next.alarmEnabled) {
                    stringResource(R.string.home_alarmAt, context.formatTime(next.alarmTime))
                } else {
                    stringResource(R.string.home_alarmOff)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TodayList(
    nextPrayer: Prayer?,
    now: Long,
) {
    val context = LocalContext.current
    val guard = LocalGuard.current
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    val times = remember(settings, now / 60_000) { AlarmController.todayTimes().orEmpty() }
    Card(Modifier) {
        Prayer.entries.forEachIndexed { index, prayer ->
            if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            val time = times[prayer]
            val isNext = prayer == nextPrayer && time != null && time > now
            val alarmOn = settings.isAlarmEnabled(prayer)
            val color = if (isNext) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
            val weight = if (isNext) FontWeight.SemiBold else FontWeight.Normal
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(context.prayerName(prayer), Modifier.weight(1f), color = color, fontWeight = weight, style = MaterialTheme.typography.titleMedium)
                Text(time?.let(context::formatTime) ?: "—", color = color, fontWeight = weight, style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = {
                    if (alarmOn) {
                        guard.run(AlarmController.disablingNeedsChallenge(prayer)) { setAlarm(prayer, false) }
                    } else {
                        setAlarm(prayer, true)
                    }
                }) {
                    Icon(
                        if (alarmOn) Icons.Filled.Alarm else Icons.Outlined.AlarmOff,
                        contentDescription = stringResource(if (alarmOn) R.string.home_alarmOn_a11y else R.string.home_alarmOff_a11y),
                        tint = if (alarmOn) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    )
                }
            }
        }
    }
}

private fun setAlarm(
    prayer: Prayer,
    enabled: Boolean,
) = AlarmController.updateSettings { it.copy(alarmEnabled = it.alarmEnabled + (prayer.key to enabled)) }

@Composable
fun PauseBanner(
    until: Long,
    resume: () -> Unit,
) {
    val context = LocalContext.current
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.PauseCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.pause_active), fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.pause_until, context.formatDateTime(until)), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            OutlinedButton(onClick = resume) { Text(stringResource(R.string.pause_resume_short)) }
        }
    }
}

/** Что может помешать будильнику зазвонить: уведомления, точные будильники, полноэкранный показ, батарея. */
@Composable
private fun ReliabilityWarnings(keepAlive: Boolean) {
    val context = LocalContext.current
    var problems by remember { mutableStateOf(reliabilityProblems(context, keepAlive)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { problems = reliabilityProblems(context, keepAlive) }
    LaunchedEffect(keepAlive) { problems = reliabilityProblems(context, keepAlive) }
    val notifications =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            problems = reliabilityProblems(context, keepAlive)
        }
    if (problems.isEmpty()) return
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.WarningAmber, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.width(10.dp))
            Text(stringResource(R.string.warn_title), fontWeight = FontWeight.SemiBold)
        }
        problems.forEach { problem ->
            Row(
                Modifier.fillMaxWidth().clickable { fix(context, problem, notifications::launch) }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(problem.title), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { fix(context, problem, notifications::launch) }) { Text(stringResource(R.string.warn_fix)) }
            }
        }
    }
}

private enum class Problem(
    val title: Int,
) {
    NOTIFICATIONS(R.string.warn_notifications),
    EXACT(R.string.warn_exact),
    FULL_SCREEN(R.string.warn_fullscreen),
    BATTERY(R.string.warn_battery),
}

private fun reliabilityProblems(
    context: Context,
    keepAlive: Boolean,
): List<Problem> =
    buildList {
        if (!Notifications.permitted(context)) add(Problem.NOTIFICATIONS)
        if (!AlarmScheduler.canScheduleExact(context)) add(Problem.EXACT)
        if (!Notifications.canUseFullScreen(context)) add(Problem.FULL_SCREEN)
        val power = context.getSystemService(PowerManager::class.java)
        if (keepAlive && !power.isIgnoringBatteryOptimizations(context.packageName)) add(Problem.BATTERY)
    }

private fun fix(
    context: Context,
    problem: Problem,
    requestNotifications: (String) -> Unit,
) {
    val packageUri = Uri.fromParts("package", context.packageName, null)
    val intent =
        when (problem) {
            Problem.NOTIFICATIONS ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    return requestNotifications(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                }
            Problem.EXACT ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri)
                } else {
                    return
                }
            Problem.FULL_SCREEN ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri)
                } else {
                    return
                }
            Problem.BATTERY -> requestIgnoreBatteryOptimizations(context)
        }
    runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        .onFailure {
            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
}

/** Будильник — допустимая причина просить исключение из оптимизации батареи. */
@android.annotation.SuppressLint("BatteryLife")
fun requestIgnoreBatteryOptimizations(context: Context): Intent =
    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.fromParts("package", context.packageName, null))

@Composable
private fun LocationPromptCard(navigator: Navigator) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val error by AlarmController.locationError.collectAsStateWithLifecycle()
    val locating by AlarmController.locating.collectAsStateWithLifecycle()
    val openSettings = rememberOpenAppSettings()
    val locate = AlarmController::requestLocationUpdate
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            // Отказ — locateCurrent вернёт Denied и покажет ошибку с кнопкой настроек.
            if (granted) locate() else scope.launch { AlarmController.locateCurrent() }
        }
    Card {
        Icon(Icons.Outlined.LocationOn, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(40.dp))
        Spacer(Modifier.padding(6.dp))
        Text(stringResource(R.string.location_prompt_title), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.padding(4.dp))
        Text(stringResource(R.string.location_prompt_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
        error?.let {
            Spacer(Modifier.padding(4.dp))
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            if (!LocationService.hasPermission(context)) {
                TextButton(onClick = openSettings) { Text(stringResource(R.string.common_openSettings)) }
            }
        }
        Spacer(Modifier.padding(8.dp))
        Button(
            onClick = {
                if (LocationService.hasPermission(context)) locate() else permission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
            },
            enabled = !locating,
            modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
        ) {
            if (locating) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                Spacer(Modifier.width(8.dp))
            }
            Text(stringResource(R.string.location_prompt_button))
        }
        TextButton(onClick = { navigator.open(Screen.LOCATION) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.location_prompt_manual))
        }
    }
}
