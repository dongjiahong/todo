package com.lele.navigator.ui

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.TagColors
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
import com.lele.navigator.ui.components.ThingsCheckbox
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.components.ThingsPill
import com.lele.navigator.ui.theme.ThingsTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Things 3-inspired floating white card task editor.
 * Clean borderless title + notes, circular subtask checklist, and subtle bottom metadata bar.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TaskDetailScreen(
    task: TaskItem,
    tags: List<TagItem>,
    vm: NavigatorViewModel,
    onBack: () -> Unit
) {
    val c = ThingsTheme.colors
    var newSubtask by remember { mutableStateOf("") }
    var showDueSheet by remember { mutableStateOf(false) }
    var showTagPicker by remember { mutableStateOf(false) }
    var previewPath by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    val photoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    val bytes = stream.readBytes()
                    if (bytes.isNotEmpty()) {
                        vm.attachImage(task.id, bytes, "jpg")
                    }
                }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(c.hubBackground)
            .statusBarsPadding()
            .imePadding()
    ) {
        // Minimal Things 3 top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(onClick = onBack)
                    .padding(horizontal = 6.dp, vertical = 6.dp)
            ) {
                Icon(
                    imageVector = Icons.Rounded.ChevronLeft,
                    contentDescription = "返回",
                    tint = c.accentBlue,
                    modifier = Modifier.size(24.dp)
                )
                Text(
                    text = "返回",
                    color = c.accentBlue,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(Modifier.weight(1f))

            IconButton(
                onClick = {
                    photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
            ) {
                Icon(
                    imageVector = Icons.Rounded.AddPhotoAlternate,
                    contentDescription = "添加图片",
                    tint = c.inkSecondary,
                    modifier = Modifier.size(21.dp)
                )
            }

            IconButton(
                onClick = {
                    vm.deleteTask(task.id)
                    onBack()
                }
            ) {
                Icon(
                    imageVector = Icons.Rounded.DeleteOutline,
                    contentDescription = "删除任务",
                    tint = c.danger,
                    modifier = Modifier.size(21.dp)
                )
            }
        }

        // Scrollable floating Things 3 card
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(18.dp),
                color = c.cardSurface,
                shadowElevation = if (c.isDark) 0.dp else 2.dp,
                modifier = Modifier
                    .fillMaxWidth()
                    .border(
                        width = 0.6.dp,
                        color = c.divider.copy(alpha = 0.8f),
                        shape = RoundedCornerShape(18.dp)
                    )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    // Title row with Things checkbox
                    Row(
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        ThingsCheckbox(
                            checked = task.isDone,
                            isDoing = task.isDoing,
                            onCheckedChange = { vm.toggleComplete(task.id) },
                            modifier = Modifier.offset(x = (-6).dp, y = (-4).dp)
                        )
                        BasicTextField(
                            value = task.title,
                            onValueChange = { valText ->
                                vm.updateTask(task.id, debounced = true) { t, now ->
                                    t.copy(title = valText, stamps = t.stamps + ("title" to now))
                                }
                            },
                            textStyle = TextStyle(
                                color = if (task.isDone) c.inkSecondary else c.inkPrimary,
                                fontSize = 19.sp,
                                lineHeight = 26.sp,
                                fontWeight = FontWeight.SemiBold,
                                textDecoration = if (task.isDone) TextDecoration.LineThrough else TextDecoration.None
                            ),
                            cursorBrush = SolidColor(c.accentBlue),
                            modifier = Modifier
                                .weight(1f)
                                .offset(x = (-6).dp),
                            decorationBox = { inner ->
                                if (task.title.isEmpty()) {
                                    Text(
                                        "新待办事项",
                                        color = c.inkTertiary,
                                        fontSize = 19.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                                inner()
                            }
                        )
                    }

                    // Seamless borderless Notes editor
                    BasicTextField(
                        value = task.notes,
                        onValueChange = { text ->
                            vm.updateTask(task.id, debounced = true) { t, now ->
                                t.copy(notes = text, stamps = t.stamps + ("notes" to now))
                            }
                        },
                        textStyle = TextStyle(
                            color = c.inkPrimary,
                            fontSize = 14.5.sp,
                            lineHeight = 22.sp
                        ),
                        cursorBrush = SolidColor(c.accentBlue),
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = 76.dp)
                            .padding(start = 28.dp),
                        decorationBox = { inner ->
                            if (task.notes.isEmpty()) {
                                Text(
                                    "备注",
                                    color = c.inkTertiary,
                                    fontSize = 14.5.sp
                                )
                            }
                            inner()
                        }
                    )

                    // Auto-detected clickable URLs from notes
                    val noteUrls = remember(task.notes) { extractUrlsFromText(task.notes) }
                    if (noteUrls.isNotEmpty()) {
                        Column(
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 28.dp)
                        ) {
                            noteUrls.forEach { urlStr ->
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .clickable {
                                            runCatching {
                                                val target = if (urlStr.startsWith("http")) urlStr else "https://$urlStr"
                                                context.startActivity(
                                                    android.content.Intent(
                                                        android.content.Intent.ACTION_VIEW,
                                                        android.net.Uri.parse(target)
                                                    )
                                                )
                                            }
                                        }
                                        .padding(vertical = 2.dp)
                                ) {
                                    Icon(
                                        Icons.Rounded.Link,
                                        contentDescription = null,
                                        tint = c.accentBlue,
                                        modifier = Modifier.size(14.dp)
                                    )
                                    Text(
                                        text = urlStr,
                                        color = c.accentBlue,
                                        fontSize = 13.sp,
                                        maxLines = 1
                                    )
                                }
                            }
                        }
                    }

                    // Inline Checklist / Subtasks
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 22.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        if (task.subtasks.isNotEmpty()) {
                            ThingsDivider(modifier = Modifier.padding(bottom = 8.dp))
                        }

                        task.subtasks.forEach { sub ->
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                ThingsCheckbox(
                                    checked = sub.done,
                                    isCircular = true,
                                    size = 16.dp,
                                    onCheckedChange = { vm.toggleSubtask(task.id, sub.id) }
                                )
                                BasicTextField(
                                    value = sub.title,
                                    onValueChange = { valText ->
                                        vm.updateSubtaskTitle(task.id, sub.id, valText)
                                    },
                                    textStyle = TextStyle(
                                        fontSize = 14.sp,
                                        lineHeight = 20.sp,
                                        textDecoration = if (sub.done) TextDecoration.LineThrough else TextDecoration.None,
                                        color = if (sub.done) c.inkTertiary else c.inkPrimary
                                    ),
                                    cursorBrush = SolidColor(c.accentBlue),
                                    modifier = Modifier.weight(1f)
                                )
                                Box(
                                    modifier = Modifier
                                        .size(34.dp)
                                        .clip(CircleShape)
                                        .clickable { vm.deleteSubtask(task.id, sub.id) },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        Icons.Rounded.Close,
                                        contentDescription = "移除子任务",
                                        tint = c.inkTertiary,
                                        modifier = Modifier.size(15.dp)
                                    )
                                }
                            }
                        }

                        // Borderless inline add-subtask field
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp)
                        ) {
                            Box(
                                modifier = Modifier.size(34.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Add,
                                    contentDescription = null,
                                    tint = if (newSubtask.isNotBlank()) c.accentBlue else c.inkTertiary,
                                    modifier = Modifier
                                        .size(17.dp)
                                        .clickable(enabled = newSubtask.isNotBlank()) {
                                            vm.addSubtask(task.id, newSubtask)
                                            newSubtask = ""
                                        }
                                )
                            }
                            BasicTextField(
                                value = newSubtask,
                                onValueChange = { newSubtask = it },
                                singleLine = true,
                                textStyle = TextStyle(color = c.inkPrimary, fontSize = 14.sp),
                                cursorBrush = SolidColor(c.accentBlue),
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                                keyboardActions = KeyboardActions(onDone = {
                                    if (newSubtask.isNotBlank()) {
                                        vm.addSubtask(task.id, newSubtask)
                                        newSubtask = ""
                                    }
                                }),
                                modifier = Modifier.weight(1f),
                                decorationBox = { inner ->
                                    if (newSubtask.isEmpty()) {
                                        Text("添加子任务…", color = c.inkTertiary, fontSize = 14.sp)
                                    }
                                    inner()
                                }
                            )
                        }
                    }

                    // Image Attachments (async downsampled thumbnails + tap to preview)
                    if (task.attachments.isNotEmpty()) {
                        ThingsDivider()
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                        ) {
                            task.attachments.forEach { name ->
                                val path = remember(name) { vm.assetPath(name) }
                                val bitmap by produceState<ImageBitmap?>(initialValue = null, key1 = path) {
                                    value = if (path.isNotBlank()) {
                                        withContext(Dispatchers.IO) { loadDownsampledBitmap(path, 256) }
                                    } else null
                                }
                                if (bitmap != null) {
                                    Box(modifier = Modifier.size(86.dp)) {
                                        Image(
                                            bitmap = bitmap!!,
                                            contentDescription = "附件图片",
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .clip(RoundedCornerShape(12.dp))
                                                .clickable { previewPath = path }
                                        )
                                        Box(
                                            modifier = Modifier
                                                .align(Alignment.TopEnd)
                                                .padding(4.dp)
                                                .size(20.dp)
                                                .clip(CircleShape)
                                                .background(Color.Black.copy(alpha = 0.58f))
                                                .clickable { vm.removeAttachment(task.id, name) },
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Icon(
                                                Icons.Rounded.Close,
                                                contentDescription = "移除图片",
                                                tint = Color.White,
                                                modifier = Modifier.size(13.dp)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ThingsDivider()

                    // Bottom Metadata Strip: Due Date + Tags
                    val dueInfo = DateUtils.dueLabel(task.dueAt, settled = task.isDone)
                    val repeatLabel = when (task.repeatRule) {
                        "daily" -> " · 每天"
                        "weekly" -> " · 每周"
                        "monthly" -> " · 每月"
                        "yearly" -> " · 每年"
                        else -> ""
                    }
                    val dueTextColor = when (dueInfo?.second) {
                        2 -> c.danger
                        1 -> c.todayGold
                        else -> if (dueInfo != null) c.accentBlue else c.inkSecondary
                    }
                    val dueBgColor = when (dueInfo?.second) {
                        2 -> c.dangerSoft
                        1 -> c.todayGoldSoft
                        else -> if (dueInfo != null) c.accentBlueSoft else c.subtleFill
                    }

                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        ThingsPill(
                            text = (dueInfo?.first ?: "设置时间") + repeatLabel,
                            textColor = dueTextColor,
                            backgroundColor = dueBgColor,
                            icon = Icons.Rounded.CalendarToday,
                            onClick = { showDueSheet = true }
                        )

                        // Active tags on this task
                        val activeTags = task.tagIds.mapNotNull { id -> tags.firstOrNull { it.id == id } }
                        activeTags.forEach { tag ->
                            val tagColor = TagColors.colorFor(tag.hue)
                            ThingsPill(
                                text = tag.label,
                                textColor = tagColor,
                                backgroundColor = tagColor.copy(alpha = if (c.isDark) 0.2f else 0.12f),
                                dotColor = tagColor,
                                onClick = { showTagPicker = !showTagPicker }
                            )
                        }

                        if (tags.isNotEmpty()) {
                            ThingsPill(
                                text = if (showTagPicker) "收起标签" else "标签",
                                textColor = c.inkSecondary,
                                backgroundColor = c.subtleFill,
                                icon = Icons.Rounded.Sell,
                                onClick = { showTagPicker = !showTagPicker }
                            )
                        }
                    }

                    // Expandable inline tag selector
                    if (showTagPicker && tags.isNotEmpty()) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(c.elevatedSurface)
                                .padding(10.dp)
                        ) {
                            tags.forEach { tag ->
                                val selected = task.tagIds.contains(tag.id)
                                val tagColor = TagColors.colorFor(tag.hue)
                                ThingsPill(
                                    text = tag.label,
                                    textColor = if (selected) tagColor else c.inkSecondary,
                                    backgroundColor = if (selected) tagColor.copy(alpha = if (c.isDark) 0.22f else 0.14f) else c.cardSurface,
                                    dotColor = tagColor,
                                    onClick = {
                                        vm.updateTask(task.id) { t, now ->
                                            val next = if (selected) t.tagIds - tag.id else t.tagIds + tag.id
                                            t.copy(tagIds = next, stamps = t.stamps + ("tagIds" to now))
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }

            // Sleek Segmented Status Control outside the main card
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = c.cardSurface,
                modifier = Modifier
                    .fillMaxWidth()
                    .border(0.6.dp, c.divider.copy(alpha = 0.8f), RoundedCornerShape(14.dp))
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(5.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    listOf("todo" to "待办", "doing" to "进行中", "done" to "已完成").forEach { (id, label) ->
                        val active = task.status == id
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(10.dp))
                                .background(
                                    when {
                                        active && id == "doing" -> c.doingBlueSoft
                                        active && id == "done" -> c.logbookGreenSoft
                                        active -> c.subtleFill
                                        else -> Color.Transparent
                                    }
                                )
                                .clickable {
                                    if (id == "done") {
                                        if (!task.isDone) vm.toggleComplete(task.id)
                                    } else {
                                        vm.updateTask(task.id) { t, now ->
                                            t.copy(
                                                status = id,
                                                completedAt = null,
                                                stamps = t.stamps + ("status" to now) + ("completedAt" to now)
                                            )
                                        }
                                    }
                                }
                                .padding(vertical = 10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = label,
                                fontSize = 13.5.sp,
                                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                                color = when {
                                    active && id == "doing" -> c.doingBlue
                                    active && id == "done" -> c.logbookGreen
                                    active -> c.inkPrimary
                                    else -> c.inkSecondary
                                }
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(36.dp))
        }
    }

    if (showDueSheet) {
        DueDateSheet(
            currentDue = task.dueAt,
            currentRepeat = task.repeatRule,
            onApply = { newDue, newRepeat ->
                vm.updateTask(task.id) { t, now ->
                    t.copy(
                        dueAt = newDue,
                        repeatRule = if (newDue.isNullOrBlank()) null else newRepeat,
                        stamps = t.stamps + ("dueAt" to now) + ("repeatRule" to now)
                    )
                }
            },
            onDismiss = { showDueSheet = false }
        )
    }

    previewPath?.let { path ->
        val fullBitmap by produceState<ImageBitmap?>(initialValue = null, key1 = path) {
            value = withContext(Dispatchers.IO) { loadDownsampledBitmap(path, 1600) }
        }
        Dialog(
            onDismissRequest = { previewPath = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.92f))
                    .clickable { previewPath = null },
                contentAlignment = Alignment.Center
            ) {
                fullBitmap?.let { bmp ->
                    Image(
                        bitmap = bmp,
                        contentDescription = "大图预览",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp)
                    )
                }
                IconButton(
                    onClick = { previewPath = null },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .statusBarsPadding()
                        .padding(12.dp)
                ) {
                    Icon(
                        Icons.Rounded.Close,
                        contentDescription = "关闭预览",
                        tint = Color.White
                    )
                }
            }
        }
    }
}

private fun loadDownsampledBitmap(path: String, reqSizePx: Int): ImageBitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    val w = bounds.outWidth
    val h = bounds.outHeight
    if (w <= 0 || h <= 0) return null
    var sampleSize = 1
    while (w / (sampleSize * 2) >= reqSizePx || h / (sampleSize * 2) >= reqSizePx) {
        sampleSize *= 2
    }
    val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
    return BitmapFactory.decodeFile(path, opts)?.asImageBitmap()
}

private fun extractUrlsFromText(text: String): List<String> {
    if (text.isBlank()) return emptyList()
    val matcher = android.util.Patterns.WEB_URL.matcher(text)
    val seen = LinkedHashSet<String>()
    while (matcher.find()) {
        val raw = matcher.group() ?: continue
        if (raw.contains(".")) {
            seen.add(raw)
        }
    }
    return seen.toList()
}
