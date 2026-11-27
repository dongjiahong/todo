package com.lele.navigator.model

import androidx.compose.ui.graphics.Color
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Serializable
data class SubtaskItem(
    val id: String,
    val title: String,
    val done: Boolean = false,
    val order: Int = 0
)

@Serializable
data class TaskItem(
    val id: String,
    val title: String = "",
    val notes: String = "",
    val status: String = "todo", // "todo" | "doing" | "done"
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
    val isDoing: Boolean get() = status == "doing"
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
    val seeded: Boolean = false
)

@Serializable
data class PeerStatus(
    val addr: String,
    val ok: Boolean = false,
    val at: Long = 0L,
    val typed: Boolean = false,
    val pair: String = "ok",
    val retry: Long = 0L
)

@Serializable
data class SyncStatus(
    val listening: Boolean = false,
    val address: String = "",
    val pairCode: String? = null,
    val peers: List<PeerStatus> = emptyList(),
    val unreachable: Boolean = false,
    val syncedAt: Long = 0L,
    val pair: String = "need",
    val retry: Long = 0L
)

@Serializable
data class SyncEvent(
    val type: String,
    val tasks: List<TaskItem>? = null,
    val tags: List<TagItem>? = null,
    val status: SyncStatus? = null,
    val at: Long? = null
)

object TagColors {
    fun colorFor(hue: String): Color = when (hue) {
        "green" -> Color(0xFF28A76E)
        "purple" -> Color(0xFF8B5CF6)
        "amber" -> Color(0xFFE59500)
        "red" -> Color(0xFFE5484D)
        else -> Color(0xFF3178F6)
    }

    val allHues = listOf("blue", "green", "purple", "amber", "red")
}

object DateUtils {
    private val dueFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")

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
        if (late) return "已逾期 · $day $time" to 2
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

    fun todaySubtitle(): String {
        val today = LocalDate.now()
        val wd = when (today.dayOfWeek.value) {
            1 -> "周一"
            2 -> "周二"
            3 -> "周三"
            4 -> "周四"
            5 -> "周五"
            6 -> "周六"
            else -> "周日"
        }
        return "${today.monthValue}月${today.dayOfMonth}日 · $wd"
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
