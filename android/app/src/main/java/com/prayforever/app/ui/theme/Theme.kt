package com.prayforever.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily

/** Палитра из иконки: зелень михраба, золото орнамента, кремовый фон, красный коврика. */
object Brand {
    val Green = Color(0xFF1D6347)
    val GreenLight = Color(0xFF5FBF92)
    val Gold = Color(0xFFC9A95C)
    val Cream = Color(0xFFF1EBDD)
    val Ink = Color(0xFF10251C)
    val Night = Color(0xFF0E1A15)
    val NightCard = Color(0xFF17261F)
    val Ruby = Color(0xFFB3261E)

    /** Прочитанные слова и прогресс чтения. */
    val Read = Color(0xFF2E7D5B)
    val Skipped = Color(0xFFE08A1E)
}

private val LightColors =
    lightColorScheme(
        primary = Brand.Green,
        onPrimary = Color.White,
        primaryContainer = Color(0xFFD5E8DC),
        onPrimaryContainer = Brand.Ink,
        secondary = Color(0xFF8A6D2B),
        secondaryContainer = Color(0xFFF2E6C6),
        background = Color(0xFFF6F2E8),
        onBackground = Brand.Ink,
        surface = Color(0xFFF6F2E8),
        onSurface = Brand.Ink,
        surfaceContainer = Color.White,
        surfaceContainerHigh = Color(0xFFFFFDF8),
        surfaceVariant = Color(0xFFE9E3D4),
        onSurfaceVariant = Color(0xFF5B6B63),
        outlineVariant = Color(0xFFDDD5C3),
        error = Brand.Ruby,
    )

private val DarkColors =
    darkColorScheme(
        primary = Brand.GreenLight,
        onPrimary = Brand.Night,
        primaryContainer = Color(0xFF1E4A38),
        onPrimaryContainer = Color(0xFFD5E8DC),
        secondary = Brand.Gold,
        secondaryContainer = Color(0xFF4A3D1E),
        background = Brand.Night,
        onBackground = Brand.Cream,
        surface = Brand.Night,
        onSurface = Brand.Cream,
        surfaceContainer = Brand.NightCard,
        surfaceContainerHigh = Color(0xFF1C2D25),
        surfaceVariant = Color(0xFF22332B),
        onSurfaceVariant = Color(0xFFA9B5AE),
        outlineVariant = Color(0xFF2C3E35),
        error = Color(0xFFF2B8B5),
    )

@Composable
fun PrayerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        typography = Typography(),
        content = content,
    )
}

/** Шрифт Корана Amiri Quran (OFL) — тот же файл, что в iOS-версии. */
@Composable
fun rememberQuranFont(): FontFamily {
    val assets = LocalContext.current.assets
    return remember(assets) { FontFamily(Font("AmiriQuran-Regular.ttf", assets)) }
}
