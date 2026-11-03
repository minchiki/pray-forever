package com.prayforever.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.prayforever.app.R
import com.prayforever.app.core.Prayer
import com.prayforever.app.core.PrayerTimeCalculator
import com.prayforever.app.data.SettingsStore
import com.prayforever.app.ui.MainActivity
import com.prayforever.app.ui.formatTime
import com.prayforever.app.ui.prayerName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.LocalDate

/** Виджет: ближайший намаз, а на широком виджете — ещё и расписание на сегодня. */
class PrayerWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    override suspend fun provideGlance(
        context: Context,
        id: GlanceId,
    ) {
        val state = WidgetState.load(context)
        provideContent { GlanceTheme { Content(state) } }
    }

    @Composable
    private fun Content(state: WidgetState) {
        val context = LocalContext.current
        val wide = LocalSize.current.width >= WIDE.width
        Column(
            modifier =
                GlanceModifier
                    .fillMaxSize()
                    .background(Palette.background)
                    .cornerRadius(20.dp)
                    .padding(14.dp)
                    .clickable(actionStartActivity<MainActivity>()),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            when {
                state.pausedUntil != null -> {
                    Text(context.getString(R.string.pause_active), style = TextStyle(color = Palette.text, fontWeight = FontWeight.Bold))
                    Text(context.getString(R.string.pause_until, context.formatTime(state.pausedUntil)), style = TextStyle(color = Palette.secondary))
                }
                state.next == null -> Text(context.getString(R.string.widget_noLocation), style = TextStyle(color = Palette.secondary))
                else -> {
                    Text(context.getString(R.string.home_next), style = TextStyle(color = Palette.secondary, fontSize = 12.sp))
                    Text(context.prayerName(state.next.first), style = TextStyle(color = Palette.text, fontWeight = FontWeight.Medium, fontSize = 16.sp))
                    Text(context.formatTime(state.next.second), style = TextStyle(color = Palette.accent, fontWeight = FontWeight.Bold, fontSize = 30.sp))
                    if (wide) {
                        Spacer(GlanceModifier.height(6.dp))
                        state.today.forEach { (prayer, time) ->
                            val isNext = prayer == state.next.first && time == state.next.second
                            Row(GlanceModifier.fillMaxWidth()) {
                                val style =
                                    TextStyle(
                                        color = if (isNext) Palette.accent else Palette.text,
                                        fontWeight = if (isNext) FontWeight.Bold else FontWeight.Normal,
                                        fontSize = 13.sp,
                                    )
                                Text(context.prayerName(prayer), style = style, modifier = GlanceModifier.defaultWeight())
                                Text(context.formatTime(time), style = style)
                            }
                        }
                    }
                }
            }
        }
    }

    private data class WidgetState(
        val next: Pair<Prayer, Long>?,
        val today: List<Pair<Prayer, Long>>,
        val pausedUntil: Long?,
    ) {
        companion object {
            fun load(context: Context): WidgetState {
                val settings = SettingsStore(context).settings.value
                val now = System.currentTimeMillis()
                val calculator = PrayerTimeCalculator()
                val next = calculator.instances(now, 2, settings).firstOrNull { it.prayerTime > now }
                val today =
                    calculator
                        .times(LocalDate.now(), settings)
                        .orEmpty()
                        .toList()
                        .sortedBy { it.second }
                return WidgetState(next?.let { it.prayer to it.prayerTime }, today, settings.activePause(now))
            }
        }
    }

    private object Palette {
        val background = ColorProvider(day = Color.White, night = Color(0xFF1C1C1E))
        val text = ColorProvider(day = Color.Black, night = Color.White)
        val secondary = ColorProvider(day = Color(0xFF6C6C70), night = Color(0xFF98989D))
        val accent = ColorProvider(day = Color(0xFF1D6347), night = Color(0xFF5FBF92))
    }

    companion object {
        private val SMALL = DpSize(110.dp, 110.dp)
        private val WIDE = DpSize(220.dp, 110.dp)
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        fun requestUpdate(context: Context) {
            val app = context.applicationContext
            scope.launch { runCatching { PrayerWidget().updateAll(app) } }
        }
    }
}

class PrayerWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = PrayerWidget()
}
