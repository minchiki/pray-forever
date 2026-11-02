package com.prayforever.app.ui

import android.content.Intent
import android.location.Address
import android.os.PowerManager
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MyLocation
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.prayforever.app.BuildConfig
import com.prayforever.app.R
import com.prayforever.app.alarm.AlarmController
import com.prayforever.app.core.AlarmSound
import com.prayforever.app.core.AppSettings
import com.prayforever.app.core.CalculationMethodOption
import com.prayforever.app.core.CoordinateParser
import com.prayforever.app.core.ImageQuality
import com.prayforever.app.core.MadhabOption
import com.prayforever.app.core.PauseChallenge
import com.prayforever.app.core.Prayer
import com.prayforever.app.core.RecitationChoice
import com.prayforever.app.core.SavedLocation
import com.prayforever.app.core.TaskKind
import com.prayforever.app.location.LocationService
import com.prayforever.app.recognition.ObjectVerifier
import com.prayforever.app.recognition.ReferenceStore
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

private const val REPO_URL = "https://github.com/minchiki/pray-forever"
private const val CHANNEL_URL = "https://t.me/huicoding"

@Composable
private fun SettingsScaffold(
    title: String,
    navigator: Navigator,
    content: @Composable ColumnScope.() -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { BackTopBar(title, onBack = { navigator.back() }) },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
    }
}

@Composable
private fun Section(
    @StringRes header: Int?,
    footer: List<String> = emptyList(),
    content: @Composable ColumnScope.() -> Unit,
) {
    if (header != null) {
        Text(
            stringResource(header).uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
        )
    }
    Column(
        Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(16.dp)).padding(horizontal = 16.dp),
        content = content,
    )
    footer.forEach {
        Text(
            it,
            style = MaterialTheme.typography.bodySmall,
            color = if (it.startsWith(LOCK_MARK)) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
        )
    }
}

private const val LOCK_MARK = "⚠ "

@Composable
private fun NavRow(
    title: String,
    value: String? = null,
    onClick: () -> Unit,
) = ValueRow(title, value, Modifier.clickable(onClick = onClick))

@Composable
private fun SwitchRow(
    title: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { onChange(!checked) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked, onCheckedChange = onChange)
    }
}

@Composable
private fun StepperRow(
    title: String,
    value: String,
    canDecrease: Boolean,
    canIncrease: Boolean,
    onStep: (Int) -> Unit,
) {
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
        IconButton(onClick = { onStep(-1) }, enabled = canDecrease) { Icon(Icons.Outlined.Remove, contentDescription = "−") }
        IconButton(onClick = { onStep(1) }, enabled = canIncrease) { Icon(Icons.Outlined.Add, contentDescription = "+") }
    }
}

