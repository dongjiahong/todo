package com.lele.navigator.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

@Immutable
data class ThingsColors(
    val isDark: Boolean,
    val listBackground: Color,
    val hubBackground: Color,
    val cardSurface: Color,
    val elevatedSurface: Color,
    val subtleFill: Color,
    val divider: Color,
    val inkPrimary: Color,
    val inkSecondary: Color,
    val inkTertiary: Color,
    val checkboxBorder: Color,
    val accentBlue: Color,
    val accentBlueSoft: Color,
    val todayGold: Color,
    val todayGoldSoft: Color,
    val inboxBlue: Color,
    val upcomingCoral: Color,
    val upcomingCoralSoft: Color,
    val logbookGreen: Color,
    val logbookGreenSoft: Color,
    val doingBlue: Color,
    val doingBlueSoft: Color,
    val danger: Color,
    val dangerSoft: Color
)

private val LightThingsColors = ThingsColors(
    isDark = false,
    listBackground = Color(0xFFFFFFFF),
    hubBackground = Color(0xFFF3F4F7),
    cardSurface = Color(0xFFFFFFFF),
    elevatedSurface = Color(0xFFF7F8FA),
    subtleFill = Color(0xFFF0F2F6),
    divider = Color(0xFFEBEEF2),
    inkPrimary = Color(0xFF1A1D24),
    inkSecondary = Color(0xFF6B7280),
    inkTertiary = Color(0xFF9CA3AF),
    checkboxBorder = Color(0xFFC3C9D4),
    accentBlue = Color(0xFF3178F6),
    accentBlueSoft = Color(0xFFEBF2FE),
    todayGold = Color(0xFFF2A900),
    todayGoldSoft = Color(0xFFFEF6E0),
    inboxBlue = Color(0xFF3A82F6),
    upcomingCoral = Color(0xFFE5484D),
    upcomingCoralSoft = Color(0xFFFDECEC),
    logbookGreen = Color(0xFF28A76E),
    logbookGreenSoft = Color(0xFFE8F7F0),
    doingBlue = Color(0xFF3178F6),
    doingBlueSoft = Color(0xFFEBF2FE),
    danger = Color(0xFFE5484D),
    dangerSoft = Color(0xFFFDECEC)
)

private val DarkThingsColors = ThingsColors(
    isDark = true,
    listBackground = Color(0xFF16181D),
    hubBackground = Color(0xFF101216),
    cardSurface = Color(0xFF1E2128),
    elevatedSurface = Color(0xFF252932),
    subtleFill = Color(0xFF282C36),
    divider = Color(0xFF2A2E38),
    inkPrimary = Color(0xFFF2F4F8),
    inkSecondary = Color(0xFF9BA3B0),
    inkTertiary = Color(0xFF68707E),
    checkboxBorder = Color(0xFF4E5565),
    accentBlue = Color(0xFF4C8DF6),
    accentBlueSoft = Color(0xFF1E2B42),
    todayGold = Color(0xFFF5B82E),
    todayGoldSoft = Color(0xFF332A16),
    inboxBlue = Color(0xFF5698FA),
    upcomingCoral = Color(0xFFF25F5C),
    upcomingCoralSoft = Color(0xFF381E20),
    logbookGreen = Color(0xFF34C282),
    logbookGreenSoft = Color(0xFF193026),
    doingBlue = Color(0xFF4C8DF6),
    doingBlueSoft = Color(0xFF1E2B42),
    danger = Color(0xFFF25F5C),
    dangerSoft = Color(0xFF381E20)
)

val LocalThingsColors = staticCompositionLocalOf { LightThingsColors }

object ThingsTheme {
    val colors: ThingsColors
        @Composable get() = LocalThingsColors.current
}

private val ThingsTypography = Typography(
    headlineLarge = TextStyle(
        fontSize = 28.sp,
        lineHeight = 34.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.4).sp
    ),
    headlineMedium = TextStyle(
        fontSize = 22.sp,
        lineHeight = 28.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.3).sp
    ),
    titleLarge = TextStyle(
        fontSize = 19.sp,
        lineHeight = 26.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = (-0.2).sp
    ),
    titleMedium = TextStyle(
        fontSize = 16.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = (-0.1).sp
    ),
    titleSmall = TextStyle(
        fontSize = 14.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.SemiBold
    ),
    bodyLarge = TextStyle(
        fontSize = 15.5.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.Normal
    ),
    bodyMedium = TextStyle(
        fontSize = 14.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.Normal
    ),
    bodySmall = TextStyle(
        fontSize = 12.5.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Normal
    ),
    labelLarge = TextStyle(
        fontSize = 13.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.SemiBold
    ),
    labelMedium = TextStyle(
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Medium
    ),
    labelSmall = TextStyle(
        fontSize = 11.sp,
        lineHeight = 14.sp,
        fontWeight = FontWeight.Medium
    )
)

@Composable
fun NavigatorThingsTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val thingsColors = if (darkTheme) DarkThingsColors else LightThingsColors
    val m3Scheme = if (darkTheme) {
        darkColorScheme(
            primary = thingsColors.accentBlue,
            onPrimary = Color.White,
            secondary = thingsColors.logbookGreen,
            background = thingsColors.listBackground,
            onBackground = thingsColors.inkPrimary,
            surface = thingsColors.cardSurface,
            onSurface = thingsColors.inkPrimary,
            surfaceVariant = thingsColors.elevatedSurface,
            onSurfaceVariant = thingsColors.inkSecondary,
            outline = thingsColors.divider,
            error = thingsColors.danger,
            onError = Color.White
        )
    } else {
        lightColorScheme(
            primary = thingsColors.accentBlue,
            onPrimary = Color.White,
            secondary = thingsColors.logbookGreen,
            background = thingsColors.listBackground,
            onBackground = thingsColors.inkPrimary,
            surface = thingsColors.cardSurface,
            onSurface = thingsColors.inkPrimary,
            surfaceVariant = thingsColors.elevatedSurface,
            onSurfaceVariant = thingsColors.inkSecondary,
            outline = thingsColors.divider,
            error = thingsColors.danger,
            onError = Color.White
        )
    }

    CompositionLocalProvider(LocalThingsColors provides thingsColors) {
        MaterialTheme(
            colorScheme = m3Scheme,
            typography = ThingsTypography,
            content = content
        )
    }
}
