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

/** Палитра оригинального iOS-дизайна: AccentColor, системные светлые и тёмные фоны. */
object Brand {
    val Green = Color(0xFF1D6347)
    val GreenLight = Color(0xFF5FBF92)
    val Gold = Color(0xFFC9A95C)
    val Cream = Color(0xFFF1EBDD)
    val Ruby = Color(0xFFB3261E)

    /** Прочитанные слова и прогресс чтения (в iOS — синий акцент чтения). */
    val Read = Color(0xFF2E7D5B)
    val Skipped = Color(0xFFE08A1E)
}

// systemGroupedBackground / secondarySystemGroupedBackground из iOS.
private val LightColors =
    lightColorScheme(
        primary = Brand.Green,
        onPrimary = Color.White,
        primaryContainer = Color(0xFFD5E8DC),
        onPrimaryContainer = Color(0xFF10251C),
        secondary = Color(0xFF8A6D2B),
        secondaryContainer = Color(0xFFF2E6C6),
        background = Color(0xFFF2F2F7),
        onBackground = Color.Black,
        surface = Color(0xFFF2F2F7),
        onSurface = Color.Black,
        surfaceContainer = Color.White,
        surfaceContainerHigh = Color.White,
        surfaceVariant = Color(0xFFE5E5EA),
        onSurfaceVariant = Color(0xFF6C6C70),
        outlineVariant = Color(0xFFD1D1D6),
        error = Brand.Ruby,
    )

private val DarkColors =
    darkColorScheme(
        primary = Brand.GreenLight,
        onPrimary = Color.Black,
        primaryContainer = Color(0xFF1E4A38),
        onPrimaryContainer = Color(0xFFD5E8DC),
        secondary = Brand.Gold,
        secondaryContainer = Color(0xFF4A3D1E),
        background = Color.Black,
        onBackground = Color.White,
        surface = Color.Black,
        onSurface = Color.White,
        surfaceContainer = Color(0xFF1C1C1E),
        surfaceContainerHigh = Color(0xFF2C2C2E),
        surfaceVariant = Color(0xFF2C2C2E),
        onSurfaceVariant = Color(0xFF98989D),
        outlineVariant = Color(0xFF38383A),
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
