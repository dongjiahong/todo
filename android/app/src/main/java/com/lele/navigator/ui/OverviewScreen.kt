package com.lele.navigator.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.ListStyle
import com.lele.navigator.model.TaskListItem
import com.lele.navigator.ui.components.ThingsCheckbox
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.theme.ThingsTheme

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun OverviewScreen(
    state: NavigatorUiState,
    vm: NavigatorViewModel,
    quickQuery: String,
    onQuickQueryChange: (String) -> Unit,
    onNavigate: (NavRoute) -> Unit,
    onOpenInspector: (String) -> Unit,
    onNewReminder: () -> Unit,
    onAddList: () -> Unit,
    onEditList: (TaskListItem) -> Unit,
    onOpenSync: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenTagManager: () -> Unit
) {
    val c = ThingsTheme.colors
    val searching = quickQuery.isNotBlank()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(c.hubBackground)
            .statusBarsPadding()
    ) {
        // Compact Top Utility Bar with Live Sync Status Pill
        val sync = state.syncStatus
        val onlinePaired = sync.pairedPeers.count { it.online }
        val (dotColor, syncText) = when {
            state.isSyncing -> c.accentBlue to "同步中…"
            !sync.lastError.isNullOrBlank() -> c.danger to "同步异常"
            sync.pairedPeers.isNotEmpty() && sync.syncedAt > 0L -> {
                val timeStr = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
                    .format(java.util.Date(sync.syncedAt))
                (if (onlinePaired > 0) c.logbookGreen else c.logbookGreen.copy(alpha = 0.7f)) to "已同步 · $timeStr"
            }
            onlinePaired > 0 -> c.logbookGreen to "$onlinePaired 台在线"
            sync.pairedPeers.isNotEmpty() -> c.inkTertiary to "已配对 · 离线"
            sync.discoveredPeers.isNotEmpty() -> c.todayGold to "发现 ${sync.discoveredPeers.size} 台设备"
            else -> (if (sync.running) c.accentBlue else c.inkTertiary) to "未配对"
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.cardSurface)
                    .clickable(onClick = onOpenSync)
                    .padding(horizontal = 9.dp, vertical = 4.dp)
            ) {
                if (state.isSyncing) {
                    CircularProgressIndicator(
                        strokeWidth = 1.6.dp,
                        color = c.accentBlue,
                        modifier = Modifier.size(11.dp)
                    )
                } else {
                    Box(
                        Modifier
                            .size(6.5.dp)
                            .clip(CircleShape)
                            .background(dotColor)
                    )
                }
                Text(
                    text = syncText,
                    fontSize = 11.5.sp,
                    color = c.inkPrimary,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(Modifier.weight(1f))

            IconButton(
                onClick = onOpenSettings,
                modifier = Modifier.size(30.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.MoreHoriz,
                    contentDescription = "设置",
                    tint = c.accentBlue,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        // Compact Search Bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 3.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(if (c.isDark) c.cardSurface else Color(0xFFE3E3E8))
                .padding(horizontal = 10.dp, vertical = 7.dp)
        ) {
            Icon(
                imageVector = Icons.Rounded.Search,
                contentDescription = null,
                tint = c.inkSecondary,
                modifier = Modifier.size(16.dp)
            )
            BasicTextField(
                value = quickQuery,
                onValueChange = onQuickQueryChange,
                singleLine = true,
                textStyle = TextStyle(color = c.inkPrimary, fontSize = 14.sp),
                cursorBrush = SolidColor(c.accentBlue),
                modifier = Modifier.weight(1f),
                decorationBox = { inner ->
                    if (quickQuery.isEmpty()) {
                        Text("搜索", color = c.inkSecondary, fontSize = 14.sp)
                    }
                    inner()
                }
            )
            if (searching) {
                Icon(
                    imageVector = Icons.Rounded.Cancel,
                    contentDescription = "清空",
                    tint = c.inkTertiary,
                    modifier = Modifier
                        .size(16.dp)
                        .clickable { onQuickQueryChange("") }
                )
            }
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (searching) {
                val results = state.liveTasks.filter { state.matchesSearch(it, quickQuery) }
                item {
                    if (results.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 40.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("没有找到匹配「$quickQuery」的提醒事项", color = c.inkTertiary, fontSize = 13.sp)
                        }
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(c.cardSurface)
                        ) {
                            results.forEachIndexed { idx, task ->
                                val list = state.listFor(task.effectiveListId)
                                val tint = ListStyle.colorFor(list.color)
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { onOpenInspector(task.id) }
                                        .padding(horizontal = 6.dp, vertical = 6.dp)
                                ) {
                                    ThingsCheckbox(
                                        checked = task.isDone,
                                        tint = tint,
                                        onCheckedChange = { vm.toggleComplete(task.id) }
                                    )
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            text = task.title.ifBlank { "未命名提醒" },
                                            fontSize = 14.sp,
                                            color = if (task.isDone) c.inkSecondary else c.inkPrimary,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                        Text(text = list.name, fontSize = 11.5.sp, color = tint)
                                    }
                                    Icon(
                                        imageVector = Icons.Rounded.Info,
                                        contentDescription = "详情",
                                        tint = c.todayGold,
                                        modifier = Modifier
                                            .padding(end = 6.dp)
                                            .size(18.dp)
                                    )
                                }
                                if (idx < results.lastIndex) {
                                    ThingsDivider(insetStart = 38.dp)
                                }
                            }
                        }
                    }
                }
            } else {
                // Compact 2-Column Smart List Grid
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            SmartGridCard(
                                title = "今天",
                                count = state.todayTasks.size,
                                tint = c.accentBlue,
                                badgeText = "${DateUtils.todayDayNumber()}",
                                icon = Icons.Rounded.CalendarToday,
                                modifier = Modifier.weight(1f),
                                onClick = { onNavigate(NavRoute.Today) }
                            )
                            SmartGridCard(
                                title = "计划",
                                count = state.scheduledTasks.size,
                                tint = c.upcomingCoral,
                                icon = Icons.Rounded.DateRange,
                                modifier = Modifier.weight(1f),
                                onClick = { onNavigate(NavRoute.Scheduled) }
                            )
                        }

                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            SmartGridCard(
                                title = "全部",
                                count = state.allActiveTasks.size,
                                tint = c.allDark,
                                icon = Icons.Rounded.Inbox,
                                modifier = Modifier.weight(1f),
                                onClick = { onNavigate(NavRoute.All) }
                            )
                            SmartGridCard(
                                title = "旗标",
                                count = state.flaggedTasks.size,
                                tint = c.todayGold,
                                icon = Icons.Rounded.Flag,
                                modifier = Modifier.weight(1f),
                                onClick = { onNavigate(NavRoute.Flagged) }
                            )
                        }

                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            SmartGridCard(
                                title = "完成",
                                count = null,
                                tint = c.completedGray,
                                icon = Icons.Rounded.Check,
                                modifier = Modifier.weight(1f),
                                onClick = { onNavigate(NavRoute.Completed) }
                            )
                            Spacer(Modifier.weight(1f))
                        }
                    }
                }

                // Compact 我的列表
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = "我的列表",
                            fontSize = 15.5.sp,
                            fontWeight = FontWeight.Bold,
                            color = c.inkPrimary,
                            modifier = Modifier.padding(horizontal = 4.dp)
                        )

                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(c.cardSurface)
                        ) {
                            state.liveLists.forEachIndexed { idx, list ->
                                val listColor = ListStyle.colorFor(list.color)
                                val count = state.activeTasksInList(list.id).size
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .combinedClickable(
                                            onClick = { onNavigate(NavRoute.CustomList(list.id)) },
                                            onLongClick = { onEditList(list) }
                                        )
                                        .padding(horizontal = 12.dp, vertical = 8.5.dp)
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(25.dp)
                                            .clip(CircleShape)
                                            .background(listColor),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Icon(
                                            imageVector = ListStyle.iconFor(list.icon),
                                            contentDescription = null,
                                            tint = Color.White,
                                            modifier = Modifier.size(14.dp)
                                        )
                                    }

                                    Spacer(Modifier.width(10.dp))

                                    Text(
                                        text = list.name,
                                        fontSize = 14.5.sp,
                                        color = c.inkPrimary,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f)
                                    )

                                    Text(
                                        text = "$count",
                                        fontSize = 13.5.sp,
                                        color = c.inkSecondary
                                    )
                                    Spacer(Modifier.width(3.dp))
                                    Icon(
                                        imageVector = Icons.Rounded.ChevronRight,
                                        contentDescription = null,
                                        tint = c.inkTertiary,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                                if (idx < state.liveLists.lastIndex) {
                                    ThingsDivider(insetStart = 47.dp)
                                }
                            }
                        }
                    }
                }

                // Compact 标签
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 4.dp)
                        ) {
                            Text(
                                text = "标签",
                                fontSize = 15.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = c.inkPrimary,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                text = "管理",
                                fontSize = 13.sp,
                                color = c.accentBlue,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .clickable(onClick = onOpenTagManager)
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }

                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            HubTagChip(
                                title = "所有标签",
                                onClick = { onNavigate(NavRoute.AllTags) }
                            )
                            state.liveTags.forEach { tag ->
                                HubTagChip(
                                    title = "#${tag.label}",
                                    onClick = { onNavigate(NavRoute.Tag(tag.id)) }
                                )
                            }
                        }
                    }
                }
            }
        }

        // Compact Bottom Bar
        ThingsDivider()
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .background(c.hubBackground)
                .navigationBarsPadding()
                .padding(horizontal = 14.dp, vertical = 7.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClick = onNewReminder)
                    .padding(horizontal = 4.dp, vertical = 3.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.AddCircle,
                    contentDescription = null,
                    tint = c.accentBlue,
                    modifier = Modifier.size(19.dp)
                )
                Text(
                    text = "新提醒事项",
                    fontSize = 14.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = c.accentBlue
                )
            }

            Spacer(Modifier.weight(1f))

            Text(
                text = "添加列表",
                fontSize = 14.5.sp,
                color = c.accentBlue,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClick = onAddList)
                    .padding(horizontal = 6.dp, vertical = 3.dp)
            )
        }
    }
}

@Composable
private fun SmartGridCard(
    title: String,
    count: Int?,
    tint: Color,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    badgeText: String? = null,
    onClick: () -> Unit
) {
    val c = ThingsTheme.colors
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(c.cardSurface)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            Box(
                modifier = Modifier
                    .size(25.dp)
                    .clip(CircleShape)
                    .background(tint),
                contentAlignment = Alignment.Center
            ) {
                if (badgeText != null) {
                    Text(
                        text = badgeText,
                        color = Color.White,
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold
                    )
                } else {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            if (count != null) {
                Text(
                    text = "$count",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = c.inkPrimary
                )
            }
        }
        Text(
            text = title,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.SemiBold,
            color = c.inkSecondary
        )
    }
}

@Composable
private fun HubTagChip(
    title: String,
    onClick: () -> Unit
) {
    val c = ThingsTheme.colors
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(c.cardSurface)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 5.dp)
    ) {
        Text(
            text = title,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.Medium,
            color = c.inkPrimary
        )
    }
}
