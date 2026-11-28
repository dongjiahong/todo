package com.lele.navigator.ui

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.ListStyle
import com.lele.navigator.model.TagColors
import com.lele.navigator.model.TaskItem
import com.lele.navigator.ui.components.MiniProgressRing
import com.lele.navigator.ui.components.ThingsCheckbox
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.components.ThingsPill
import com.lele.navigator.ui.theme.ThingsTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TaskListScreen(
    route: NavRoute,
    state: NavigatorUiState,
    vm: NavigatorViewModel,
    onBackToLists: () -> Unit,
    onOpenInspector: (String) -> Unit
) {
    val c = ThingsTheme.colors
    val context = LocalContext.current
    var showCompleted by remember(route) { mutableStateOf(false) }
    var dueSheetTaskId by remember { mutableStateOf<String?>(null) }
    var tagSheetTaskId by remember { mutableStateOf<String?>(null) }
    var photoTargetTaskId by remember { mutableStateOf<String?>(null) }
    var previewImagePath by remember { mutableStateOf<String?>(null) }

    val inlinePhotoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        val tid = photoTargetTaskId
        photoTargetTaskId = null
        if (uri != null && tid != null) {
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }.getOrNull()?.let { bytes ->
                vm.attachImage(tid, bytes, "jpg")
            }
        }
    }

    val (pageTitle, titleColor) = when (route) {
        NavRoute.Today -> "今天" to c.accentBlue
        NavRoute.Scheduled -> "计划" to c.upcomingCoral
        NavRoute.All -> "全部" to c.inkPrimary
        NavRoute.Flagged -> "旗标" to c.todayGold
        NavRoute.Completed -> "完成" to c.completedGray
        is NavRoute.CustomList -> {
            val l = state.listFor(route.listId)
            l.name to ListStyle.colorFor(l.color)
        }
        NavRoute.AllTags -> "所有标签" to c.inkPrimary
        is NavRoute.Tag -> {
            val t = state.liveTags.firstOrNull { it.id == route.tagId }
            "#${t?.label ?: "标签"}" to (t?.let { TagColors.colorFor(it.hue) } ?: c.accentBlue)
        }
        NavRoute.Overview -> "" to c.inkPrimary
    }

    val completedForSection = remember(route, state.tasks) {
        when (route) {
            NavRoute.All, NavRoute.Completed -> state.completedTasks
            NavRoute.Today -> state.liveTasks.filter { it.isDone && DateUtils.isCompletedToday(it.completedAt) }
            NavRoute.Scheduled -> state.liveTasks.filter { it.isDone && !it.dueAt.isNullOrBlank() }
            NavRoute.Flagged -> state.liveTasks.filter { it.isDone && it.flagged }
            is NavRoute.CustomList -> state.completedTasksInList(route.listId)
            NavRoute.AllTags -> state.liveTasks.filter { it.isDone && it.tagIds.isNotEmpty() }
            is NavRoute.Tag -> state.liveTasks.filter { it.isDone && it.tagIds.contains(route.tagId) }
            NavRoute.Overview -> emptyList()
        }
    }

    fun spawnInlineForRoute(listIdOverride: String? = null) {
        val targetList = listIdOverride ?: when (route) {
            is NavRoute.CustomList -> route.listId
            else -> state.liveLists.first().id
        }
        val defaultDue = if (route == NavRoute.Today || route == NavRoute.Scheduled) DateUtils.presetDue(0, 18) else null
        val defaultFlag = route == NavRoute.Flagged
        val defaultTags = if (route is NavRoute.Tag) listOf(route.tagId) else emptyList()
        vm.createInlineTask(
            listId = targetList,
            dueAt = defaultDue,
            flagged = defaultFlag,
            tagIds = defaultTags,
            focusInline = true
        )
    }

    fun pickPhotoFor(taskId: String) {
        photoTargetTaskId = taskId
        inlinePhotoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(c.listBackground)
            .statusBarsPadding()
            .imePadding()
    ) {
        // Compact Top Navigation Bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 3.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable {
                        vm.setEditingTask(null)
                        onBackToLists()
                    }
                    .padding(horizontal = 4.dp, vertical = 4.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.ChevronLeft,
                    contentDescription = "返回列表",
                    tint = c.accentBlue,
                    modifier = Modifier.size(22.dp)
                )
                Text(
                    text = "列表",
                    fontSize = 15.sp,
                    color = c.accentBlue,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(Modifier.weight(1f))

            if (state.editingTaskId != null) {
                Text(
                    text = "完成",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = c.accentBlue,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { vm.setEditingTask(null) }
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                )
            } else if (route != NavRoute.Completed) {
                IconButton(
                    onClick = { spawnInlineForRoute() },
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Add,
                        contentDescription = "新建提醒事项",
                        tint = c.accentBlue,
                        modifier = Modifier.size(22.dp)
                    )
                }
            }
        }

        // Compact Colored Title
        Text(
            text = pageTitle,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = titleColor,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp)
        )

        // Completed Counter Bar ("N 项完成 • 清除" | "显示 / 隐藏")
        if (completedForSection.isNotEmpty() || route == NavRoute.Completed) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
            ) {
                Text(
                    text = "${completedForSection.size} 项完成",
                    fontSize = 12.sp,
                    color = c.inkSecondary
                )
                if (completedForSection.isNotEmpty()) {
                    Text(" • ", fontSize = 12.sp, color = c.inkTertiary)
                    Text(
                        text = "清除",
                        fontSize = 12.sp,
                        color = c.accentBlue,
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .clickable {
                                val listFilter = if (route is NavRoute.CustomList) route.listId else null
                                vm.clearCompleted(listFilter)
                            }
                            .padding(horizontal = 2.dp)
                    )
                }
                Spacer(Modifier.weight(1f))
                if (route != NavRoute.Completed && completedForSection.isNotEmpty()) {
                    Text(
                        text = if (showCompleted) "隐藏" else "显示",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = c.accentBlue,
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .clickable { showCompleted = !showCompleted }
                            .padding(horizontal = 4.dp, vertical = 2.dp)
                    )
                }
            }
        }

        ThingsDivider(insetStart = 16.dp)

        // Main Scrollable Reminder Stream
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(bottom = 72.dp)
        ) {
            when (route) {
                NavRoute.All -> {
                    state.liveLists.forEach { list ->
                        val listTint = ListStyle.colorFor(list.color)
                        val listTasks = state.activeTasksInList(list.id)
                        item(key = "hdr_${list.id}") {
                            Text(
                                text = list.name,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = listTint,
                                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 11.dp, bottom = 2.dp)
                            )
                        }
                        items(listTasks, key = { it.id }) { task ->
                            ReminderRow(
                                task = task,
                                state = state,
                                vm = vm,
                                accentTint = listTint,
                                showListBadge = false,
                                onOpenDue = { dueSheetTaskId = task.id },
                                onOpenTags = { tagSheetTaskId = task.id },
                                onPickPhoto = { pickPhotoFor(task.id) },
                                onPreviewImage = { previewImagePath = it },
                                onOpenInspector = { onOpenInspector(task.id) },
                                onReturnKey = { spawnInlineForRoute(list.id) }
                            )
                        }
                        item(key = "phantom_${list.id}") {
                            PhantomRow(onClick = { spawnInlineForRoute(list.id) })
                            ThingsDivider(insetStart = 16.dp)
                        }
                    }
                }

                NavRoute.Scheduled -> {
                    val items = state.scheduledTasks
                    val grouped = items.groupBy { DateUtils.upcomingGroupLabel(it.dueAt) }
                    grouped.forEach { (dayLabel, dayTasks) ->
                        item(key = "sched_$dayLabel") {
                            Text(
                                text = dayLabel,
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (dayLabel == "已逾期") c.danger else c.inkPrimary,
                                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 2.dp)
                            )
                        }
                        items(dayTasks, key = { it.id }) { task ->
                            val tint = ListStyle.colorFor(state.listFor(task.effectiveListId).color)
                            ReminderRow(
                                task = task,
                                state = state,
                                vm = vm,
                                accentTint = tint,
                                showListBadge = true,
                                onOpenDue = { dueSheetTaskId = task.id },
                                onOpenTags = { tagSheetTaskId = task.id },
                                onPickPhoto = { pickPhotoFor(task.id) },
                                onPreviewImage = { previewImagePath = it },
                                onOpenInspector = { onOpenInspector(task.id) },
                                onReturnKey = { spawnInlineForRoute() }
                            )
                        }
                    }
                    item(key = "phantom_sched") {
                        PhantomRow(onClick = { spawnInlineForRoute() })
                    }
                }

                NavRoute.Completed -> {
                    val grouped = state.completedTasks.groupBy { DateUtils.logbookDay(it.completedAt) }
                    if (grouped.isEmpty()) {
                        item {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 56.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("暂无已完成的提醒事项", color = c.inkTertiary, fontSize = 13.5.sp)
                            }
                        }
                    } else {
                        grouped.forEach { (dayLabel, dayTasks) ->
                            item(key = "done_$dayLabel") {
                                Text(
                                    text = dayLabel,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = c.inkSecondary,
                                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 2.dp)
                                )
                            }
                            items(dayTasks, key = { it.id }) { task ->
                                val tint = ListStyle.colorFor(state.listFor(task.effectiveListId).color)
                                ReminderRow(
                                    task = task,
                                    state = state,
                                    vm = vm,
                                    accentTint = tint,
                                    showListBadge = true,
                                    onOpenDue = { dueSheetTaskId = task.id },
                                    onOpenTags = { tagSheetTaskId = task.id },
                                    onPickPhoto = { pickPhotoFor(task.id) },
                                    onPreviewImage = { previewImagePath = it },
                                    onOpenInspector = { onOpenInspector(task.id) },
                                    onReturnKey = {}
                                )
                            }
                        }
                    }
                }

                else -> {
                    val activeTasks = when (route) {
                        NavRoute.Today -> state.todayTasks
                        NavRoute.Flagged -> state.flaggedTasks
                        is NavRoute.CustomList -> state.activeTasksInList(route.listId)
                        NavRoute.AllTags -> state.allTaggedActiveTasks()
                        is NavRoute.Tag -> state.activeTasksForTag(route.tagId)
                        else -> emptyList()
                    }
                    val showBadge = route !is NavRoute.CustomList
                    items(activeTasks, key = { it.id }) { task ->
                        val tint = ListStyle.colorFor(state.listFor(task.effectiveListId).color)
                        ReminderRow(
                            task = task,
                            state = state,
                            vm = vm,
                            accentTint = tint,
                            showListBadge = showBadge,
                            onOpenDue = { dueSheetTaskId = task.id },
                            onOpenTags = { tagSheetTaskId = task.id },
                            onPickPhoto = { pickPhotoFor(task.id) },
                            onPreviewImage = { previewImagePath = it },
                            onOpenInspector = { onOpenInspector(task.id) },
                            onReturnKey = { spawnInlineForRoute() }
                        )
                    }
                    item(key = "phantom_flat") {
                        PhantomRow(onClick = { spawnInlineForRoute() })
                    }
                }
            }

            if (route != NavRoute.Completed && showCompleted && completedForSection.isNotEmpty()) {
                item(key = "done_divider_hdr") {
                    Text(
                        text = "已完成",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = c.inkSecondary,
                        modifier = Modifier.padding(start = 16.dp, top = 14.dp, bottom = 2.dp)
                    )
                }
                items(completedForSection, key = { "done_${it.id}" }) { task ->
                    val tint = ListStyle.colorFor(state.listFor(task.effectiveListId).color)
                    ReminderRow(
                        task = task,
                        state = state,
                        vm = vm,
                        accentTint = tint,
                        showListBadge = route !is NavRoute.CustomList,
                        onOpenDue = { dueSheetTaskId = task.id },
                        onOpenTags = { tagSheetTaskId = task.id },
                        onPickPhoto = { pickPhotoFor(task.id) },
                        onPreviewImage = { previewImagePath = it },
                        onOpenInspector = { onOpenInspector(task.id) },
                        onReturnKey = {}
                    )
                }
            }
        }
    }

    // Inline Quick Date Picker Sheet
    dueSheetTaskId?.let { tid ->
        val t = state.liveTasks.firstOrNull { it.id == tid }
        if (t != null) {
            DueDateSheet(
                currentDue = t.dueAt,
                currentRepeat = t.repeatRule,
                onApply = { newDue, newRepeat ->
                    vm.updateTask(tid) { cur, now ->
                        cur.copy(
                            dueAt = newDue,
                            repeatRule = if (newDue == null) null else newRepeat,
                            stamps = cur.stamps + ("dueAt" to now) + ("repeatRule" to now)
                        )
                    }
                },
                onDismiss = { dueSheetTaskId = null }
            )
        }
    }

    // Inline Quick Tag Picker Sheet
    tagSheetTaskId?.let { tid ->
        val t = state.liveTasks.firstOrNull { it.id == tid }
        if (t != null) {
            ModalBottomSheet(
                onDismissRequest = { tagSheetTaskId = null },
                containerColor = c.cardSurface,
                shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
                dragHandle = { SheetDragHandle() }
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(horizontal = 18.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("选择标签", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.inkPrimary)
                    if (state.liveTags.isEmpty()) {
                        Text("暂无标签，可在首页标签栏添加", fontSize = 13.sp, color = c.inkTertiary)
                    } else {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(7.dp),
                            verticalArrangement = Arrangement.spacedBy(7.dp)
                        ) {
                            state.liveTags.forEach { tag ->
                                val on = t.tagIds.contains(tag.id)
                                val col = TagColors.colorFor(tag.hue)
                                ThingsPill(
                                    text = "#${tag.label}",
                                    textColor = if (on) Color.White else col,
                                    backgroundColor = if (on) col else col.copy(alpha = 0.14f),
                                    onClick = {
                                        vm.updateTask(tid) { cur, now ->
                                            val next = if (cur.tagIds.contains(tag.id)) cur.tagIds - tag.id else cur.tagIds + tag.id
                                            cur.copy(tagIds = next, stamps = cur.stamps + ("tagIds" to now))
                                        }
                                    }
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
    }

    // 1-Tap Zoomable Full-Screen Image Preview Dialog directly from list rows
    previewImagePath?.let { path ->
        com.lele.navigator.ui.components.ZoomableImageDialog(
            imagePath = path,
            onDismiss = { previewImagePath = null }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun ReminderRow(
    task: TaskItem,
    state: NavigatorUiState,
    vm: NavigatorViewModel,
    accentTint: Color,
    showListBadge: Boolean,
    onOpenDue: () -> Unit,
    onOpenTags: () -> Unit,
    onPickPhoto: () -> Unit,
    onPreviewImage: (String) -> Unit,
    onOpenInspector: () -> Unit,
    onReturnKey: () -> Unit
) {
    val c = ThingsTheme.colors
    val context = LocalContext.current
    val isEditing = state.editingTaskId == task.id
    val taskTags = remember(task.tagIds, state.tags) {
        task.tagIds.mapNotNull { id -> state.liveTags.firstOrNull { it.id == id } }
    }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    vm.toggleComplete(task.id)
                    false
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    vm.toggleFlag(task.id)
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = !isEditing,
        enableDismissFromEndToStart = !isEditing && !task.isDone,
        backgroundContent = {
            val dir = dismissState.dismissDirection
            val bg = when (dir) {
                SwipeToDismissBoxValue.StartToEnd -> c.logbookGreen
                SwipeToDismissBoxValue.EndToStart -> c.todayGold
                else -> Color.Transparent
            }
            val align = if (dir == SwipeToDismissBoxValue.StartToEnd) Alignment.CenterStart else Alignment.CenterEnd
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(bg)
                    .padding(horizontal = 20.dp),
                contentAlignment = align
            ) {
                if (dir == SwipeToDismissBoxValue.StartToEnd) {
                    Icon(Icons.Rounded.Check, contentDescription = "完成", tint = Color.White, modifier = Modifier.size(20.dp))
                } else if (dir == SwipeToDismissBoxValue.EndToStart) {
                    Icon(Icons.Rounded.Flag, contentDescription = "旗标", tint = Color.White, modifier = Modifier.size(20.dp))
                }
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(c.listBackground)
                .clickable(enabled = !isEditing) { vm.setEditingTask(task.id) }
        ) {
            Row(
                verticalAlignment = Alignment.Top,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 10.dp, end = 12.dp, top = 5.dp, bottom = 5.dp)
            ) {
                ThingsCheckbox(
                    checked = task.isDone,
                    tint = accentTint,
                    onCheckedChange = { vm.toggleComplete(task.id) }
                )

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(top = 5.dp, start = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    if (isEditing) {
                        var draftTitle by remember(task.id) { mutableStateOf(task.title) }
                        var draftNotes by remember(task.id) { mutableStateOf(task.notes) }
                        val focusRequester = remember { FocusRequester() }

                        LaunchedEffect(task.id) {
                            if (task.title.isEmpty()) {
                                delay(80)
                                runCatching { focusRequester.requestFocus() }
                            }
                        }

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (task.priorityPrefix.isNotEmpty()) {
                                Text(
                                    text = "${task.priorityPrefix} ",
                                    color = accentTint,
                                    fontSize = 14.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            BasicTextField(
                                value = draftTitle,
                                onValueChange = { valNext ->
                                    draftTitle = valNext
                                    vm.updateTask(task.id, debounced = true) { t, now ->
                                        t.copy(title = valNext, stamps = t.stamps + ("title" to now))
                                    }
                                },
                                textStyle = TextStyle(
                                    color = c.inkPrimary,
                                    fontSize = 14.5.sp,
                                    fontWeight = FontWeight.Normal
                                ),
                                cursorBrush = SolidColor(c.accentBlue),
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                                keyboardActions = KeyboardActions(onNext = {
                                    if (draftTitle.isBlank()) {
                                        vm.setEditingTask(null)
                                    } else {
                                        onReturnKey()
                                    }
                                }),
                                modifier = Modifier
                                    .weight(1f)
                                    .focusRequester(focusRequester),
                                decorationBox = { inner ->
                                    if (draftTitle.isEmpty()) {
                                        Text("新提醒事项", color = c.inkTertiary, fontSize = 14.5.sp)
                                    }
                                    inner()
                                }
                            )
                        }

                        // Multi-line Notes field
                        BasicTextField(
                            value = draftNotes,
                            onValueChange = { valNext ->
                                draftNotes = valNext
                                vm.updateTask(task.id, debounced = true) { t, now ->
                                    t.copy(notes = valNext, stamps = t.stamps + ("notes" to now))
                                }
                            },
                            textStyle = TextStyle(color = c.inkSecondary, fontSize = 13.sp, lineHeight = 18.sp),
                            cursorBrush = SolidColor(c.accentBlue),
                            minLines = 2,
                            maxLines = 8,
                            modifier = Modifier.fillMaxWidth(),
                            decorationBox = { inner ->
                                if (draftNotes.isEmpty()) {
                                    Text("备注（支持多行）", color = c.inkTertiary, fontSize = 13.sp)
                                }
                                inner()
                            }
                        )

                        // Inline Image Thumbnails right inside the notes area
                        if (task.attachments.isNotEmpty()) {
                            InlineThumbnailsRow(
                                attachments = task.attachments,
                                vm = vm,
                                editable = true,
                                onPreview = onPreviewImage,
                                onRemove = { name -> vm.removeAttachment(task.id, name) }
                            )
                        }

                        // Inline Quick Action Chips ([添加日期] [#] [旗标] [图片])
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                            verticalArrangement = Arrangement.spacedBy(5.dp),
                            modifier = Modifier.padding(top = 3.dp)
                        ) {
                            val dueInfo = DateUtils.dueLabel(task.dueAt, task.isDone)
                            ThingsPill(
                                text = dueInfo?.first ?: "添加日期",
                                textColor = when (dueInfo?.second) {
                                    2 -> c.danger
                                    1 -> c.accentBlue
                                    else -> c.inkSecondary
                                },
                                backgroundColor = if (dueInfo != null) c.accentBlueSoft else c.subtleFill,
                                icon = Icons.Rounded.CalendarToday,
                                onClick = onOpenDue
                            )
                            ThingsPill(
                                text = if (taskTags.isEmpty()) "#" else "# ${taskTags.size}",
                                textColor = if (taskTags.isEmpty()) c.inkSecondary else c.accentBlue,
                                backgroundColor = if (taskTags.isEmpty()) c.subtleFill else c.accentBlueSoft,
                                onClick = onOpenTags
                            )
                            ThingsPill(
                                text = if (task.flagged) "已标旗" else "旗标",
                                textColor = if (task.flagged) c.todayGold else c.inkSecondary,
                                backgroundColor = if (task.flagged) c.todayGoldSoft else c.subtleFill,
                                icon = Icons.Rounded.Flag,
                                onClick = { vm.toggleFlag(task.id) }
                            )
                            ThingsPill(
                                text = if (task.attachments.isEmpty()) "图片" else "图片 ${task.attachments.size}",
                                textColor = if (task.attachments.isEmpty()) c.inkSecondary else c.accentBlue,
                                backgroundColor = if (task.attachments.isEmpty()) c.subtleFill else c.accentBlueSoft,
                                icon = Icons.Rounded.Image,
                                onClick = onPickPhoto
                            )
                        }
                    } else {
                        // Compact Read-only Row
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (task.priorityPrefix.isNotEmpty()) {
                                Text(
                                    text = "${task.priorityPrefix} ",
                                    color = accentTint,
                                    fontSize = 14.5.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            Text(
                                text = task.title.ifBlank { "未命名提醒" },
                                fontSize = 14.5.sp,
                                lineHeight = 19.sp,
                                color = if (task.isDone) c.inkSecondary else c.inkPrimary,
                                textDecoration = if (task.isDone) TextDecoration.LineThrough else TextDecoration.None
                            )
                        }

                        if (task.notes.isNotBlank()) {
                            Text(
                                text = task.notes.trim(),
                                fontSize = 12.5.sp,
                                lineHeight = 17.sp,
                                color = c.inkSecondary,
                                maxLines = 4,
                                overflow = TextOverflow.Ellipsis
                            )
                        }

                        // Inline Image Thumbnails directly visible below notes — 1 tap to view!
                        if (task.attachments.isNotEmpty()) {
                            InlineThumbnailsRow(
                                attachments = task.attachments,
                                vm = vm,
                                editable = false,
                                onPreview = onPreviewImage,
                                onRemove = {}
                            )
                        }

                        if (task.url.isNotBlank()) {
                            Text(
                                text = task.url.trim(),
                                fontSize = 12.sp,
                                color = c.accentBlue,
                                textDecoration = TextDecoration.Underline,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.clickable {
                                    val raw = task.url.trim()
                                    val uri = Uri.parse(if (raw.contains("://")) raw else "https://$raw")
                                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                                }
                            )
                        }

                        val dueInfo = DateUtils.dueLabel(task.dueAt, task.isDone)
                        val hasMeta = dueInfo != null || taskTags.isNotEmpty() || task.checklistTotal > 0 || showListBadge
                        if (hasMeta) {
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(7.dp),
                                verticalArrangement = Arrangement.spacedBy(3.dp),
                                modifier = Modifier.padding(top = 1.dp)
                            ) {
                                if (dueInfo != null) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.CalendarToday,
                                            contentDescription = null,
                                            tint = when (dueInfo.second) {
                                                2 -> c.danger
                                                1 -> c.accentBlue
                                                else -> c.inkSecondary
                                            },
                                            modifier = Modifier.size(11.dp)
                                        )
                                        Text(
                                            text = dueInfo.first,
                                            fontSize = 11.5.sp,
                                            color = when (dueInfo.second) {
                                                2 -> c.danger
                                                1 -> c.accentBlue
                                                else -> c.inkSecondary
                                            }
                                        )
                                    }
                                }

                                if (showListBadge) {
                                    val l = state.listFor(task.effectiveListId)
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.5.dp)
                                    ) {
                                        Box(
                                            Modifier
                                                .size(5.5.dp)
                                                .clip(CircleShape)
                                                .background(ListStyle.colorFor(l.color))
                                        )
                                        Text(l.name, fontSize = 11.5.sp, color = c.inkSecondary)
                                    }
                                }

                                taskTags.forEach { tag ->
                                    Text(
                                        text = "#${tag.label}",
                                        fontSize = 11.5.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = TagColors.colorFor(tag.hue)
                                    )
                                }

                                if (task.checklistTotal > 0) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp)
                                    ) {
                                        MiniProgressRing(done = task.checklistDone, total = task.checklistTotal)
                                        Text(
                                            text = "${task.checklistDone}/${task.checklistTotal}",
                                            fontSize = 11.sp,
                                            color = c.inkSecondary
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                // Right side: Flag icon + Compact (i) Inspector Button
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    modifier = Modifier.padding(top = 3.dp)
                ) {
                    if (task.flagged && !isEditing) {
                        Icon(
                            imageVector = Icons.Rounded.Flag,
                            contentDescription = "已标旗",
                            tint = c.todayGold,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                    IconButton(
                        onClick = onOpenInspector,
                        modifier = Modifier.size(26.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Info,
                            contentDescription = "检查器详情",
                            tint = if (isEditing) c.todayGold else c.inkTertiary,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
            ThingsDivider(insetStart = 46.dp)
        }
    }
}

@Composable
private fun InlineThumbnailsRow(
    attachments: List<String>,
    vm: NavigatorViewModel,
    editable: Boolean,
    onPreview: (String) -> Unit,
    onRemove: (String) -> Unit
) {
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(top = 3.dp, bottom = 2.dp)
    ) {
        items(attachments, key = { it }) { name ->
            val path = remember(name) { vm.assetPath(name) }
            val bmp by produceState<android.graphics.Bitmap?>(initialValue = null, path) {
                value = withContext(Dispatchers.IO) {
                    if (path.isNotBlank() && File(path).exists()) BitmapFactory.decodeFile(path) else null
                }
            }
            Box(modifier = Modifier.size(48.dp)) {
                if (bmp != null) {
                    Image(
                        bitmap = bmp!!.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(RoundedCornerShape(7.dp))
                            .clickable { onPreview(path) }
                    )
                }
                if (editable) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .size(17.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.65f))
                            .clickable { onRemove(name) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            Icons.Rounded.Close,
                            contentDescription = "删除图片",
                            tint = Color.White,
                            modifier = Modifier.size(11.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PhantomRow(onClick: () -> Unit) {
    val c = ThingsTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(start = 16.dp, end = 14.dp, top = 8.dp, bottom = 8.dp)
    ) {
        Icon(
            imageVector = Icons.Rounded.AddCircleOutline,
            contentDescription = "新建提醒事项",
            tint = c.inkTertiary,
            modifier = Modifier.size(19.dp)
        )
        Spacer(Modifier.width(10.dp))
        Text("新提醒事项", fontSize = 13.5.sp, color = c.inkTertiary)
    }
}
