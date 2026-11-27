package com.lele.navigator.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lele.navigator.ui.theme.ThingsTheme

/**
 * Things 3 signature rounded-square checkbox with spring micro-animation and haptic feedback.
 */
@Composable
fun ThingsCheckbox(
    checked: Boolean,
    onCheckedChange: () -> Unit,
    modifier: Modifier = Modifier,
    isDoing: Boolean = false,
    isCircular: Boolean = false,
    size: Dp = 20.dp
) {
    val c = ThingsTheme.colors
    val haptic = LocalHapticFeedback.current
    val shape = if (isCircular) CircleShape else RoundedCornerShape(6.dp)

    val fillColor by animateColorAsState(
        targetValue = when {
            checked -> c.accentBlue
            else -> Color.Transparent
        },
        label = "cbFill"
    )
    val borderColor by animateColorAsState(
        targetValue = when {
            checked -> c.accentBlue
            isDoing -> c.doingBlue
            else -> c.checkboxBorder
        },
        label = "cbBorder"
    )
    val scale by animateFloatAsState(
        targetValue = if (checked) 1f else 0.98f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium
        ),
        label = "cbScale"
    )

    Box(
        modifier = modifier
            .size(40.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                onCheckedChange()
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(size)
                .scale(scale)
                .clip(shape)
                .background(fillColor)
                .border(
                    width = if (checked) 0.dp else 1.6.dp,
                    color = borderColor,
                    shape = shape
                ),
            contentAlignment = Alignment.Center
        ) {
            if (checked) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = "已完成",
                    tint = Color.White,
                    modifier = Modifier.size(size * 0.66f)
                )
            }
        }
    }
}

/**
 * Things 3 signature circular blue Magic Plus floating action button.
 */
@Composable
fun ThingsMagicFab(
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val c = ThingsTheme.colors
    val haptic = LocalHapticFeedback.current

    Surface(
        onClick = {
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onClick()
        },
        shape = CircleShape,
        color = c.accentBlue,
        contentColor = Color.White,
        modifier = modifier
            .size(56.dp)
            .shadow(
                elevation = 10.dp,
                shape = CircleShape,
                ambientColor = c.accentBlue.copy(alpha = 0.45f),
                spotColor = c.accentBlue.copy(alpha = 0.45f)
            )
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = Icons.Rounded.Add,
                contentDescription = "新建任务",
                tint = Color.White,
                modifier = Modifier.size(28.dp)
            )
        }
    }
}

/**
 * Tiny Things-style circular progress pie/ring for subtask checklist progress.
 */
@Composable
fun MiniProgressRing(
    done: Int,
    total: Int,
    modifier: Modifier = Modifier
) {
    val c = ThingsTheme.colors
    val fraction = if (total > 0) (done.toFloat() / total.toFloat()).coerceIn(0f, 1f) else 0f
    val trackColor = c.checkboxBorder.copy(alpha = 0.6f)
    val fillColor = if (done == total && total > 0) c.logbookGreen else c.accentBlue

    Canvas(modifier = modifier.size(12.dp)) {
        val stroke = 1.6.dp.toPx()
        drawCircle(
            color = trackColor,
            style = Stroke(width = stroke)
        )
        if (fraction > 0f) {
            drawArc(
                color = fillColor,
                startAngle = -90f,
                sweepAngle = 360f * fraction,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round)
            )
        }
    }
}

/**
 * Clean pill badge used across task rows, detail editors, and capture sheets.
 */
@Composable
fun ThingsPill(
    text: String,
    textColor: Color,
    backgroundColor: Color,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    dotColor: Color? = null,
    onClick: (() -> Unit)? = null
) {
    val shape = RoundedCornerShape(7.dp)
    val base = modifier
        .clip(shape)
        .background(backgroundColor)
        .let { if (onClick != null) it.clickable(onClick = onClick) else it }
        .padding(horizontal = 8.dp, vertical = 4.dp)

    Row(
        modifier = base,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        if (dotColor != null) {
            Box(
                Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(dotColor)
            )
        }
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = textColor,
                modifier = Modifier.size(12.dp)
            )
        }
        Text(
            text = text,
            color = textColor,
            fontSize = 11.5.sp,
            fontWeight = FontWeight.Medium,
            lineHeight = 14.sp
        )
    }
}

/**
 * Whisper-quiet section header in Things 3 style.
 */
@Composable
fun ThingsSectionHeader(
    title: String,
    count: Int? = null,
    accentColor: Color? = null,
    modifier: Modifier = Modifier
) {
    val c = ThingsTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = title,
            color = accentColor ?: c.inkSecondary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.1.sp
        )
        if (count != null && count > 0) {
            Text(
                text = "$count",
                color = (accentColor ?: c.inkTertiary).copy(alpha = 0.8f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Hairline inset divider matching Things 3 list rhythm.
 */
@Composable
fun ThingsDivider(
    insetStart: Dp = 0.dp,
    modifier: Modifier = Modifier
) {
    val c = ThingsTheme.colors
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = insetStart)
            .height(0.6.dp)
            .background(c.divider)
    )
}
