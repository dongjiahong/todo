package com.lele.navigator.ui

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lele.navigator.data.CoreRepository
import com.lele.navigator.model.DEFAULT_LIST_ID
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.SubtaskItem
import com.lele.navigator.model.SyncStatus
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
import com.lele.navigator.model.TaskListItem
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
    val lists: List<TaskListItem> = emptyList(),
    val syncStatus: SyncStatus = SyncStatus(),
    val searchQuery: String = "",
    val editingTaskId: String? = null,
    val undoMessage: UndoMessage? = null,
    val appearanceMode: String = "system", // "system" | "light" | "dark"
    val leadReminderMinutes: Int = 0
) {
    val liveTasks: List<TaskItem> get() = tasks.filter { !it.deleted }
    val liveTags: List<TagItem> get() = tags.filter { !it.deleted }.sortedBy { it.order }
    val liveLists: List<TaskListItem>
        get() {
            val active = lists.filter { !it.deleted }.sortedBy { it.order }
            return active.ifEmpty {
                listOf(TaskListItem(id = DEFAULT_LIST_ID, name = "提醒", color = "orange", icon = "list"))
            }
        }

    fun listFor(id: String?): TaskListItem {
        val target = if (id.isNullOrBlank()) DEFAULT_LIST_ID else id
        return liveLists.firstOrNull { it.id == target } ?: liveLists.first()
    }

    fun matchesSearch(t: TaskItem, query: String = searchQuery): Boolean {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return true
        if (t.title.lowercase().contains(q) ||
            t.notes.lowercase().contains(q) ||
            t.url.lowercase().contains(q) ||
            t.subtasks.any { it.title.lowercase().contains(q) }
        ) return true
        return t.tagIds.any { tid ->
            liveTags.firstOrNull { it.id == tid }?.label?.lowercase()?.contains(q) == true
        }
    }

    val todayTasks: List<TaskItem>
        get() = liveTasks.filter { !it.isDone && (DateUtils.isOverdue(it.dueAt) || DateUtils.isDueToday(it.dueAt)) }

    val scheduledTasks: List<TaskItem>
        get() = liveTasks.filter { !it.isDone && !it.dueAt.isNullOrBlank() }
            .sortedBy { it.dueAt }

    val allActiveTasks: List<TaskItem>
        get() = liveTasks.filter { !it.isDone }

    val flaggedTasks: List<TaskItem>
        get() = liveTasks.filter { !it.isDone && it.flagged }

    val completedTasks: List<TaskItem>
        get() = liveTasks.filter { it.isDone }
            .sortedByDescending { it.completedAt ?: 0L }

    fun activeTasksInList(listId: String): List<TaskItem> =
        liveTasks.filter { !it.isDone && it.effectiveListId == listId }

    fun completedTasksInList(listId: String): List<TaskItem> =
        liveTasks.filter { it.isDone && it.effectiveListId == listId }
            .sortedByDescending { it.completedAt ?: 0L }

    fun activeTasksForTag(tagId: String): List<TaskItem> =
        liveTasks.filter { !it.isDone && it.tagIds.contains(tagId) }

    fun allTaggedActiveTasks(): List<TaskItem> =
        liveTasks.filter { !it.isDone && it.tagIds.isNotEmpty() }
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
                it.copy(
                    tasks = board.tasks,
                    tags = board.tags,
                    lists = board.lists,
                    syncStatus = status
                )
            }
            ReminderScheduler.rescheduleAll(getApplication(), board.tasks, _state.value.leadReminderMinutes)
        }
    }

    private fun reloadInternal() {
        val board = repo.loadBoard()
        val status = repo.syncStatus()
        _state.update {
            it.copy(
                tasks = board.tasks,
                tags = board.tags,
                lists = board.lists,
                syncStatus = status
            )
        }
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

    fun setEditingTask(taskId: String?) {
        val prev = _state.value.editingTaskId
        if (prev != null && prev != taskId) {
            commitInlineEditIfEmpty(prev)
        }
        _state.update { it.copy(editingTaskId = taskId) }
    }

    fun commitInlineEditIfEmpty(taskId: String) {
        val existing = _state.value.liveTasks.firstOrNull { it.id == taskId } ?: return
        if (existing.title.isBlank() && existing.notes.isBlank() && existing.subtasks.isEmpty() && existing.attachments.isEmpty()) {
            viewModelScope.launch(Dispatchers.IO) {
                repo.deleteTask(taskId, true)
                reloadInternal()
            }
            _state.update { st ->
                st.copy(editingTaskId = if (st.editingTaskId == taskId) null else st.editingTaskId)
            }
        }
    }

    fun clearUndo() {
        _state.update { it.copy(undoMessage = null) }
    }

    fun showToastMessage(text: String) {
        _state.update { it.copy(undoMessage = UndoMessage(text, undo = null)) }
    }

    fun createInlineTask(
        listId: String? = null,
        title: String = "",
        dueAt: String? = null,
        flagged: Boolean = false,
        tagIds: List<String> = emptyList(),
        focusInline: Boolean = true
    ) {
        val targetList = if (!listId.isNullOrBlank()) listId else _state.value.liveLists.first().id
        val now = System.currentTimeMillis()
        val maxRank = _state.value.liveTasks.maxOfOrNull { it.rank } ?: 0.0
        val newId = "t_${UUID.randomUUID().toString().take(12)}"
        val task = TaskItem(
            id = newId,
            title = title.trim(),
            status = "todo",
            listId = targetList,
            flagged = flagged,
            priority = 0,
            tagIds = tagIds,
            dueAt = dueAt,
            rank = maxRank + 1000.0,
            createdAt = now,
            updatedAt = now,
            stamps = mapOf(
                "title" to now, "status" to now, "listId" to now,
                "flagged" to now, "priority" to now, "tagIds" to now,
                "dueAt" to now, "rank" to now, "deleted" to now
            )
        )
        _state.update { st ->
            st.copy(
                tasks = st.tasks + task,
                editingTaskId = if (focusInline) newId else st.editingTaskId
            )
        }
        viewModelScope.launch(Dispatchers.IO) {
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
                delay(320L)
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
        if (nextDone && _state.value.editingTaskId == taskId) {
            _state.update { it.copy(editingTaskId = null) }
        }
        viewModelScope.launch(Dispatchers.IO) {
            val saved = repo.completeTask(taskId, nextDone)
            val spawned = if (nextDone) saved.firstOrNull { it.id != taskId } else null
            reloadInternal()
            if (nextDone) {
                _state.update {
                    it.copy(
                        undoMessage = UndoMessage("已完成「${existing.title.ifBlank { "未命名提醒" }}」") {
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

    fun toggleFlag(taskId: String) {
        updateTask(taskId) { t, now ->
            t.copy(flagged = !t.flagged, stamps = t.stamps + ("flagged" to now))
        }
    }

    fun setPriority(taskId: String, priority: Int) {
        updateTask(taskId) { t, now ->
            t.copy(priority = priority.coerceIn(0, 3), stamps = t.stamps + ("priority" to now))
        }
    }

    fun moveTaskToList(taskId: String, listId: String) {
        updateTask(taskId) { t, now ->
            t.copy(listId = listId, stamps = t.stamps + ("listId" to now))
        }
    }

    fun clearCompleted(listId: String?) {
        viewModelScope.launch(Dispatchers.IO) {
            val cleared = repo.clearCompleted(listId)
            if (cleared.isEmpty()) return@launch
            reloadInternal()
            val ids = cleared.map { it.id }
            _state.update {
                it.copy(
                    undoMessage = UndoMessage("已清除 ${cleared.size} 项已完成提醒") {
                        viewModelScope.launch(Dispatchers.IO) {
                            ids.forEach { id -> repo.deleteTask(id, false) }
                            reloadInternal()
                        }
                    }
                )
            }
        }
    }

    fun deleteTask(taskId: String) {
        val existing = _state.value.liveTasks.firstOrNull { it.id == taskId } ?: return
        if (_state.value.editingTaskId == taskId) {
            _state.update { it.copy(editingTaskId = null) }
        }
        viewModelScope.launch(Dispatchers.IO) {
            repo.deleteTask(taskId, true)
            reloadInternal()
            _state.update {
                it.copy(
                    undoMessage = UndoMessage("已删除「${existing.title.ifBlank { "未命名提醒" }}」") {
                        viewModelScope.launch(Dispatchers.IO) {
                            repo.deleteTask(taskId, false)
                            reloadInternal()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Lists

    fun createList(name: String, color: String, icon: String) {
        val clean = name.trim()
        if (clean.isEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val list = TaskListItem(
                id = "list_${UUID.randomUUID().toString().take(8)}",
                name = clean,
                color = color,
                icon = icon,
                order = (_state.value.liveLists.maxOfOrNull { it.order } ?: -1) + 1,
                updatedAt = System.currentTimeMillis()
            )
            repo.saveList(list)
            reloadInternal()
        }
    }

    fun updateList(list: TaskListItem) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.saveList(list.copy(updatedAt = System.currentTimeMillis()))
            reloadInternal()
        }
    }

    fun deleteList(listId: String) {
        if (_state.value.liveLists.size <= 1) return
        viewModelScope.launch(Dispatchers.IO) {
            repo.deleteList(listId)
            reloadInternal()
        }
    }

    // MARK: - Subtasks

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

    // MARK: - Sync / Tags / Export / Attachments

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