/** Выбор из списка — диалог с переключателями (аналог Picker в iOS). */
@Composable
private fun <T> ChoiceRow(
    title: String,
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onSelect: (T) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    NavRow(title, label(selected)) { open = true }
    if (!open) return
    AlertDialog(
        onDismissRequest = { open = false },
        title = { Text(title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                options.forEach { option ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(option == selected, role = Role.RadioButton) {
                            open = false
                            onSelect(option)
                        },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(option == selected, onClick = null)
                        Spacer(Modifier.width(12.dp))
                        Text(label(option))
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { open = false }) { Text(stringResource(R.string.common_cancel)) } },
    )
}

@Composable
private fun Divider() = HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

// Настройки

@Composable
fun SettingsScreen(navigator: Navigator) {
    val context = LocalContext.current
    val guard = LocalGuard.current
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    val locked = AlarmController.changesLocked

    SettingsScaffold(stringResource(R.string.settings_title), navigator) {
        Section(R.string.settings_section_times) {
            ChoiceRow(stringResource(R.string.settings_method), CalculationMethodOption.entries, settings.method, { stringResource(it.title) }) { value ->
                guard.update { it.copy(method = value) }
            }
            Divider()
            ChoiceRow(stringResource(R.string.settings_madhab), MadhabOption.entries, settings.madhab, { stringResource(it.title) }) { value ->
                guard.update { it.copy(madhab = value) }
            }
            Divider()
            NavRow(stringResource(R.string.settings_location), locationLabel(settings)) { navigator.open(Screen.LOCATION) }
            Divider()
            NavRow(stringResource(R.string.settings_offsets)) { navigator.open(Screen.OFFSETS) }
        }

        Section(
            R.string.settings_section_alarm,
            listOf(stringResource(R.string.settings_alarmLimit_footer), stringResource(R.string.settings_delay_footer)),
        ) {
            Prayer.entries.forEach { prayer ->
                SwitchRow(context.prayerName(prayer), settings.isAlarmEnabled(prayer)) { enabled ->
                    val change = { s: AppSettings -> s.copy(alarmEnabled = s.alarmEnabled + (prayer.key to enabled)) }
                    if (enabled) {
                        AlarmController.updateSettings(
                            change,
                        )
                    } else {
                        guard.run(AlarmController.disablingNeedsChallenge(prayer)) { AlarmController.updateSettings(change) }
                    }
                }
                Divider()
            }
            StepperRow(
                stringResource(R.string.settings_delay),
                stringResource(R.string.common_minutes, settings.delayMinutes),
                settings.delayMinutes > AppSettings.DELAY_RANGE.first,
                settings.delayMinutes < AppSettings.DELAY_RANGE.last,
            ) { step -> guard.update { it.copy(delayMinutes = it.delayMinutes + step) } }
            Divider()
            ChoiceRow(stringResource(R.string.settings_sound), AlarmSound.entries, settings.sound, { stringResource(it.title) }) { value ->
                AlarmController.updateSettings { it.copy(sound = value) }
            }
            Divider()
            NavRow(stringResource(R.string.settings_sound_preview)) { AlarmController.previewSound() }
            Divider()
            SwitchRow(stringResource(R.string.settings_notifyAtTime), settings.notifyAtPrayerTime) { value ->
                AlarmController.updateSettings { it.copy(notifyAtPrayerTime = value) }
            }
        }

        Section(
            R.string.settings_section_task,
            listOf(stringResource(R.string.settings_task_footer), stringResource(R.string.settings_recitation_footer)),
        ) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                TaskKind.entries.forEachIndexed { index, kind ->
                    SegmentedButton(
                        selected = settings.task == kind,
                        onClick = { AlarmController.updateSettings { it.copy(task = kind) } },
                        shape = SegmentedButtonDefaults.itemShape(index, TaskKind.entries.size),
                    ) { Text(stringResource(kind.title)) }
                }
            }
            Divider()
            NavRow(stringResource(R.string.settings_references)) { navigator.open(Screen.REFERENCES) }
            Divider()
            ChoiceRow(stringResource(R.string.settings_recitation), RecitationChoice.entries, settings.recitation, { stringResource(it.title) }) { value ->
                guard.update { it.copy(recitation = value) }
            }
        }

        val reliabilityFooter =
            buildList {
                add(stringResource(R.string.settings_keepAlive_footer))
                add(stringResource(R.string.settings_wakeCheck_footer))
                if (locked) add(LOCK_MARK + stringResource(R.string.settings_locked_footer))
            }
        Section(R.string.settings_section_reliability, reliabilityFooter) {
            SwitchRow(stringResource(R.string.settings_keepAlive), settings.keepAlive) { value ->
                guard.update { it.copy(keepAlive = value) }
                val power = context.getSystemService(PowerManager::class.java)
                if (value && !power.isIgnoringBatteryOptimizations(context.packageName)) {
                    runCatching { context.startActivity(requestIgnoreBatteryOptimizations(context)) }
                }
            }
            Divider()
            SwitchRow(stringResource(R.string.settings_wakeCheck), settings.wakeCheck) { value -> guard.update { it.copy(wakeCheck = value) } }
            Divider()
            NavRow(
                stringResource(R.string.pause_title),
                if (settings.activePause(System.currentTimeMillis()) !=
                    null
                ) {
                    stringResource(R.string.pause_on)
                } else {
                    null
                },
            ) {
                navigator.open(Screen.PAUSE)
            }
            Divider()
            NavRow(stringResource(R.string.settings_test)) {
                navigator.home()
                AlarmController.startTestAlarm()
            }
            Divider()
            NavRow(stringResource(R.string.common_openSettings), onClick = rememberOpenAppSettings())
        }

        Section(R.string.settings_section_about) {
            ValueRow(stringResource(R.string.app_name), stringResource(R.string.about_version, BuildConfig.VERSION_NAME))
            Divider()
            NavRow(stringResource(R.string.about_channel), "t.me/huicoding") { openUrl(context, CHANNEL_URL) }
            Divider()
            NavRow(stringResource(R.string.about_source), "GitHub") { openUrl(context, REPO_URL) }
        }
    }
}

private fun openUrl(
    context: android.content.Context,
    url: String,
) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

@Composable
private fun locationLabel(settings: AppSettings): String =
    settings.location?.let { it.name ?: String.format(Locale.ROOT, "%.3f, %.3f", it.latitude, it.longitude) }
        ?: stringResource(R.string.settings_location_none)

// Ручная корректировка

