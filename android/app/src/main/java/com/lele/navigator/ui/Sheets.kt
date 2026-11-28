package com.lele.navigator.ui

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.ListStyle
import com.lele.navigator.model.TagColors
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskListItem
import com.lele.navigator.notify.ReminderScheduler
import com.lele.navigator.ui.components.ThingsDivider
import com.lele.navigator.ui.components.ThingsPill
import com.lele.navigator.ui.theme.ThingsTheme
import kotlinx.coroutines.delay

@Composable
fun SheetDragHandle() {
    val c = ThingsTheme.colors
    Box(
        modifier = Modifier
            .padding(top = 10.dp, bottom = 4.dp)
            .width(36.dp)
            .height(4.dp)
            .clip(CircleShape)
            .background(c.divider)
    )
}

@Composable
fun CleanRoundedInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text
) {
    val c = ThingsTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(11.dp))
            .background(c.subtleFill)
            .padding(horizontal = 14.dp, vertical = 12.dp)
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = TextStyle(color = c.inkPrimary, fontSize = 15.sp),
            cursorBrush = SolidColor(c.accentBlue),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            modifier = Modifier.fillMaxWidth(),
            decorationBox = { inner ->
                if (value.isEmpty()) {
                    Text(placeholder, color = c.inkTertiary, fontSize = 15.sp)
                }
                inner()
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AddListSheet(
    editing: TaskListItem?,
    canDelete: Boolean,
    onDismiss: () -> Unit,
    onSave: (String, String, String) -> Unit,
    onDelete: (() -> Unit)? = null
) {
    val c = ThingsTheme.colors
    var name by remember(editing?.id) { mutableStateOf(editing?.name ?: "") }
    var color by remember(editing?.id) { mutableStateOf(editing?.color ?: "blue") }
    var icon by remember(editing?.id) { mutableStateOf(editing?.icon ?: "list") }
    val selectedColor = ListStyle.colorFor(color)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.cardSurface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = { SheetDragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "取消",
                    fontSize = 15.5.sp,
                    color = c.inkSecondary,
                    modifier = Modifier.clickable(onClick = onDismiss)
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = if (editing == null) "新建列表" else "编辑列表",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = c.inkPrimary
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = "完成",
                    fontSize = 15.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (name.isNotBlank()) c.accentBlue else c.inkTertiary,
                    modifier = Modifier.clickable(enabled = name.isNotBlank()) {
                        onSave(name.trim(), color, icon)
                        onDismiss()
                    }
                )
            }

            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(selectedColor),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = ListStyle.iconFor(icon),
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(30.dp)
                )
            }

            CleanRoundedInput(
                value = name,
                onValueChange = { name = it },
                placeholder = "列表名称"
            )

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                ListStyle.allColors.forEach { key ->
                    val col = ListStyle.colorFor(key)
                    val active = color == key
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .border(
                                width = if (active) 2.5.dp else 0.dp,
                                color = if (active) c.inkPrimary.copy(alpha = 0.4f) else Color.Transparent,
                                shape = CircleShape
                            )
                            .padding(3.dp)
                            .clip(CircleShape)
                            .background(col)
                            .clickable { color = key }
                    )
                }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                ListStyle.allIcons.forEach { key ->
                    val active = icon == key
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(if (active) selectedColor.copy(alpha = 0.18f) else c.subtleFill)
                            .border(
                                width = if (active) 1.5.dp else 0.dp,
                                color = if (active) selectedColor else Color.Transparent,
                                shape = CircleShape
                            )
                            .clickable { icon = key },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = ListStyle.iconFor(key),
                            contentDescription = null,
                            tint = if (active) selectedColor else c.inkSecondary,
                            modifier = Modifier.size(19.dp)
                        )
                    }
                }
            }

            if (editing != null && canDelete && onDelete != null) {
                ThingsDivider()
                Text(
                    text = "删除列表",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = c.danger,
                    modifier = Modifier
                        .clickable {
                            onDelete()
                            onDismiss()
                        }
                        .padding(vertical = 6.dp)
                )
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun QuickCaptureSheet(
    lists: List<TaskListItem>,
    tags: List<TagItem>,
    defaultListId: String,
    defaultFlagged: Boolean,
    defaultDue: String?,
    defaultTagIds: List<String>,
    onDismiss: () -> Unit,
    onSave: (String, String, Boolean, List<String>, String?) -> Unit
) {
    val c = ThingsTheme.colors
    var title by remember { mutableStateOf("") }
    var listId by remember { mutableStateOf(defaultListId) }
    var flagged by remember { mutableStateOf(defaultFlagged) }
    var selectedTags by remember { mutableStateOf(defaultTagIds.toSet()) }
    var dueAt by remember { mutableStateOf(defaultDue) }
    var showDueSheet by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        delay(100)
        runCatching { focusRequester.requestFocus() }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.cardSurface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = { SheetDragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Box(
                    modifier = Modifier
                        .padding(top = 3.dp)
                        .size(20.dp)
                        .clip(CircleShape)
                        .border(1.6.dp, c.checkboxBorder, CircleShape)
                )
                BasicTextField(
                    value = title,
                    onValueChange = { title = it },
                    textStyle = TextStyle(
                        color = c.inkPrimary,
                        fontSize = 18.sp,
                        lineHeight = 25.sp,
                        fontWeight = FontWeight.Medium
                    ),
                    cursorBrush = SolidColor(c.accentBlue),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = {
                        if (title.isNotBlank()) {
                            onSave(title, listId, flagged, selectedTags.toList(), dueAt)
                            onDismiss()
                        }
                    }),
                    modifier = Modifier
                        .weight(1f)
                        .focusRequester(focusRequester),
                    decorationBox = { inner ->
                        if (title.isEmpty()) {
                            Text("新提醒事项", color = c.inkTertiary, fontSize = 18.sp)
                        }
                        inner()
                    }
                )
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                val dueLabel = DateUtils.dueLabel(dueAt)?.first
                ThingsPill(
                    text = dueLabel ?: "添加日期",
                    textColor = if (dueAt != null) c.accentBlue else c.inkSecondary,
                    backgroundColor = if (dueAt != null) c.accentBlueSoft else c.subtleFill,
                    icon = Icons.Rounded.CalendarToday,
                    onClick = { showDueSheet = true }
                )
                ThingsPill(
                    text = "旗标",
                    textColor = if (flagged) c.todayGold else c.inkSecondary,
                    backgroundColor = if (flagged) c.todayGoldSoft else c.subtleFill,
                    icon = Icons.Rounded.Flag,
                    onClick = { flagged = !flagged }
                )
                lists.forEach { list ->
                    val on = listId == list.id
                    val col = ListStyle.colorFor(list.color)
                    ThingsPill(
                        text = list.name,
                        textColor = if (on) Color.White else c.inkSecondary,
                        backgroundColor = if (on) col else c.subtleFill,
                        dotColor = if (on) Color.White else col,
                        onClick = { listId = list.id }
                    )
                }
                tags.forEach { tag ->
                    val on = selectedTags.contains(tag.id)
                    val col = TagColors.colorFor(tag.hue)
                    ThingsPill(
                        text = "#${tag.label}",
                        textColor = if (on) Color.White else col,
                        backgroundColor = if (on) col else col.copy(alpha = 0.14f),
                        onClick = {
                            selectedTags = if (on) selectedTags - tag.id else selectedTags + tag.id
                        }
                    )
                }
            }

            ThingsDivider()

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = {
                        onSave(title, listId, flagged, selectedTags.toList(), dueAt)
                        onDismiss()
                    },
                    enabled = title.isNotBlank(),
                    shape = RoundedCornerShape(11.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = c.accentBlue,
                        contentColor = Color.White,
                        disabledContainerColor = c.subtleFill,
                        disabledContentColor = c.inkTertiary
                    ),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)
                ) {
                    Text("添加", fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(6.dp))
        }
    }

    if (showDueSheet) {
        DueDateSheet(
            currentDue = dueAt,
            currentRepeat = null,
            onApply = { newDue, _ -> dueAt = newDue },
            onDismiss = { showDueSheet = false }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncPairingSheet(
    state: NavigatorUiState,
    onDismiss: () -> Unit,
    onPair: (String, String) -> Unit,
    onSyncNow: () -> Unit
) {
    val c = ThingsTheme.colors
    var code by remember { mutableStateOf("") }
    var addr by remember { mutableStateOf("") }
    val sync = state.syncStatus

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.cardSurface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = { SheetDragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("连接到 Mac", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = c.inkPrimary)
            Text(
                "在 Mac 端「设置 → 局域网同步」中查看 6 位配对码。同一 Wi-Fi 下会自动发现设备。",
                fontSize = 13.5.sp,
                lineHeight = 19.sp,
                color = c.inkSecondary
            )

            if (sync.pair == "wrong" || sync.pair == "locked") {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(c.dangerSoft)
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                ) {
                    Icon(Icons.Rounded.ErrorOutline, contentDescription = null, tint = c.danger, modifier = Modifier.size(18.dp))
                    Text(
                        text = if (sync.pair == "locked") "尝试次数过多，请 ${sync.retry} 秒后重试" else "配对码不匹配，请核对 Mac 端的 6 位配对码",
                        fontSize = 13.sp,
                        color = c.danger
                    )
                }
            } else if (sync.peers.isNotEmpty()) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(c.elevatedSurface)
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                ) {
                    sync.peers.forEach { peer ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(
                                Modifier
                                    .size(7.dp)
                                    .clip(CircleShape)
                                    .background(if (peer.ok) c.logbookGreen else c.todayGold)
                            )
                            Text(peer.addr, fontSize = 13.sp, color = c.inkPrimary, modifier = Modifier.weight(1f))
                            Text(
                                text = when {
                                    peer.ok -> "已同步"
                                    peer.pair == "wrong" -> "配对码错误"
                                    peer.pair == "locked" -> "已锁定 (${peer.retry}s)"
                                    else -> "连接中"
                                },
                                fontSize = 12.sp,
                                color = if (peer.ok) c.logbookGreen else c.inkSecondary
                            )
                        }
                    }
                }
            }

            CleanRoundedInput(
                value = code,
                onValueChange = { code = it.filter { ch -> ch.isDigit() }.take(6) },
                placeholder = "输入 6 位配对码",
                keyboardType = KeyboardType.Number
            )
            CleanRoundedInput(
                value = addr,
                onValueChange = { addr = it },
                placeholder = "Mac 地址（可选，如 192.168.1.5:8787）"
            )

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = onSyncNow,
                    shape = RoundedCornerShape(11.dp),
                    modifier = Modifier.weight(1f).height(46.dp)
                ) {
                    Text("立即同步", color = c.inkPrimary)
                }
                Button(
                    onClick = {
                        onPair(code, addr)
                        onDismiss()
                    },
                    enabled = code.length == 6,
                    shape = RoundedCornerShape(11.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = c.accentBlue, contentColor = Color.White),
                    modifier = Modifier.weight(1f).height(46.dp)
                ) {
                    Text("配对并同步", fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsSheet(
    state: NavigatorUiState,
    vm: NavigatorViewModel,
    onDismiss: () -> Unit,
    onOpenSync: () -> Unit
) {
    val c = ThingsTheme.colors
    val context = LocalContext.current
    var notifGranted by remember { mutableStateOf(ReminderScheduler.hasNotificationPermission(context)) }
    val notifLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        notifGranted = granted || ReminderScheduler.hasNotificationPermission(context)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.cardSurface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = { SheetDragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("设置", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = c.inkPrimary)

            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.elevatedSurface)
                    .padding(14.dp)
            ) {
                Text("外观主题", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkPrimary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    listOf("system" to "跟随系统", "light" to "浅色", "dark" to "深色").forEach { (id, label) ->
                        val selected = state.appearanceMode == id
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(9.dp))
                                .background(if (selected) c.accentBlueSoft else c.cardSurface)
                                .clickable { vm.setAppearanceMode(id) }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = label,
                                fontSize = 13.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                                color = if (selected) c.accentBlue else c.inkSecondary
                            )
                        }
                    }
                }
            }

            Column(
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.elevatedSurface)
                    .padding(14.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Rounded.Notifications,
                        contentDescription = null,
                        tint = if (notifGranted) c.logbookGreen else c.todayGold,
                        modifier = Modifier.size(22.dp)
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("到期通知提醒", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = c.inkPrimary)
                        Text(
                            if (notifGranted) "已开启 · 支持后台准时提醒" else "未授权 · 开启后任务到期会提醒",
                            fontSize = 12.5.sp,
                            color = c.inkSecondary
                        )
                    }
                    if (notifGranted) {
                        Text(
                            text = "测试",
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = c.accentBlue,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(c.accentBlueSoft)
                                .clickable { ReminderScheduler.sendTestNotification(context) }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        )
                    } else {
                        Text(
                            text = "开启",
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(c.accentBlue)
                                .clickable {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                        notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                    } else {
                                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                        }
                                        context.startActivity(intent)
                                    }
                                }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        )
                    }
                }

                ThingsDivider()
                Text("提前提醒", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = c.inkSecondary)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(0 to "准点", 15 to "提前 15m", 30 to "提前 30m", 60 to "提前 1h").forEach { (mins, label) ->
                        val active = state.leadReminderMinutes == mins
                        ThingsPill(
                            text = label,
                            textColor = if (active) c.accentBlue else c.inkSecondary,
                            backgroundColor = if (active) c.accentBlueSoft else c.cardSurface,
                            onClick = { vm.setLeadReminderMinutes(mins) }
                        )
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.elevatedSurface)
                    .clickable(onClick = onOpenSync)
                    .padding(14.dp)
            ) {
                Icon(Icons.Rounded.Sync, contentDescription = null, tint = c.accentBlue, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("局域网同步与配对", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = c.inkPrimary)
                    Text(
                        if (state.syncStatus.syncedAt > 0) "已连接 Mac 并保持同步" else "输入 Mac 6 位配对码即可同步",
                        fontSize = 12.5.sp,
                        color = c.inkSecondary
                    )
                }
                Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = c.inkTertiary)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = {
                        vm.exportMarkdown { md ->
                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            cm.setPrimaryClip(ClipData.newPlainText("TODO Markdown", md))
                            vm.showToastMessage("已复制 Markdown 到剪贴板")
                        }
                        onDismiss()
                    },
                    shape = RoundedCornerShape(11.dp),
                    modifier = Modifier.weight(1f).height(44.dp)
                ) {
                    Text("导出 Markdown", fontSize = 13.sp, color = c.inkPrimary)
                }
                OutlinedButton(
                    onClick = {
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val raw = cm.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
                        if (raw.isNotBlank()) {
                            vm.importJSON(raw)
                        } else {
                            vm.showToastMessage("剪贴板为空")
                        }
                        onDismiss()
                    },
                    shape = RoundedCornerShape(11.dp),
                    modifier = Modifier.weight(1f).height(44.dp)
                ) {
                    Text("导入剪贴板 JSON", fontSize = 13.sp, color = c.inkPrimary)
                }
            }

            Spacer(Modifier.height(14.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagManagerSheet(
    tags: List<TagItem>,
    onCreateTag: (String, String) -> Unit,
    onDeleteTag: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val c = ThingsTheme.colors
    var label by remember { mutableStateOf("") }
    var hue by remember { mutableStateOf("blue") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = c.cardSurface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        dragHandle = { SheetDragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("管理标签", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = c.inkPrimary)

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Box(modifier = Modifier.weight(1f)) {
                    CleanRoundedInput(
                        value = label,
                        onValueChange = { label = it },
                        placeholder = "新标签名称"
                    )
                }
                Button(
                    onClick = {
                        onCreateTag(label, hue)
                        label = ""
                    },
                    enabled = label.isNotBlank(),
                    shape = RoundedCornerShape(11.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = c.accentBlue, contentColor = Color.White),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp)
                ) {
                    Text("添加", fontWeight = FontWeight.SemiBold)
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                TagColors.allHues.forEach { h ->
                    val col = TagColors.colorFor(h)
                    val selected = hue == h
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(col.copy(alpha = if (selected) 0.22f else 0f))
                            .clickable { hue = h },
                        contentAlignment = Alignment.Center
                    ) {
                        Box(
                            modifier = Modifier
                                .size(if (selected) 16.dp else 13.dp)
                                .clip(CircleShape)
                                .background(col)
                        )
                    }
                }
            }

            if (tags.isNotEmpty()) {
                ThingsDivider()
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    tags.forEach { tag ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 6.dp)
                        ) {
                            Box(
                                Modifier
                                    .size(9.dp)
                                    .clip(CircleShape)
                                    .background(TagColors.colorFor(tag.hue))
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(
                                text = "#${tag.label}",
                                fontSize = 15.sp,
                                color = c.inkPrimary,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(
                                onClick = { onDeleteTag(tag.id) },
                                modifier = Modifier.size(32.dp)
                            ) {
                                Icon(
                                    Icons.Rounded.DeleteOutline,
                                    contentDescription = "删除标签",
                                    tint = c.inkTertiary,
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(14.dp))
        }
    }
}
