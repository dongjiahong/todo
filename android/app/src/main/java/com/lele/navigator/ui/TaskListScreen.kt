package com.lele.navigator.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.TagColors
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
import com.lele.navigator.ui.components.*
import com.lele.navigator.ui.theme.ThingsTheme

/**
 * Airy Things 3 Task List View (Today / Doing / Todo / Upcoming / Tag / Logbook).
 */
@Composable
fun TaskListScreen(
    route: NavRoute,
    state: NavigatorUiState,
    vm: NavigatorViewModel,
    showSearch: Boolean,
    onToggleSearch: () -> Unit,
    onBackToLists: () -> Unit,
    onOpenTask: (String) -> Unit,
    onOpenSync: () -> Unit
) {
    val c = ThingsTheme.colors
    var showDoneToday by remember { mutableStateOf(false) }

    val activeTag = remember(route, state.liveTags) {
        if (route is NavRoute.Tag) state.liveTags.firstOrNull { it.id == route.tagId } else null
    }

    val headerTitle = when (route) {
        NavRoute.Today -> "今天"
        NavRoute.Doing -> "进行中"
        NavRoute.Todo -> "待办"
        NavRoute.Upcoming -> "计划"
        NavRoute.Logbook -> "日志簿"
        is NavRoute.Tag -> activeTag?.label ?: "标签"
        NavRoute.Overview -> ""
    }

    val headerSubtitle = if (route == NavRoute.Today) DateUtils.todaySubtitle() else null

    val headerIcon: ImageVector? = when (route) {
        NavRoute.Today -> Icons.Rounded.Star
        NavRoute.Doing -> Icons.Rounded.Whatshot
        NavRoute.Todo -> Icons.Rounded.Inbox
        NavRoute.Upcoming -> Icons.Rounded.CalendarMonth
        NavRoute.Logbook -> Icons.Rounded.AutoStories
        is NavRoute.Tag -> null
        NavRoute.Overview -> null
    }

    val headerTint: Color = when (route) {
        NavRoute.Today -> c.todayGold
        NavRoute.Doing -> c.doingBlue
        NavRoute.Todo -> c.inboxBlue
        NavRoute.Upcoming -> c.upcomingCoral
        NavRoute.Logbook -> c.logbookGreen
        is NavRoute.Tag -> TagColors.colorFor(activeTag?.hue ?: "blue")
        NavRoute.Overview -> c.accentBlue
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(c.listBackground)
            .statusBarsPadding()
    ) {
        // Minimal borderless top navigation bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(onClick = onBackToLists)
                    .padding(horizontal = 6.dp, vertical = 6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.ChevronLeft,
                    contentDescription = "列表",
                    tint = c.accentBlue,
                    modifier = Modifier.size(24.dp)
                )
                Text(
                    text = "列表",
                    color = c.accentBlue,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(Modifier.weight(1f))

            val synced = state.syncStatus.syncedAt > 0
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier
                    .clip(CircleShape)
                    .clickable(onClick = onOpenSync)
                    .padding(horizontal = 10.dp, vertical = 6.dp)
            ) {
                Box(
                    Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(if (synced) c.logbookGreen else c.inkTertiary)
                )
                Text(
                    text = if (synced) "已同步" else "未同步",
                    fontSize = 12.sp,
                    color = c.inkTertiary
                )
            }

            IconButton(onClick = onToggleSearch) {
                Icon(
                    imageVector = if (showSearch) Icons.Rounded.Close else Icons.Rounded.Search,
                    contentDescription = "搜索",
                    tint = c.inkSecondary,
                    modifier = Modifier.size(21.dp)
                )
            }
        }

        // Collapsible sleek search bar
        AnimatedVisibility(visible = showSearch) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 4.dp)
                    .clip(RoundedCornerShape(11.dp))
                    .background(c.subtleFill)
                    .padding(horizontal = 12.dp, vertical = 9.dp)
            ) {
                Icon(
                    Icons.Rounded.Search,
                    contentDescription = null,
                    tint = c.inkTertiary,
                    modifier = Modifier.size(17.dp)
                )
                Spacer(Modifier.width(8.dp))
                BasicTextField(
                    value = state.searchQuery,
                    onValueChange = { vm.setSearch(it) },
                    singleLine = true,
                    textStyle = TextStyle(color = c.inkPrimary, fontSize = 14.5.sp),
                    cursorBrush = SolidColor(c.accentBlue),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        if (state.searchQuery.isEmpty()) {
                            Text("筛选标题、备注、子任务或标签", color = c.inkTertiary, fontSize = 14.5.sp)
                        }
                        inner()
                    }
                )
            }
        }

        // Main Scrollable Task List with Things 3 Big Header
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 110.dp)
        ) {
            item(key = "header") {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        if (headerIcon != null) {
                            Icon(
                                imageVector = headerIcon,
                                contentDescription = null,
                                tint = headerTint,
                                modifier = Modifier.size(28.dp)
                            )
                        } else {
                            Box(
                                Modifier
                                    .size(14.dp)
                                    .clip(CircleShape)
                                    .background(headerTint)
                            )
                        }
                        Text(
                            text = headerTitle,
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = (-0.4).sp,
                            color = c.inkPrimary
                        )
                    }
                    if (headerSubtitle != null) {
                        Text(
                            text = headerSubtitle,
                            fontSize = 13.5.sp,
                            color = c.inkTertiary,
                            modifier = Modifier.padding(start = 38.dp)
                        )
                    }
                }
            }

            when (route) {
                NavRoute.Today -> {
                    if (state.overdueTasks.isNotEmpty()) {
                        item(key = "overdue_hdr") {
                            ThingsSectionHeader(
                                title = "已逾期",
                                count = state.overdueTasks.size,
                                accentColor = c.danger
                            )
                        }
                        itemsIndexed(state.overdueTasks, key = { _, it -> "ov_${it.id}" }) { idx, task ->
                            ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = true, vm, onOpenTask)
                            if (idx < state.overdueTasks.lastIndex) ThingsDivider(insetStart = 54.dp)
                        }
                        item(key = "overdue_gap") { Spacer(Modifier.height(14.dp)) }
                    }

                    if (state.todayActiveTasks.isEmpty() && state.overdueTasks.isEmpty()) {
                        item(key = "today_empty") {
                            EmptyStateBlock(Icons.Rounded.StarOutline, "今天很清静，没有待处理事项")
                        }
                    } else {
                        if (state.overdueTasks.isNotEmpty() && state.todayActiveTasks.isNotEmpty()) {
                            item(key = "today_hdr") {
                                ThingsSectionHeader(title = "今日聚焦", count = state.todayActiveTasks.size)
                            }
                        }
                        itemsIndexed(state.todayActiveTasks, key = { _, it -> it.id }) { idx, task ->
                            ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = true, vm, onOpenTask)
                            if (idx < state.todayActiveTasks.lastIndex) ThingsDivider(insetStart = 54.dp)
                        }
                    }

                    if (state.todayCompletedTasks.isNotEmpty()) {
                        item(key = "done_today_toggle") {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .padding(horizontal = 20.dp, vertical = 14.dp)
                                    .clip(RoundedCornerShape(8.dp))
                                    .clickable { showDoneToday = !showDoneToday }
                                    .padding(horizontal = 4.dp, vertical = 4.dp)
                            ) {
                                Icon(
                                    imageVector = if (showDoneToday) Icons.Rounded.ExpandMore else Icons.Rounded.ChevronRight,
                                    contentDescription = null,
                                    tint = c.inkTertiary,
                                    modifier = Modifier.size(18.dp)
                                )
                                Text(
                                    text = "今日已完成 (${state.todayCompletedTasks.size})",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = c.inkTertiary
                                )
                            }
                        }
                        if (showDoneToday) {
                            itemsIndexed(state.todayCompletedTasks, key = { _, it -> "dt_${it.id}" }) { idx, task ->
                                ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = false, vm, onOpenTask)
                                if (idx < state.todayCompletedTasks.lastIndex) ThingsDivider(insetStart = 54.dp)
                            }
                        }
                    }
                }

                NavRoute.Doing -> {
                    if (state.doingTasks.isEmpty()) {
                        item(key = "doing_empty") {
                            EmptyStateBlock(Icons.Rounded.Whatshot, "当前没有进行中的任务")
                        }
                    } else {
                        itemsIndexed(state.doingTasks, key = { _, it -> it.id }) { idx, task ->
                            ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = false, vm, onOpenTask)
                            if (idx < state.doingTasks.lastIndex) ThingsDivider(insetStart = 54.dp)
                        }
                    }
                }

                NavRoute.Todo -> {
                    if (state.todoTasks.isEmpty()) {
                        item(key = "todo_empty") {
                            EmptyStateBlock(Icons.Rounded.Inbox, "待办已清空，点右下角 ＋ 记一笔")
                        }
                    } else {
                        itemsIndexed(state.todoTasks, key = { _, it -> it.id }) { idx, task ->
                            ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = false, vm, onOpenTask)
                            if (idx < state.todoTasks.lastIndex) ThingsDivider(insetStart = 54.dp)
                        }
                    }
                }

                NavRoute.Upcoming -> {
                    val grouped = state.upcomingTasks.groupBy { DateUtils.upcomingGroupLabel(it.dueAt) }
                    if (grouped.isEmpty()) {
                        item(key = "up_empty") {
                            EmptyStateBlock(Icons.Rounded.CalendarMonth, "暂无带截止日期的计划事项")
                        }
                    } else {
                        grouped.forEach { (dayLabel, list) ->
                            item(key = "up_hdr_$dayLabel") {
                                ThingsSectionHeader(
                                    title = dayLabel,
                                    count = list.size,
                                    accentColor = if (dayLabel == "已逾期") c.danger else null,
                                    modifier = Modifier.padding(top = 8.dp)
                                )
                            }
                            itemsIndexed(list, key = { _, it -> it.id }) { idx, task ->
                                ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = true, vm, onOpenTask)
                                if (idx < list.lastIndex) ThingsDivider(insetStart = 54.dp)
                            }
                        }
                    }
                }

                is NavRoute.Tag -> {
                    val q = state.searchQuery.trim().lowercase()
                    val tagTasks = state.liveTasks.filter { t ->
                        !t.isDone && t.tagIds.contains(route.tagId) &&
                            (q.isEmpty() || t.title.lowercase().contains(q) || t.notes.lowercase().contains(q) ||
                                t.subtasks.any { it.title.lowercase().contains(q) })
                    }
                    if (tagTasks.isEmpty()) {
                        item(key = "tag_empty") {
                            EmptyStateBlock(Icons.Rounded.Sell, "此标签下暂无未完成任务")
                        }
                    } else {
                        itemsIndexed(tagTasks, key = { _, it -> it.id }) { idx, task ->
                            ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = true, vm, onOpenTask)
                            if (idx < tagTasks.lastIndex) ThingsDivider(insetStart = 54.dp)
                        }
                    }
                }

                NavRoute.Logbook -> {
                    val grouped = state.logbookTasks.groupBy { DateUtils.logbookDay(it.completedAt) }
                    if (grouped.isEmpty()) {
                        item(key = "log_empty") {
                            EmptyStateBlock(Icons.Rounded.AutoStories, "日志簿还是空的")
                        }
                    } else {
                        grouped.forEach { (day, list) ->
                            item(key = "log_hdr_$day") {
                                ThingsSectionHeader(
                                    title = day,
                                    count = list.size,
                                    modifier = Modifier.padding(top = 8.dp)
                                )
                            }
                            itemsIndexed(list, key = { _, it -> it.id }) { idx, task ->
                                ThingsSwipeableTaskRow(task, state.liveTags, showDoingBadge = false, vm, onOpenTask)
                                if (idx < list.lastIndex) ThingsDivider(insetStart = 54.dp)
                            }
                        }
                    }
                }

                NavRoute.Overview -> Unit
            }
        }
    }
}