@Composable
fun OffsetsScreen(navigator: Navigator) {
    val context = LocalContext.current
    val guard = LocalGuard.current
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    val minutes = stringResource(R.string.common_min)
    SettingsScaffold(stringResource(R.string.settings_offsets), navigator) {
        Section(null, listOf(stringResource(R.string.offsets_footer))) {
            Prayer.entries.forEachIndexed { index, prayer ->
                if (index > 0) Divider()
                val value = settings.offset(prayer)
                StepperRow(
                    context.prayerName(prayer),
                    if (value == 0) "0" else String.format(Locale.getDefault(), "%+d %s", value, minutes),
                    value > AppSettings.OFFSET_RANGE.first,
                    value < AppSettings.OFFSET_RANGE.last,
                ) { step -> guard.update { it.copy(offsetMinutes = it.offsetMinutes + (prayer.key to value + step)) } }
            }
        }
        Section(null) {
            NavRow(stringResource(R.string.offsets_reset)) { guard.update { it.copy(offsetMinutes = emptyMap()) } }
        }
    }
}

// Местоположение

@Composable
fun LocationPickerScreen(navigator: Navigator) {
    val context = LocalContext.current
    val guard = LocalGuard.current
    val scope = rememberCoroutineScope()
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    val error by AlarmController.locationError.collectAsStateWithLifecycle()
    var locating by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Address>>(emptyList()) }
    var searchMessage by remember { mutableStateOf<Int?>(null) }
    var searching by remember { mutableStateOf(false) }
    var latitude by remember { mutableStateOf(settings.location?.let { String.format(Locale.ROOT, "%.4f", it.latitude) }.orEmpty()) }
    var longitude by remember { mutableStateOf(settings.location?.let { String.format(Locale.ROOT, "%.4f", it.longitude) }.orEmpty()) }
    var searchJob by remember { mutableStateOf<Job?>(null) }

    // Другое место сдвигает время намаза, поэтому рядом с будильником — только через испытание.
    fun apply(
        location: SavedLocation,
        close: Boolean,
    ) {
        val change = { s: AppSettings -> s.copy(location = location) }
        guard.run(AlarmController.needsChallenge(change)) {
            AlarmController.updateSettings(change)
            AlarmController.clearLocationError()
            latitude = String.format(Locale.ROOT, "%.4f", location.latitude)
            longitude = String.format(Locale.ROOT, "%.4f", location.longitude)
            if (close) navigator.back()
        }
    }

    LaunchedEffect(query) {
        val text = query.trim()
        if (text.length < 2) {
            results = emptyList()
            searchMessage = null
            return@LaunchedEffect
        }
        delay(SEARCH_DEBOUNCE)
        searching = true
        val found = LocationService.search(context, text)
        searching = false
        results = found.orEmpty().filter { it.hasLatitude() && it.hasLongitude() }
        searchMessage =
            when {
                found == null -> R.string.location_search_unavailable
                results.isEmpty() -> R.string.location_search_empty
                else -> null
            }
    }

    SettingsScaffold(stringResource(R.string.settings_location), navigator) {
        Section(R.string.location_current) {
            ValueRow(
                settings.location?.name ?: stringResource(R.string.settings_location_none),
                settings.location?.let { String.format(Locale.ROOT, "%.4f, %.4f", it.latitude, it.longitude) },
            )
            Divider()
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(enabled = !locating) {
                    locating = true
                    searchJob?.cancel()
                    scope.launch {
                        AlarmController.locateCurrent()?.let { apply(it, close = false) }
                        locating = false
                    }
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.MyLocation, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.location_useCurrent), Modifier.weight(1f), color = MaterialTheme.colorScheme.primary)
                if (locating) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            }
            error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(bottom = 12.dp),
                )
            }
        }

        Section(R.string.location_search) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                trailingIcon = { if (searching) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) },
                placeholder = { Text(stringResource(R.string.location_search_placeholder)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            )
            searchMessage?.let {
                Text(
                    stringResource(it),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(bottom = 12.dp),
                )
            }
            results.forEach { address ->
                Divider()
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable {
                            apply(SavedLocation(address.latitude, address.longitude, address.locality ?: address.featureName), close = true)
                        }.padding(vertical = 10.dp),
                ) {
                    Text(address.locality ?: address.featureName ?: "—")
                    listOfNotNull(address.adminArea, address.countryName).joinToString(", ").takeIf { it.isNotEmpty() }?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        val parsed = CoordinateParser.parse(latitude, longitude)
        Section(R.string.location_coordinates, listOf(stringResource(R.string.location_coordinates_footer))) {
            OutlinedTextField(
                latitude,
                { latitude = it },
                label = { Text(stringResource(R.string.location_latitude)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            )
            OutlinedTextField(
                longitude,
                { longitude = it },
                label = { Text(stringResource(R.string.location_longitude)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )
            Button(
                onClick = { parsed?.let { (lat, lon) -> apply(SavedLocation(lat, lon), close = true) } },
                enabled = parsed != null,
                modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
            ) { Text(stringResource(R.string.location_coordinates_save)) }
        }
    }
}

private const val SEARCH_DEBOUNCE = 400L

// Эталонные фото

@Composable
fun ReferencePhotosScreen(navigator: Navigator) {
    val context = LocalContext.current
    val store = remember { ReferenceStore(context) }
    var version by remember { mutableIntStateOf(0) }
    var capturing by remember { mutableStateOf<TaskKind?>(null) }
    SettingsScaffold(stringResource(R.string.settings_references), navigator) {
        Section(null, listOf(stringResource(R.string.references_footer))) {
            listOf(TaskKind.RUG, TaskKind.SINK).forEachIndexed { index, kind ->
                if (index > 0) Divider()
                val saved = remember(version) { store.hasReference(kind) }
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(kind.title))
                        Text(
                            stringResource(if (saved) R.string.references_saved else R.string.references_none),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (saved) {
                        IconButton(onClick = {
                            store.remove(kind)
                            version += 1
                        }) { Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.common_delete), tint = MaterialTheme.colorScheme.error) }
                    }
                    TextButton(onClick = { capturing = kind }) {
                        Text(stringResource(if (saved) R.string.references_retake else R.string.references_take))
                    }
                }
            }
        }
    }
    capturing?.let { kind ->
        ReferenceCaptureDialog(kind, store) {
            capturing = null
            version += 1
        }
    }
}

@Composable
private fun ReferenceCaptureDialog(
    kind: TaskKind,
    store: ReferenceStore,
    close: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val handle = remember { CameraHandle() }
    var state by remember { mutableStateOf(CameraState.IDLE) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DialogSystemBars(lightBackground = false)
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (state == CameraState.DENIED) {
                Text(stringResource(R.string.camera_denied), color = Color.White, modifier = Modifier.align(Alignment.Center).padding(32.dp))
            } else {
                CameraPreview(handle, active = true, onState = { state = it }, modifier = Modifier.fillMaxSize())
            }
            Column(Modifier.fillMaxSize().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
                    TextButton(onClick = close) { Text(stringResource(R.string.common_cancel), color = Color.White) }
                }
                Text(stringResource(kind.instruction), color = Color.White, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(24.dp))
                Spacer(Modifier.weight(1f))
                error?.let {
                    Text(
                        stringResource(it),
                        color = Color.White,
                        modifier = Modifier.background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(12.dp)).padding(12.dp),
                    )
                    Spacer(Modifier.size(12.dp))
                }
                ShutterButton(busy, enabled = state == CameraState.RUNNING) {
                    busy = true
                    error = null
                    scope.launch {
                        val photo = handle.takePhoto(context)
                        val issue = photo?.let { ObjectVerifier.quality(it)?.issue }
                        when {
                            photo == null -> error = R.string.verify_notRecognized
                            issue != null -> error = issue.message
                            else ->
                                runCatching { store.save(photo, kind) }
                                    .onSuccess { comparable -> if (comparable) close() else error = R.string.references_compare_unavailable }
                                    .onFailure { error = R.string.references_saveError }
                        }
                        busy = false
                    }
                }
            }
        }
    }
}

