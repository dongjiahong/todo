package com.lele.navigator.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lele.navigator.model.DateUtils
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.theme.ThingsTheme
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

/**
 * Things 3-inspired Date, Time & Repeat bottom sheet.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DueDateSheet(
    currentDue: String?,
    currentRepeat: String?,
    onApply: (String?, String?) -> Unit,
    onDismiss: () -> Unit
) {
    val c = ThingsTheme.colors
    val parsed = remember(currentDue) { DateUtils.parseDue(currentDue) }
    var selectedDate by remember { mutableStateOf(parsed?.toLocalDate() ?: LocalDate.now()) }
    var displayedMonth by remember { mutableStateOf(YearMonth.from(selectedDate)) }
    var hour by remember { mutableStateOf(parsed?.hour ?: 18) }
    var minute by remember { mutableStateOf(parsed?.minute ?: 0) }
    var repeatRule by remember { mutableStateOf(currentRepeat ?: "") }

    val fmt = remember { DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm") }
    fun buildIso(): String =
        LocalDateTime.of(selectedDate.year, selectedDate.month, selectedDate.dayOfMonth, hour, minute).format(fmt)

    fun adjustMinutes(delta: Int) {
        var total = hour * 60 + minute + delta
        if (total < 0) total += 24 * 60
        total %= (24 * 60)
        hour = total / 60
        minute = total % 60
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.cardSurface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = {
            Box(
                modifier = Modifier
                    .padding(top = 10.dp, bottom = 6.dp)
                    .width(36.dp)
                    .height(4.dp)
                    .clip(CircleShape)
                    .background(c.divider)
            )
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "何时",
                    color = c.inkPrimary,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.weight(1f))
                if (currentDue != null) {
                    Text(
                        text = "清除",
                        color = c.danger,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .clickable {
                                onApply(null, null)
                                onDismiss()
                            }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }

            // 1. Quick 2x2 Presets
            val today = LocalDate.now()
            val tomorrow = today.plusDays(1)
            val weekend = today.with(TemporalAdjusters.next(DayOfWeek.SATURDAY))
            val nextMon = today.with(TemporalAdjusters.next(DayOfWeek.MONDAY))

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    PresetTile(
                        title = "今天",
                        sub = "${today.monthValue}/${today.dayOfMonth}",
                        icon = Icons.Rounded.Star,
                        iconTint = c.todayGold,
                        selected = selectedDate == today,
                        modifier = Modifier.weight(1f)
                    ) {
                        selectedDate = today; displayedMonth = YearMonth.from(today)
                        if (currentDue == null) { hour = 18; minute = 0 }
                    }
                    PresetTile(
                        title = "明天",
                        sub = "${tomorrow.monthValue}/${tomorrow.dayOfMonth}",
                        icon = Icons.Rounded.WbSunny,
                        iconTint = Color(0xFFEA8C24),
                        selected = selectedDate == tomorrow,
                        modifier = Modifier.weight(1f)
                    ) {
                        selectedDate = tomorrow; displayedMonth = YearMonth.from(tomorrow)
                        if (currentDue == null) { hour = 9; minute = 0 }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    PresetTile(
                        title = "本周末",
                        sub = "${weekend.monthValue}/${weekend.dayOfMonth}",
                        icon = Icons.Rounded.Weekend,
                        iconTint = c.accentBlue,
                        selected = selectedDate == weekend,
                        modifier = Modifier.weight(1f)
                    ) {
                        selectedDate = weekend; displayedMonth = YearMonth.from(weekend)
                        if (currentDue == null) { hour = 10; minute = 0 }
                    }
                    PresetTile(
                        title = "下周一",
                        sub = "${nextMon.monthValue}/${nextMon.dayOfMonth}",
                        icon = Icons.Rounded.CalendarMonth,
                        iconTint = c.upcomingCoral,
                        selected = selectedDate == nextMon,
                        modifier = Modifier.weight(1f)
                    ) {
                        selectedDate = nextMon; displayedMonth = YearMonth.from(nextMon)
                        if (currentDue == null) { hour = 9; minute = 0 }
                    }
                }
            }

            // 2. Clean Monday-first Calendar Grid
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.elevatedSurface)
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        "${displayedMonth.year}年${displayedMonth.monthValue}月",
                        color = c.inkPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(start = 4.dp)
                    )
                    Spacer(Modifier.weight(1f))
                    SmallCircleIconButton(Icons.Rounded.ChevronLeft, "上个月") {
                        displayedMonth = displayedMonth.minusMonths(1)
                    }
                    Text(
                        text = "今天",
                        color = c.accentBlue,
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .clickable {
                                selectedDate = today
                                displayedMonth = YearMonth.from(today)
                            }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                    SmallCircleIconButton(Icons.Rounded.ChevronRight, "下个月") {
                        displayedMonth = displayedMonth.plusMonths(1)
                    }
                }

                Spacer(Modifier.height(2.dp))

                Row(Modifier.fillMaxWidth()) {
                    listOf("一", "二", "三", "四", "五", "六", "日").forEach { wd ->
                        Text(
                            text = wd,
                            modifier = Modifier.weight(1f),
                            textAlign = TextAlign.Center,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            color = c.inkTertiary
                        )
                    }
                }

                val firstDay = displayedMonth.atDay(1)
                val offset = (firstDay.dayOfWeek.value - 1)
                val totalDays = displayedMonth.lengthOfMonth()
                val totalCells = ((offset + totalDays + 6) / 7) * 7

                for (row in 0 until totalCells / 7) {
                    Row(Modifier.fillMaxWidth()) {
                        for (col in 0..6) {
                            val idx = row * 7 + col - offset
                            val cellDate = firstDay.plusDays(idx.toLong())
                            val inMonth = cellDate.month == displayedMonth.month
                            val isSelected = cellDate == selectedDate
                            val isToday = cellDate == today

                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(34.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(30.dp)
                                        .clip(CircleShape)
                                        .background(if (isSelected) c.accentBlue else Color.Transparent)
                                        .border(
                                            width = if (isToday && !isSelected) 1.2.dp else 0.dp,
                                            color = if (isToday && !isSelected) c.accentBlue else Color.Transparent,
                                            shape = CircleShape
                                        )
                                        .clickable {
                                            selectedDate = cellDate
                                            if (!inMonth) displayedMonth = YearMonth.from(cellDate)
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = "${cellDate.dayOfMonth}",
                                        fontSize = 13.sp,
                                        fontWeight = if (isSelected || isToday) FontWeight.SemiBold else FontWeight.Normal,
                                        color = when {
                                            isSelected -> Color.White
                                            inMonth -> c.inkPrimary
                                            else -> c.inkTertiary.copy(alpha = 0.45f)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // 3. Time Picker
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        Icons.Rounded.Schedule,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = c.inkSecondary
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("时间", fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSecondary)
                    Spacer(Modifier.weight(1f))

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(c.subtleFill)
                            .padding(horizontal = 4.dp, vertical = 3.dp)
                    ) {
                        Text(
                            text = "-30m",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = c.inkSecondary,
                            modifier = Modifier
                                .clip(RoundedCornerShape(7.dp))
                                .clickable { adjustMinutes(-30) }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        )
                        Text(
                            text = String.format("%02d:%02d", hour, minute),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = c.inkPrimary,
                            modifier = Modifier.padding(horizontal = 10.dp)
                        )
                        Text(
                            text = "+30m",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = c.inkSecondary,
                            modifier = Modifier
                                .clip(RoundedCornerShape(7.dp))
                                .clickable { adjustMinutes(30) }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        )
                    }
                }

                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(9 to "09:00", 12 to "12:00", 14 to "14:00", 18 to "18:00", 21 to "21:00").forEach { (h, label) ->
                        val active = hour == h && minute == 0
                        SelectablePill(label, active) { hour = h; minute = 0 }
                    }
                }
            }

            ThingsDivider()

            // 4. Repeat Cycle
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Rounded.Repeat,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = c.inkSecondary
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("重复", fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSecondary)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("" to "不重复", "daily" to "每天", "weekly" to "每周", "monthly" to "每月", "yearly" to "每年").forEach { (id, label) ->
                        SelectablePill(label, repeatRule == id) { repeatRule = id }
                    }
                }
            }

            // 5. Primary Action Button
            Button(
                onClick = {
                    onApply(buildIso(), repeatRule.ifEmpty { null })
                    onDismiss()
                },
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = c.accentBlue, contentColor = Color.White),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                Text("完成", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }

            Spacer(Modifier.height(10.dp))
        }
    }
}

@Composable
private fun PresetTile(
    title: String,
    sub: String,
    icon: ImageVector,
    iconTint: Color,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit
) {
    val c = ThingsTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = modifier
            .clip(shape)
            .background(if (selected) c.accentBlueSoft else c.subtleFill)
            .border(
                width = if (selected) 1.2.dp else 0.dp,
                color = if (selected) c.accentBlue.copy(alpha = 0.45f) else Color.Transparent,
                shape = shape
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(16.dp))
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.inkPrimary)
        Spacer(Modifier.weight(1f))
        Text(sub, fontSize = 12.sp, color = c.inkTertiary)
    }
}

@Composable
private fun SelectablePill(label: String, selected: Boolean, onClick: () -> Unit) {
    val c = ThingsTheme.colors
    val shape = RoundedCornerShape(9.dp)
    Box(
        modifier = Modifier
            .clip(shape)
            .background(if (selected) c.accentBlueSoft else c.subtleFill)
            .border(
                width = if (selected) 1.dp else 0.dp,
                color = if (selected) c.accentBlue.copy(alpha = 0.4f) else Color.Transparent,
                shape = shape
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp)
    ) {
        Text(
            text = label,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) c.accentBlue else c.inkPrimary
        )
    }
}

@Composable
private fun SmallCircleIconButton(icon: ImageVector, desc: String, onClick: () -> Unit) {
    val c = ThingsTheme.colors
    Box(
        modifier = Modifier
            .size(30.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = desc, tint = c.inkSecondary, modifier = Modifier.size(18.dp))
    }
}
