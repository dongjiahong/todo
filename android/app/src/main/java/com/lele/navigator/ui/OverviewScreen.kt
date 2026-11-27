package com.lele.navigator.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.lele.navigator.model.TagColors
import com.lele.navigator.notify.ReminderScheduler
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.theme.ThingsTheme

/**
 * Things 3-style Lists Overview Hub.
 */
@Composable
fun OverviewScreen(
    state: NavigatorUiState,
    vm: NavigatorViewModel,
    quickQuery: String,
    onQuickQueryChange: (String) -> Unit,
    onNavigate: (NavRoute) -> Unit,
    onOpenTask: (String) -> Unit,
    onOpenSync: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenTagManager: () -> Unit
) {
    val c = ThingsTheme.colors
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var notifGranted by remember { mutableStateOf(ReminderScheduler.hasNotificationPermission(context)) }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                notifGranted = ReminderScheduler.hasNotificationPermission(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val searchMatches = remember(state.liveTasks, state.liveTags, quickQuery) {
        val q = quickQuery.trim().lowercase()
        if (q.isEmpty()) emptyList()
        else state.liveTasks.filter { t ->
            t.title.lowercase().contains(q) ||
                t.notes.lowercase().contains(q) ||
                t.subtasks.any { it.title.lowercase().contains(q) } ||
                t.tagIds.any { tid -> state.liveTags.firstOrNull { it.id == tid }?.label?.lowercase()?.contains(q) == true }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(c.hubBackground)
            .statusBarsPadding()
    ) {
        // Quick Find Bar (Things 3 style)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (c.isDark) c.cardSurface else Color(0xFFE7E9EE))
                    .padding(horizontal = 12.dp, vertical = 10.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.Search,
                    contentDescription = null,
                    tint = c.inkTertiary,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                BasicTextField(
                    value = quickQuery,
                    onValueChange = onQuickQueryChange,
                    singleLine = true,
                    textStyle = TextStyle(color = c.inkPrimary, fontSize = 15.sp),
                    cursorBrush = SolidColor(c.accentBlue),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        if (quickQuery.isEmpty()) {
                            Text("快速查找标题、备注、子任务或标签", color = c.inkTertiary, fontSize = 15.sp)
                        }
                        inner()
                    }
                )
                if (quickQuery.isNotEmpty()) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "清除",
                        tint = c.inkTertiary,
                        modifier = Modifier
                            .size(18.dp)
                            .clickable { onQuickQueryChange("") }
                    )
                }
            }
        }

        if (quickQuery.isNotBlank()) {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)
            ) {
                if (searchMatches.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 48.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("没有匹配的任务", color = c.inkTertiary, fontSize = 14.sp)
                        }
                    }
                } else {
                    item {
                        Surface(
                            shape = RoundedCornerShape(15.dp),
                            color = c.cardSurface,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column {
                                searchMatches.forEachIndexed { idx, task ->
                                    ThingsTaskRowContent(
                                        task = task,
                                        tags = state.liveTags,
                                        showDoingBadge = true,
                                        onToggleComplete = { vm.toggleComplete(task.id) },
                                        onOpen = { onOpenTask(task.id) }
                                    )
                                    if (idx < searchMatches.lastIndex) {
                                        ThingsDivider(insetStart = 54.dp)
                                    }
                                }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(96.dp)) }
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                item {
                    val todayCount = state.todayActiveTasks.size + state.overdueTasks.size
                    val overdueCount = state.overdueTasks.size
                    OverviewCard {
                        OverviewRow(
                            title = "今天",
                            icon = Icons.Rounded.Star,
                            iconTint = c.todayGold,
                            count = todayCount,
                            alertCount = overdueCount,
                            onClick = { onNavigate(NavRoute.Today) }
                        )
                        ThingsDivider(insetStart = 50.dp)
                        OverviewRow(
                            title = "进行中",
                            icon = Icons.Rounded.Whatshot,
                            iconTint = c.doingBlue,
                            count = state.doingTasks.size,
                            onClick = { onNavigate(NavRoute.Doing) }
                        )
                        ThingsDivider(insetStart = 50.dp)
                        OverviewRow(
                            title = "待办",
                            icon = Icons.Rounded.Inbox,
                            iconTint = c.inboxBlue,
                            count = state.todoTasks.size,
                            onClick = { onNavigate(NavRoute.Todo) }
                        )
                        ThingsDivider(insetStart = 50.dp)
                        OverviewRow(
                            title = "计划",
                            icon = Icons.Rounded.CalendarMonth,
                            iconTint = c.upcomingCoral,
                            count = state.upcomingTasks.size,
                            onClick = { onNavigate(NavRoute.Upcoming) }
                        )
                    }
                }

                item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 6.dp)
                        ) {
                            Text(
                                text = "标签",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = c.inkSecondary
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                text = "管理",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = c.accentBlue,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .clickable(onClick = onOpenTagManager)
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }

                        OverviewCard {
                            if (state.liveTags.isEmpty()) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable(onClick = onOpenTagManager)
                                        .padding(horizontal = 16.dp, vertical = 14.dp)
                                ) {
                                    Icon(
                                        Icons.Rounded.Add,
                                        contentDescription = null,
                                        tint = c.accentBlue,
                                        modifier = Modifier.size(18.dp)
                                    )
                                    Text("新建标签整理任务", fontSize = 15.sp, color = c.inkSecondary)
                                }
                            } else {
                                state.liveTags.forEachIndexed { idx, tag ->
                                    val count = state.liveTasks.count { !it.isDone && it.tagIds.contains(tag.id) }
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { onNavigate(NavRoute.Tag(tag.id)) }
                                            .padding(horizontal = 16.dp, vertical = 13.dp)
                                    ) {
                                        Box(
                                            modifier = Modifier.size(22.dp),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Box(
                                                modifier = Modifier
                                                    .size(9.dp)
                                                    .clip(CircleShape)
                                                    .background(TagColors.colorFor(tag.hue))
                                            )
                                        }
                                        Spacer(Modifier.width(12.dp))
                                        Text(
                                            text = tag.label,
                                            fontSize = 15.5.sp,
                                            fontWeight = FontWeight.Medium,
                                            color = c.inkPrimary,
                                            modifier = Modifier.weight(1f)
                                        )
                                        if (count > 0) {
                                            Text(
                                                text = "$count",
                                                fontSize = 14.sp,
                                                fontWeight = FontWeight.Medium,
                                                color = c.inkTertiary
                                            )
                                        }
                                    }
                                    if (idx < state.liveTags.lastIndex) {
                                        ThingsDivider(insetStart = 50.dp)
                                    }
                                }
                            }
                        }
                    }
                }

                item {
                    OverviewCard {
                        OverviewRow(
                            title = "日志簿",
                            icon = Icons.Rounded.AutoStories,
                            iconTint = c.logbookGreen,
                            count = state.logbookTasks.size,
                            onClick = { onNavigate(NavRoute.Logbook) }
                        )
                    }
                }

                item { Spacer(Modifier.height(84.dp)) }
            }
        }

        // Minimal Bottom Bar (Sync + Settings)
        ThingsDivider()
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .background(c.hubBackground)
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 10.dp)
        ) {
            val synced = state.syncStatus.syncedAt > 0
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(onClick = onOpenSync)
                    .padding(horizontal = 8.dp, vertical = 6.dp)
            ) {
                Box(
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (synced) c.logbookGreen else c.inkTertiary)
                )
                Text(
                    text = if (synced) "已与 Mac 同步" else "配对 Mac 同步",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = c.inkSecondary
                )
            }

            Spacer(Modifier.weight(1f))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(onClick = onOpenSettings)
                    .padding(horizontal = 8.dp, vertical = 6.dp)
            ) {
                if (!notifGranted) {
                    Box(
                        Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(c.todayGold)
                    )
                }
                Icon(
                    imageVector = Icons.Rounded.Tune,
                    contentDescription = "设置",
                    tint = c.inkSecondary,
                    modifier = Modifier.size(19.dp)
                )
                Text(
                    text = "设置",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = c.inkSecondary
                )
            }
        }
    }
}

