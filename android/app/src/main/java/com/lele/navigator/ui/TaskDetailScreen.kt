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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import com.lele.navigator.model.ListStyle
import com.lele.navigator.model.TagColors
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
import com.lele.navigator.model.TaskListItem
import com.lele.navigator.ui.components.ThingsCheckbox
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.components.ThingsPill
import com.lele.navigator.ui.theme.ThingsTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Apple Reminders `(i)` Inspector ModalBottomSheet for Android.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TaskInspectorSheet(
    task: TaskItem,
    lists: List<TaskListItem>,
    tags: List<TagItem>,
    vm: NavigatorViewModel,
    onDismiss: () -> Unit
) {
    val c = ThingsTheme.colors
    val context = LocalContext.current
    var title by remember(task.id) { mutableStateOf(task.title) }
    var notes by remember(task.id) { mutableStateOf(task.notes) }
    var urlText by remember(task.id) { mutableStateOf(task.url) }
    var newSubtask by remember(task.id) { mutableStateOf("") }
    var showDueSheet by remember { mutableStateOf(false) }
    var previewFile by remember { mutableStateOf<String?>(null) }

    val photoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }.getOrNull()?.let { bytes ->
                vm.attachImage(task.id, bytes, "jpg")
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.hubBackground,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = { SheetDragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header bar
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("详细信息", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.inkPrimary)
                Spacer(Modifier.weight(1f))
                Text(
                    text = "完成",
                    fontSize = 15.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = c.accentBlue,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable(onClick = onDismiss)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }

            // Card 1: Title, Notes, URL
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.cardSurface)
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                BasicTextField(
                    value = title,
                    onValueChange = { valNext ->
                        title = valNext
                        vm.updateTask(task.id, debounced = true) { t, now ->
                            t.copy(title = valNext, stamps = t.stamps + ("title" to now))
                        }
                    },
                    textStyle = TextStyle(color = c.inkPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
                    cursorBrush = SolidColor(c.accentBlue),
                    modifier = Modifier.fillMaxWidth(),
                    decorationBox = { inner ->
                        if (title.isEmpty()) Text("标题", color = c.inkTertiary, fontSize = 17.sp)
                        inner()
                    }
                )
                ThingsDivider()
                BasicTextField(
                    value = notes,
                    onValueChange = { valNext ->
                        notes = valNext
                        vm.updateTask(task.id, debounced = true) { t, now ->
                            t.copy(notes = valNext, stamps = t.stamps + ("notes" to now))
                        }
                    },
                    textStyle = TextStyle(color = c.inkSecondary, fontSize = 14.5.sp),
                    cursorBrush = SolidColor(c.accentBlue),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 44.dp),
                    decorationBox = { inner ->
                        if (notes.isEmpty()) Text("备注", color = c.inkTertiary, fontSize = 14.5.sp)
                        inner()
                    }
                )
                ThingsDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BasicTextField(
                        value = urlText,
                        onValueChange = { valNext ->
                            urlText = valNext
                            vm.updateTask(task.id, debounced = true) { t, now ->
                                t.copy(url = valNext.trim(), stamps = t.stamps + ("url" to now))
                            }
                        },
                        singleLine = true,
                        textStyle = TextStyle(color = c.accentBlue, fontSize = 14.sp),
                        cursorBrush = SolidColor(c.accentBlue),
                        modifier = Modifier.weight(1f),
                        decorationBox = { inner ->
                            if (urlText.isEmpty()) Text("URL", color = c.inkTertiary, fontSize = 14.sp)
                            inner()
                        }
                    )
                    if (urlText.isNotBlank()) {
                        IconButton(
                            onClick = {
                                val raw = urlText.trim()
                                val uri = Uri.parse(if (raw.contains("://")) raw else "https://$raw")
                                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                            },
                            modifier = Modifier.size(30.dp)
                        ) {
                            Icon(Icons.Rounded.OpenInNew, contentDescription = "打开链接", tint = c.accentBlue, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }

            // Card 2: Date/Time & Flag
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.cardSurface)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showDueSheet = true }
                        .padding(horizontal = 14.dp, vertical = 12.dp)
                ) {
                    IconBox(Icons.Rounded.CalendarToday, c.upcomingCoral)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("日期与时间", fontSize = 15.sp, color = c.inkPrimary)
                        val label = DateUtils.dueLabel(task.dueAt, task.isDone)?.first
                        if (label != null) {
                            Text(
                                text = label + repeatLabel(task.repeatRule),
                                fontSize = 12.5.sp,
                                color = c.accentBlue
                            )
                        }
                    }
                    Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = c.inkTertiary)
                }

                ThingsDivider(insetStart = 54.dp)

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 8.dp)
                ) {
                    IconBox(Icons.Rounded.Flag, c.todayGold)
                    Spacer(Modifier.width(12.dp))
                    Text("旗标", fontSize = 15.sp, color = c.inkPrimary, modifier = Modifier.weight(1f))
                    Switch(
                        checked = task.flagged,
                        onCheckedChange = { vm.toggleFlag(task.id) }
                    )
                }
            }

            // Card 3: Priority & List Picker
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.cardSurface)
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("优先级", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    listOf(0 to "无", 1 to "低 !", 2 to "中 !!", 3 to "高 !!!").forEach { (p, lbl) ->
                        val active = task.priority == p
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(9.dp))
                                .background(if (active) c.accentBlue else c.subtleFill)
                                .clickable { vm.setPriority(task.id, p) }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = lbl,
                                fontSize = 13.sp,
                                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                                color = if (active) Color.White else c.inkPrimary
                            )
                        }
                    }
                }

                ThingsDivider()

                Text("列表", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSecondary)
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    lists.forEach { list ->
                        val active = task.effectiveListId == list.id
                        val lColor = ListStyle.colorFor(list.color)
                        ThingsPill(
                            text = list.name,
                            textColor = if (active) Color.White else c.inkPrimary,
                            backgroundColor = if (active) lColor else c.subtleFill,
                            dotColor = if (active) Color.White else lColor,
                            onClick = { vm.moveTaskToList(task.id, list.id) }
                        )
                    }
                }
            }

            // Card 4: Tags
            if (tags.isNotEmpty()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(c.cardSurface)
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("标签", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSecondary)
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        tags.forEach { tag ->
                            val on = task.tagIds.contains(tag.id)
                            val col = TagColors.colorFor(tag.hue)
                            ThingsPill(
                                text = "#${tag.label}",
                                textColor = if (on) Color.White else col,
                                backgroundColor = if (on) col else col.copy(alpha = 0.14f),
                                onClick = {
                                    vm.updateTask(task.id) { cur, now ->
                                        val next = if (cur.tagIds.contains(tag.id)) cur.tagIds - tag.id else cur.tagIds + tag.id
                                        cur.copy(tagIds = next, stamps = cur.stamps + ("tagIds" to now))
                                    }
                                }
                            )
                        }
                    }
                }
            }

            // Card 5: Subtasks
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.cardSurface)
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("子任务", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSecondary)
                    if (task.checklistTotal > 0) {
                        Spacer(Modifier.width(6.dp))
                        Text("${task.checklistDone}/${task.checklistTotal}", fontSize = 12.sp, color = c.inkTertiary)
                    }
                }

                task.subtasks.forEach { st ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        ThingsCheckbox(
                            checked = st.done,
                            size = 18.dp,
                            onCheckedChange = { vm.toggleSubtask(task.id, st.id) }
                        )
                        Text(
                            text = st.title,
                            fontSize = 14.5.sp,
                            color = if (st.done) c.inkSecondary else c.inkPrimary,
                            textDecoration = if (st.done) TextDecoration.LineThrough else TextDecoration.None,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(
                            onClick = { vm.deleteSubtask(task.id, st.id) },
                            modifier = Modifier.size(28.dp)
                        ) {
                            Icon(Icons.Rounded.Close, contentDescription = "删除子任务", tint = c.inkTertiary, modifier = Modifier.size(16.dp))
                        }
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Add, contentDescription = null, tint = c.accentBlue, modifier = Modifier.size(18.dp))
                    BasicTextField(
                        value = newSubtask,
                        onValueChange = { newSubtask = it },
                        singleLine = true,
                        textStyle = TextStyle(color = c.inkPrimary, fontSize = 14.5.sp),
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
                            if (newSubtask.isEmpty()) Text("添加子任务…", color = c.inkTertiary, fontSize = 14.5.sp)
                            inner()
                        }
                    )
                    if (newSubtask.isNotBlank()) {
                        Text(
                            text = "添加",
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = c.accentBlue,
                            modifier = Modifier.clickable {
                                vm.addSubtask(task.id, newSubtask)
                                newSubtask = ""
                            }
                        )
                    }
                }
            }

            // Card 6: Images
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.cardSurface)
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        }
                ) {
                    Icon(Icons.Rounded.AddPhotoAlternate, contentDescription = null, tint = c.accentBlue, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("添加图像…", fontSize = 15.sp, color = c.accentBlue, fontWeight = FontWeight.Medium)
                }

                if (task.attachments.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(task.attachments, key = { it }) { name ->
                            val path = remember(name) { vm.assetPath(name) }
                            val bmp by produceState<android.graphics.Bitmap?>(initialValue = null, path) {
                                value = withContext(Dispatchers.IO) {
                                    if (path.isNotBlank() && File(path).exists()) BitmapFactory.decodeFile(path) else null
                                }
                            }
                            Box(modifier = Modifier.size(72.dp)) {
                                if (bmp != null) {
                                    Image(
                                        bitmap = bmp!!.asImageBitmap(),
                                        contentDescription = null,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .clip(RoundedCornerShape(10.dp))
                                            .clickable { previewFile = path }
                                    )
                                }
                                Box(
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .size(20.dp)
                                        .clip(CircleShape)
                                        .background(Color.Black.copy(alpha = 0.6f))
                                        .clickable { vm.removeAttachment(task.id, name) },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(Icons.Rounded.Close, contentDescription = "删除图片", tint = Color.White, modifier = Modifier.size(13.dp))
                                }
                            }
                        }
                    }
                }
            }

            // Delete Button
            Button(
                onClick = {
                    vm.deleteTask(task.id)
                    onDismiss()
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = c.dangerSoft,
                    contentColor = c.danger
                ),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(46.dp)
            ) {
                Icon(Icons.Rounded.DeleteOutline, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("删除提醒事项", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }

            Spacer(Modifier.height(12.dp))
        }
    }

    if (showDueSheet) {
        DueDateSheet(
            currentDue = task.dueAt,
            currentRepeat = task.repeatRule,
            onApply = { newDue, newRepeat ->
                vm.updateTask(task.id) { cur, now ->
                    cur.copy(
                        dueAt = newDue,
                        repeatRule = if (newDue == null) null else newRepeat,
                        stamps = cur.stamps + ("dueAt" to now) + ("repeatRule" to now)
                    )
                }
            },
            onDismiss = { showDueSheet = false }
        )
    }

    previewFile?.let { path ->
        com.lele.navigator.ui.components.ZoomableImageDialog(
            imagePath = path,
            onDismiss = { previewFile = null }
        )
    }
}

@Composable
private fun IconBox(icon: androidx.compose.ui.graphics.vector.ImageVector, bg: Color) {
    Box(
        modifier = Modifier
            .size(28.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(bg),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
    }
}

private fun repeatLabel(rule: String?): String = when (rule) {
    "daily" -> " · 每天"
    "weekly" -> " · 每周"
    "monthly" -> " · 每月"
    "yearly" -> " · 每年"
    else -> ""
}