@Composable
private fun EmptyStateBlock(icon: ImageVector, text: String) {
    val c = ThingsTheme.colors
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 84.dp, bottom = 32.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = c.inkTertiary.copy(alpha = 0.45f),
            modifier = Modifier.size(38.dp)
        )
        Text(
            text = text,
            fontSize = 14.5.sp,
            color = c.inkTertiary
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThingsSwipeableTaskRow(
    task: TaskItem,
    tags: List<TagItem>,
    showDoingBadge: Boolean,
    vm: NavigatorViewModel,
    onOpen: (String) -> Unit
) {
    val c = ThingsTheme.colors
    val haptic = LocalHapticFeedback.current
    val dismissState = rememberSwipeToDismissBoxState(
        positionalThreshold = { totalDistance -> totalDistance * 0.42f },
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    vm.toggleComplete(task.id)
                    false
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    if (task.isDone) vm.deleteTask(task.id) else vm.toggleDoing(task.id)
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val dir = dismissState.dismissDirection
            val bg = when (dir) {
                SwipeToDismissBoxValue.StartToEnd -> c.logbookGreen
                SwipeToDismissBoxValue.EndToStart -> if (task.isDone) c.danger else c.doingBlue
                else -> Color.Transparent
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(bg)
                    .padding(horizontal = 24.dp),
                contentAlignment = if (dir == SwipeToDismissBoxValue.StartToEnd) Alignment.CenterStart else Alignment.CenterEnd
            ) {
                if (dir == SwipeToDismissBoxValue.StartToEnd) {
                    Icon(Icons.Rounded.Check, contentDescription = "完成", tint = Color.White)
                } else if (dir == SwipeToDismissBoxValue.EndToStart) {
                    Icon(
                        if (task.isDone) Icons.Rounded.DeleteOutline else Icons.Rounded.Whatshot,
                        contentDescription = null,
                        tint = Color.White
                    )
                }
            }
        }
    ) {
        Box(modifier = Modifier.background(c.listBackground)) {
            ThingsTaskRowContent(
                task = task,
                tags = tags,
                showDoingBadge = showDoingBadge,
                onToggleComplete = { vm.toggleComplete(task.id) },
                onOpen = { onOpen(task.id) }
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ThingsTaskRowContent(
    task: TaskItem,
    tags: List<TagItem>,
    showDoingBadge: Boolean,
    onToggleComplete: () -> Unit,
    onOpen: () -> Unit
) {
    val c = ThingsTheme.colors
    val resolvedTags = remember(task.tagIds, tags) {
        task.tagIds.mapNotNull { id -> tags.firstOrNull { it.id == id } }
    }
    val dueInfo = DateUtils.dueLabel(task.dueAt, task.isDone)
    val hasMeta = (showDoingBadge && task.isDoing && !task.isDone) ||
        dueInfo != null ||
        task.checklistTotal > 0 ||
        task.attachments.isNotEmpty() ||
        resolvedTags.isNotEmpty()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(start = 10.dp, end = 20.dp, top = 11.dp, bottom = 11.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        ThingsCheckbox(
            checked = task.isDone,
            isDoing = task.isDoing,
            onCheckedChange = onToggleComplete,
            modifier = Modifier.offset(y = (-8).dp)
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = task.title.ifBlank { "未命名任务" },
                fontSize = 15.5.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.Normal,
                textDecoration = if (task.isDone) TextDecoration.LineThrough else TextDecoration.None,
                color = if (task.isDone) c.inkTertiary else c.inkPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )

            if (task.notes.isNotBlank()) {
                Text(
                    text = task.notes.trim().replace("\n", " "),
                    fontSize = 12.5.sp,
                    lineHeight = 17.sp,
                    color = c.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            if (hasMeta) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier.padding(top = 2.dp)
                ) {
                    if (showDoingBadge && task.isDoing && !task.isDone) {
                        ThingsPill(
                            text = "进行中",
                            textColor = c.doingBlue,
                            backgroundColor = c.doingBlueSoft,
                            icon = Icons.Rounded.Whatshot
                        )
                    }

                    if (dueInfo != null) {
                        val (label, tone) = dueInfo
                        val fg = when (tone) {
                            2 -> c.danger
                            1 -> c.todayGold
                            else -> c.inkSecondary
                        }
                        val bg = when (tone) {
                            2 -> c.dangerSoft
                            1 -> c.todayGoldSoft
                            else -> Color.Transparent
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(bg)
                                .padding(
                                    horizontal = if (tone == 0) 0.dp else 6.dp,
                                    vertical = if (tone == 0) 2.dp else 2.5.dp
                                )
                        ) {
                            Icon(
                                Icons.Rounded.CalendarToday,
                                contentDescription = null,
                                tint = fg,
                                modifier = Modifier.size(11.dp)
                            )
                            Text(
                                text = label,
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.Medium,
                                color = fg
                            )
                            if (!task.repeatRule.isNullOrBlank()) {
                                Icon(
                                    Icons.Rounded.Repeat,
                                    contentDescription = null,
                                    tint = fg.copy(alpha = 0.85f),
                                    modifier = Modifier.size(11.dp)
                                )
                            }
                        }
                    }

                    if (task.checklistTotal > 0) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier.padding(vertical = 2.dp)
                        ) {
                            MiniProgressRing(done = task.checklistDone, total = task.checklistTotal)
                            Text(
                                text = "${task.checklistDone}/${task.checklistTotal}",
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.Medium,
                                color = c.inkSecondary
                            )
                        }
                    }

                    if (task.attachments.isNotEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(2.dp),
                            modifier = Modifier.padding(vertical = 2.dp)
                        ) {
                            Icon(
                                Icons.Rounded.Image,
                                contentDescription = null,
                                tint = c.inkTertiary,
                                modifier = Modifier.size(12.dp)
                            )
                            if (task.attachments.size > 1) {
                                Text(
                                    text = "${task.attachments.size}",
                                    fontSize = 11.5.sp,
                                    color = c.inkTertiary
                                )
                            }
                        }
                    }

                    resolvedTags.forEach { tag ->
                        val color = TagColors.colorFor(tag.hue)
                        ThingsPill(
                            text = tag.label,
                            textColor = color,
                            backgroundColor = color.copy(alpha = if (c.isDark) 0.18f else 0.10f),
                            dotColor = color
                        )
                    }
                }
            }
        }
    }
}