@Composable
private fun OverviewCard(content: @Composable ColumnScope.() -> Unit) {
    val c = ThingsTheme.colors
    Surface(
        shape = RoundedCornerShape(15.dp),
        color = c.cardSurface,
        shadowElevation = if (c.isDark) 0.dp else 0.5.dp,
        modifier = Modifier
            .fillMaxWidth()
            .border(
                width = 0.5.dp,
                color = c.divider.copy(alpha = 0.7f),
                shape = RoundedCornerShape(15.dp)
            )
    ) {
        Column(content = content)
    }
}

@Composable
private fun OverviewRow(
    title: String,
    icon: ImageVector,
    iconTint: Color,
    count: Int,
    alertCount: Int = 0,
    onClick: () -> Unit
) {
    val c = ThingsTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.5.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = iconTint,
            modifier = Modifier.size(22.dp)
        )
        Spacer(Modifier.width(12.dp))
        Text(
            text = title,
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
            color = c.inkPrimary,
            modifier = Modifier.weight(1f)
        )
        if (alertCount > 0) {
            Box(
                modifier = Modifier
                    .padding(end = 8.dp)
                    .clip(CircleShape)
                    .background(c.danger)
                    .padding(horizontal = 7.dp, vertical = 2.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "$alertCount",
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }
        }
        if (count > 0) {
            Text(
                text = "$count",
                fontSize = 14.5.sp,
                fontWeight = FontWeight.Medium,
                color = c.inkTertiary
            )
        }
    }
}
