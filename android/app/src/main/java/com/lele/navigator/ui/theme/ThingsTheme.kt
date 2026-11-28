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
    val allDark: Color,
    val completedGray: Color,
    val danger: Color,
    val dangerSoft: Color
)

private val LightThingsColors = ThingsColors(
    isDark = false,
    listBackground = Color(0xFFFFFFFF),
    hubBackground = Color(0xFFF2F2F7),
    cardSurface = Color(0xFFFFFFFF),
    elevatedSurface = Color(0xFFF7F7FA),
    subtleFill = Color(0xFFE9E9EE),
    divider = Color(0xFFE5E5EA),
    inkPrimary = Color(0xFF1C1C1E),
    inkSecondary = Color(0xFF6C6C70),
    inkTertiary = Color(0xFFAEAEB2),
    checkboxBorder = Color(0xFFC7C7CC),
    accentBlue = Color(0xFF007AFF),
    accentBlueSoft = Color(0xFFE5F1FF),
    todayGold = Color(0xFFFF9500),
    todayGoldSoft = Color(0xFFFFF3E0),
    inboxBlue = Color(0xFF007AFF),
    upcomingCoral = Color(0xFFFF3B30),
    upcomingCoralSoft = Color(0xFFFFEBEA),
    logbookGreen = Color(0xFF34C759),
    logbookGreenSoft = Color(0xFFE8F9ED),
    allDark = Color(0xFF3A3A3C),
    completedGray = Color(0xFF636366),
    danger = Color(0xFFFF3B30),
    dangerSoft = Color(0xFFFFEBEA)
)

private val DarkThingsColors = ThingsColors(
    isDark = true,
    listBackground = Color(0xFF000000),
    hubBackground = Color(0xFF000000),
    cardSurface = Color(0xFF1C1C1E),
    elevatedSurface = Color(0xFF2C2C2E),
    subtleFill = Color(0xFF2C2C2E),
    divider = Color(0xFF38383A),
    inkPrimary = Color(0xFFFFFFFF),
    inkSecondary = Color(0xFF98989D),
    inkTertiary = Color(0xFF636366),
    checkboxBorder = Color(0xFF545458),
    accentBlue = Color(0xFF0A84FF),
    accentBlueSoft = Color(0xFF162A42),
    todayGold = Color(0xFFFF9F0A),
    todayGoldSoft = Color(0xFF362812),
    inboxBlue = Color(0xFF0A84FF),
    upcomingCoral = Color(0xFFFF453A),
    upcomingCoralSoft = Color(0xFF3A1A1A),
    logbookGreen = Color(0xFF30D158),
    logbookGreenSoft = Color(0xFF15331E),
    allDark = Color(0xFF636366),
    completedGray = Color(0xFF8E8E93),
    danger = Color(0xFFFF453A),
    dangerSoft = Color(0xFF3A1A1A)
)

val LocalThingsColors = staticCompositionLocalOf { LightThingsColors }

object ThingsTheme {
    val colors: ThingsColors
        @Composable get() = LocalThingsColors.current
}

private val ThingsTypography = Typography(
    headlineLarge = TextStyle(
        fontSize = 30.sp,
        lineHeight = 36.sp,
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
