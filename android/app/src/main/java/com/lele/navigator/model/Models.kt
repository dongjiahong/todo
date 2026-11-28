package com.lele.navigator.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

const val DEFAULT_LIST_ID = "list_reminders"

@Serializable
data class SubtaskItem(
    val id: String,
    val title: String,
    val done: Boolean = false,
    val order: Int = 0
)

@Serializable
data class TaskListItem(
    val id: String,
    val name: String,
    val color: String = "blue",
    val icon: String = "list",
    val order: Int = 0,
    val updatedAt: Long = 0L,
    val deleted: Boolean = false
)

@Serializable
data class TaskItem(
    val id: String,
    val title: String = "",
    val notes: String = "",
    val status: String = "todo", // "todo" | "done"
    val listId: String = DEFAULT_LIST_ID,
    val parentId: String? = null,
    val flagged: Boolean = false,
    val priority: Int = 0, // 0=none, 1=low, 2=medium, 3=high
    val url: String = "",
    val subtasks: List<SubtaskItem> = emptyList(),
    val tagIds: List<String> = emptyList(),
    val dueAt: String? = null,
    val repeatRule: String? = null,
    val attachments: List<String> = emptyList(),
    val rank: Double = 0.0,
    val completedAt: Long? = null,
    val createdAt: Long = 0L,
    val updatedAt: Long = 0L,
    val deleted: Boolean = false,
    val stamps: Map<String, Long> = emptyMap()
) {
    val isDone: Boolean get() = status == "done"
    val effectiveListId: String get() = listId.ifBlank { DEFAULT_LIST_ID }
    val priorityPrefix: String
        get() = when (priority) {
            1 -> "!"
            2 -> "!!"
            3 -> "!!!"
            else -> ""
        }
    val checklistDone: Int get() = subtasks.count { it.done }
    val checklistTotal: Int get() = subtasks.size
}

@Serializable
data class TagItem(
    val id: String,
    val label: String,
    val hue: String = "blue",
    val order: Int = 0,
    val updatedAt: Long = 0L,
    val deleted: Boolean = false
)

@Serializable
data class BoardState(
    val tasks: List<TaskItem> = emptyList(),
    val tags: List<TagItem> = emptyList(),
    val lists: List<TaskListItem> = emptyList(),
    val seeded: Boolean = false
)

@Serializable
data class DiscoveredPeer(
    val deviceId: String,
    val deviceName: String = "",
    val ip: String = "",
    val httpPort: Int = 8787,
    val lastSeenMs: Long = 0L
)

@Serializable
data class PairedPeer(
    val deviceId: String,
    val deviceName: String = "",
    val lastSyncAt: Long = 0L,
    val lastIp: String = "",
    val lastPort: Int = 8787,
    val online: Boolean = false
)

@Serializable
data class SyncStatus(
    val running: Boolean = false,
    val deviceId: String = "",
    val deviceName: String = "Android 手机",
    val address: String = "",
    val httpPort: Int = 8787,
    val activePairingCode: String? = null,
    val pairingExpiresAt: Long? = null,
    val pairedPeers: List<PairedPeer> = emptyList(),
    val discoveredPeers: List<DiscoveredPeer> = emptyList(),
    val syncedAt: Long = 0L,
    val lastError: String? = null
)

@Serializable
data class SyncEvent(
    val type: String,
    val tasks: List<TaskItem>? = null,
    val tags: List<TagItem>? = null,
    val lists: List<TaskListItem>? = null,
    val status: SyncStatus? = null,
    val at: Long? = null
)

object ListStyle {
    val allColors = listOf("blue", "orange", "green", "red", "purple", "pink", "yellow", "gray")
    val allIcons = listOf("list", "work", "study", "life", "home", "cart", "star", "book", "code", "heart")

    fun colorFor(key: String): Color = when (key) {
        "orange" -> Color(0xFFFF9500)
        "green" -> Color(0xFF34C759)
        "red" -> Color(0xFFFF3B30)
        "purple" -> Color(0xFFAF52DE)
        "pink" -> Color(0xFFFF2D55)
        "yellow" -> Color(0xFFF2AF00)
        "gray" -> Color(0xFF8E8E93)
        else -> Color(0xFF007AFF)
    }

