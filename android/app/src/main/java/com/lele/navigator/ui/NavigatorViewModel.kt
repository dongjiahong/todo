package com.lele.navigator.ui

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lele.navigator.data.CoreRepository
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.SubtaskItem
import com.lele.navigator.model.SyncStatus
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
import com.lele.navigator.notify.ReminderScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

data class UndoMessage(
    val text: String,
    val undo: (() -> Unit)? = null
)

data class NavigatorUiState(
    val tasks: List<TaskItem> = emptyList(),
    val tags: List<TagItem> = emptyList(),
    val syncStatus: SyncStatus = SyncStatus(),
    val searchQuery: String = "",
    val selectedTagId: String? = null,
    val undoMessage: UndoMessage? = null,
    val appearanceMode: String = "system", // "system" | "light" | "dark"
    val leadReminderMinutes: Int = 0
) {
    val liveTasks: List<TaskItem> get() = tasks.filter { !it.deleted }
    val liveTags: List<TagItem> get() = tags.filter { !it.deleted }.sortedBy { it.order }

    private fun matches(t: TaskItem): Boolean {
        if (selectedTagId != null && !t.tagIds.contains(selectedTagId)) return false
        val q = searchQuery.trim().lowercase()
        if (q.isEmpty()) return true
        if (t.title.lowercase().contains(q) ||
            t.notes.lowercase().contains(q) ||
            t.subtasks.any { it.title.lowercase().contains(q) }
        ) return true
        return t.tagIds.any { tid ->
            liveTags.firstOrNull { it.id == tid }?.label?.lowercase()?.contains(q) == true
        }
    }

    val overdueTasks: List<TaskItem>
        get() = liveTasks.filter { !it.isDone && DateUtils.isOverdue(it.dueAt) && matches(it) }

    val todayActiveTasks: List<TaskItem>
        get() = liveTasks.filter {
            !it.isDone && !DateUtils.isOverdue(it.dueAt) &&
                (DateUtils.isDueToday(it.dueAt) || it.isDoing) && matches(it)
        }

    val todayCompletedTasks: List<TaskItem>
        get() = liveTasks.filter { it.isDone && DateUtils.isCompletedToday(it.completedAt) && matches(it) }

    val doingTasks: List<TaskItem>
        get() = liveTasks.filter { it.isDoing && matches(it) }

    val todoTasks: List<TaskItem>
        get() = liveTasks.filter { it.status == "todo" && matches(it) }

    val upcomingTasks: List<TaskItem>
        get() = liveTasks.filter { !it.isDone && !it.dueAt.isNullOrBlank() && matches(it) }
            .sortedBy { it.dueAt }

    val logbookTasks: List<TaskItem>
        get() = liveTasks.filter { it.isDone && matches(it) }
            .sortedByDescending { it.completedAt ?: 0L }
}

class NavigatorViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("navigator_prefs", Context.MODE_PRIVATE)
    private val repo = CoreRepository(app.applicationContext)

    private val _state = MutableStateFlow(
        NavigatorUiState(
            appearanceMode = prefs.getString("appearance_mode", "system") ?: "system",
            leadReminderMinutes = prefs.getInt("lead_reminder_minutes", 0)
        )
    )
    val state: StateFlow<NavigatorUiState> = _state.asStateFlow()
    private val pendingSaveJobs = mutableMapOf<String, Job>()

    init {
        viewModelScope.launch(Dispatchers.IO) {
            val board = repo.loadBoard()
            val status = repo.start { event ->
                viewModelScope.launch(Dispatchers.IO) {
                    if (event.type == "status" && event.status != null) {
                        _state.update { it.copy(syncStatus = event.status) }
                    } else if (event.type == "rows") {
                        reloadInternal()
                    }
                }
            }
            _state.update {
                it.copy(tasks = board.tasks, tags = board.tags, syncStatus = status)
            }
            ReminderScheduler.rescheduleAll(getApplication(), board.tasks, _state.value.leadReminderMinutes)
        }
    }

    private fun reloadInternal() {
        val board = repo.loadBoard()
        val status = repo.syncStatus()
        _state.update { it.copy(tasks = board.tasks, tags = board.tags, syncStatus = status) }
        ReminderScheduler.rescheduleAll(getApplication(), board.tasks, _state.value.leadReminderMinutes)
    }

    fun setAppearanceMode(mode: String) {
        prefs.edit().putString("appearance_mode", mode).apply()
        _state.update { it.copy(appearanceMode = mode) }
    }

    fun setLeadReminderMinutes(minutes: Int) {
        prefs.edit().putInt("lead_reminder_minutes", minutes).apply()
        _state.update { it.copy(leadReminderMinutes = minutes) }
        viewModelScope.launch(Dispatchers.IO) {
            ReminderScheduler.rescheduleAll(getApplication(), _state.value.tasks, minutes)
        }
    }

    fun setSearch(query: String) {
        _state.update { it.copy(searchQuery = query) }
    }

    fun setTagFilter(tagId: String?) {
        _state.update { it.copy(selectedTagId = tagId) }
    }

    fun clearUndo() {
        _state.update { it.copy(undoMessage = null) }
    }

    fun showToastMessage(text: String) {
        _state.update { it.copy(undoMessage = UndoMessage(text, undo = null)) }
    }

    fun createTask(
        title: String,
        status: String = "todo",
        tagIds: List<String> = emptyList(),
        dueAt: String? = null
    ) {
        val clean = title.trim()
        if (clean.isEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val now = System.currentTimeMillis()
            val minRank = _state.value.liveTasks.minOfOrNull { it.rank } ?: 1000.0
            val task = TaskItem(
                id = "t_${UUID.randomUUID().toString().take(12)}",
                title = clean,
                status = status,
                tagIds = tagIds,
                dueAt = dueAt,
                rank = minRank - 100.0,
                createdAt = now,
                updatedAt = now,
                stamps = mapOf(
                    "title" to now, "status" to now, "tagIds" to now,
                    "dueAt" to now, "rank" to now, "deleted" to now
                )
            )
            repo.saveTask(task)
            reloadInternal()
        }
    }

    fun updateTask(
        taskId: String,
        debounced: Boolean = false,
        mutate: (TaskItem, Long) -> TaskItem
    ) {
        val existing = _state.value.liveTasks.firstOrNull { it.id == taskId } ?: return
        val now = System.currentTimeMillis()
        val updated = mutate(existing, now).copy(updatedAt = now)
        val affectsReminder =
            existing.dueAt != updated.dueAt ||
                existing.status != updated.status ||
                existing.deleted != updated.deleted

        var snapshot: List<TaskItem> = emptyList()
        _state.update { st ->
            val nextTasks = st.tasks.map { if (it.id == taskId) updated else it }
            snapshot = nextTasks
            st.copy(tasks = nextTasks)
        }

        pendingSaveJobs.remove(taskId)?.cancel()
        if (debounced) {
            pendingSaveJobs[taskId] = viewModelScope.launch(Dispatchers.IO) {
                delay(350L)
                repo.saveTask(updated)
                if (affectsReminder) {
                    ReminderScheduler.rescheduleAll(getApplication(), snapshot, _state.value.leadReminderMinutes)
                }
            }
        } else {
            viewModelScope.launch(Dispatchers.IO) {
                repo.saveTask(updated)
                if (affectsReminder) {
                    ReminderScheduler.rescheduleAll(getApplication(), snapshot, _state.value.leadReminderMinutes)
                }
            }
        }
    }

    fun toggleComplete(taskId: String) {
        val existing = _state.value.liveTasks.firstOrNull { it.id == taskId } ?: return
        val nextDone = !existing.isDone
        viewModelScope.launch(Dispatchers.IO) {
            val saved = repo.completeTask(taskId, nextDone)
            val spawned = if (nextDone) saved.firstOrNull { it.id != taskId } else null
            reloadInternal()
            if (nextDone) {
                _state.update {
                    it.copy(
                        undoMessage = UndoMessage("已完成「${existing.title.ifBlank { "未命名任务" }}」") {
                            viewModelScope.launch(Dispatchers.IO) {
                                repo.completeTask(taskId, false)
                                if (spawned != null) {
                                    repo.deleteTask(spawned.id, true)
                                }
                                reloadInternal()
                            }
                        }
                    )
                }
            }
        }
    }

    fun toggleDoing(taskId: String) {
        updateTask(taskId) { t, now ->
            val next = if (t.isDoing) "todo" else "doing"
            t.copy(
                status = next,
                completedAt = null,
                stamps = t.stamps + ("status" to now) + ("completedAt" to now)
            )
        }
    }

    fun deleteTask(taskId: String) {
        val existing = _state.value.liveTasks.firstOrNull { it.id == taskId } ?: return
        viewModelScope.launch(Dispatchers.IO) {
            repo.deleteTask(taskId, true)
            reloadInternal()
            _state.update {
                it.copy(
                    undoMessage = UndoMessage("已删除「${existing.title.ifBlank { "未命名任务" }}」") {
                        viewModelScope.launch(Dispatchers.IO) {
                            repo.deleteTask(taskId, false)
                            reloadInternal()
                        }
                    }
                )
            }
        }
    }

    fun addSubtask(taskId: String, title: String) {
        val clean = title.trim()
        if (clean.isEmpty()) return
        updateTask(taskId) { t, now ->
            val nextOrder = (t.subtasks.maxOfOrNull { it.order } ?: -1) + 1
            val item = SubtaskItem(
                id = "s_${UUID.randomUUID().toString().take(8)}",
                title = clean,
                done = false,
                order = nextOrder
            )
            t.copy(subtasks = t.subtasks + item, stamps = t.stamps + ("subtasks" to now))
        }
    }

    fun toggleSubtask(taskId: String, subtaskId: String) {
        updateTask(taskId) { t, now ->
            t.copy(
                subtasks = t.subtasks.map { if (it.id == subtaskId) it.copy(done = !it.done) else it },
                stamps = t.stamps + ("subtasks" to now)
            )
        }
    }

    fun updateSubtaskTitle(taskId: String, subtaskId: String, title: String) {
        updateTask(taskId, debounced = true) { t, now ->
            t.copy(
                subtasks = t.subtasks.map { if (it.id == subtaskId) it.copy(title = title) else it },
                stamps = t.stamps + ("subtasks" to now)
            )
        }
    }

    fun deleteSubtask(taskId: String, subtaskId: String) {
        updateTask(taskId) { t, now ->
            t.copy(
                subtasks = t.subtasks.filterNot { it.id == subtaskId },
                stamps = t.stamps + ("subtasks" to now)
            )
        }
    }

    fun pairWithMac(code: String, manualAddr: String) {
        viewModelScope.launch(Dispatchers.IO) {
            if (manualAddr.isNotBlank()) {
                repo.addPeerAddress(manualAddr.trim())
            }
            repo.setPeerCode(code.filter { it.isDigit() }.take(6))
            repo.syncNow()
            reloadInternal()
        }
    }

    fun syncNow() {
        viewModelScope.launch(Dispatchers.IO) {
            repo.syncNow()
            reloadInternal()
        }
    }

    fun exportMarkdown(onResult: (String) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            val md = repo.exportMarkdown()
            onResult(md)
        }
    }

    fun importJSON(raw: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val ok = repo.importJSON(raw)
            if (ok) {
                reloadInternal()
                showToastMessage("已合并剪贴板中的 JSON 数据")
            } else {
                showToastMessage("JSON 格式无效，未导入")
            }
        }
    }

    fun createTag(label: String, hue: String) {
        val clean = label.trim()
        if (clean.isEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val tag = TagItem(
                id = "tag_${UUID.randomUUID().toString().take(8)}",
                label = clean,
                hue = hue,
                order = (_state.value.liveTags.maxOfOrNull { it.order } ?: -1) + 1,
                updatedAt = System.currentTimeMillis()
            )
            repo.saveTag(tag)
            reloadInternal()
        }
    }

    fun deleteTag(tagId: String) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.deleteTag(tagId)
            reloadInternal()
        }
    }

    fun attachImage(taskId: String, bytes: ByteArray, ext: String = "jpg") {
        viewModelScope.launch(Dispatchers.IO) {
            val name = repo.saveAsset(bytes, ext)
            if (name.isNotBlank()) {
                updateTask(taskId) { t, now ->
                    if (t.attachments.contains(name) || t.attachments.size >= 6) t
                    else t.copy(
                        attachments = t.attachments + name,
                        stamps = t.stamps + ("attachments" to now)
                    )
                }
            }
        }
    }

    fun removeAttachment(taskId: String, name: String) {
        updateTask(taskId) { t, now ->
            t.copy(
                attachments = t.attachments.filterNot { it == name },
                stamps = t.stamps + ("attachments" to now)
            )
        }
    }

    fun assetPath(name: String): String = repo.assetPath(name)
}