@get:StringRes
val ImageQuality.Issue.message: Int
    get() =
        when (this) {
            ImageQuality.Issue.TOO_DARK -> R.string.verify_tooDark
            ImageQuality.Issue.TOO_BRIGHT -> R.string.verify_tooBright
            ImageQuality.Issue.UNIFORM -> R.string.verify_uniform
            ImageQuality.Issue.BLURRY -> R.string.verify_blurry
        }

// Пауза

@Composable
fun PauseScreen(navigator: Navigator) {
    val context = LocalContext.current
    val guard = LocalGuard.current
    val settings by AlarmController.store.settings.collectAsStateWithLifecycle()
    var hours by remember { mutableIntStateOf(3) }
    val until = settings.activePause(System.currentTimeMillis())
    SettingsScaffold(stringResource(R.string.pause_title), navigator) {
        if (until != null) {
            Section(null, listOf(stringResource(R.string.pause_active_footer))) {
                Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.PauseCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text(stringResource(R.string.pause_active), fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.pause_until, context.formatDateTime(until)), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Divider()
                NavRow(stringResource(R.string.pause_resume)) { AlarmController.resume() }
            }
        } else {
            Section(null, listOf(stringResource(R.string.pause_footer, PauseChallenge.ROUNDS, PauseChallenge.PENALTY))) {
                ChoiceRow(
                    stringResource(R.string.pause_duration),
                    PAUSE_DURATIONS.map { it.first },
                    hours,
                    { value -> stringResource(PAUSE_DURATIONS.first { it.first == value }.second) },
                ) { hours = it }
                Divider()
                // Пауза включается только после испытания — всегда, а не только за час до будильника.
                NavRow(stringResource(R.string.pause_start)) { guard.run(true) { AlarmController.pause(hours * 3600_000L) } }
            }
        }
    }
}