    fun iconFor(key: String): ImageVector = when (key) {
        "work" -> Icons.Rounded.Computer
        "study" -> Icons.Rounded.School
        "life" -> Icons.Rounded.SportsEsports
        "home" -> Icons.Rounded.Home
        "cart" -> Icons.Rounded.ShoppingCart
        "star" -> Icons.Rounded.Star
        "book" -> Icons.Rounded.MenuBook
        "code" -> Icons.Rounded.Code
        "heart" -> Icons.Rounded.Favorite
        else -> Icons.Rounded.FormatListBulleted
    }
}

object TagColors {
    fun colorFor(hue: String): Color = when (hue) {
        "green" -> Color(0xFF34C759)
        "purple" -> Color(0xFFAF52DE)
        "amber" -> Color(0xFFFF9500)
        "red" -> Color(0xFFFF3B30)
        else -> Color(0xFF007AFF)
    }

    val allHues = listOf("blue", "green", "purple", "amber", "red")
}

object DateUtils {
    private val dueFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")

    fun todayDayNumber(): Int = LocalDate.now().dayOfMonth

    fun parseDue(dueAt: String?): LocalDateTime? {
        if (dueAt.isNullOrBlank()) return null
        return runCatching { LocalDateTime.parse(dueAt, dueFmt) }.getOrNull()
    }

    fun presetDue(daysOffset: Long, hour: Int, minute: Int = 0): String {
        val dt = LocalDate.now().plusDays(daysOffset).atTime(hour, minute)
        return dt.format(dueFmt)
    }

    fun isOverdue(dueAt: String?): Boolean {
        val dt = parseDue(dueAt) ?: return false
        return dt.isBefore(LocalDateTime.now())
    }

    fun isDueToday(dueAt: String?): Boolean {
        val dt = parseDue(dueAt) ?: return false
        return dt.toLocalDate() == LocalDate.now()
    }

    fun isCompletedToday(completedAt: Long?): Boolean {
        if (completedAt == null || completedAt <= 0) return false
        val date = Instant.ofEpochMilli(completedAt).atZone(ZoneId.systemDefault()).toLocalDate()
        return date == LocalDate.now()
    }

    fun dueLabel(dueAt: String?, settled: Boolean = false): Pair<String, Int>? {
        val dt = parseDue(dueAt) ?: return null
        val today = LocalDate.now()
        val d = dt.toLocalDate()
        val time = String.format("%02d:%02d", dt.hour, dt.minute)
        val day = when (d) {
            today -> "今天"
            today.plusDays(1) -> "明天"
            today.minusDays(1) -> "昨天"
            else -> if (d.year == today.year) "${d.monthValue}月${d.dayOfMonth}日" else "${d.year}年${d.monthValue}月${d.dayOfMonth}日"
        }
        val late = !settled && dt.isBefore(LocalDateTime.now())
        if (late) return "$day $time" to 2
        if (!settled && d == today) return "今天 $time" to 1
        return "$day $time" to 0
    }

    fun logbookDay(completedAt: Long?): String {
        if (completedAt == null || completedAt <= 0) return "更早"
        val d = Instant.ofEpochMilli(completedAt).atZone(ZoneId.systemDefault()).toLocalDate()
        val today = LocalDate.now()
        return when (d) {
            today -> "今天"
            today.minusDays(1) -> "昨天"
            else -> "${d.monthValue}月${d.dayOfMonth}日"
        }
    }

    fun upcomingGroupLabel(dueAt: String?): String {
        val dt = parseDue(dueAt) ?: return "未定日期"
        val d = dt.toLocalDate()
        val today = LocalDate.now()
        val wd = when (d.dayOfWeek.value) {
            1 -> "周一"
            2 -> "周二"
            3 -> "周三"
            4 -> "周四"
            5 -> "周五"
            6 -> "周六"
            else -> "周日"
        }
        return when {
            d.isBefore(today) -> "已逾期"
            d == today -> "今天 · ${d.monthValue}月${d.dayOfMonth}日"
            d == today.plusDays(1) -> "明天 · ${d.monthValue}月${d.dayOfMonth}日"
            d.isBefore(today.plusDays(7)) -> "$wd · ${d.monthValue}月${d.dayOfMonth}日"
            d.year == today.year -> "${d.monthValue}月${d.dayOfMonth}日 · $wd"
            else -> "${d.year}年${d.monthValue}月${d.dayOfMonth}日"
        }
    }
}
