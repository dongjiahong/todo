package com.lele.navigator.data

import android.content.Context
import com.lele.navigator.model.BoardState
import com.lele.navigator.model.SyncEvent
import com.lele.navigator.model.SyncStatus
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
import com.lele.navigator.model.TaskListItem
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import mobile.EventListener
import mobile.Mobile
import mobile.NavigatorMobile

/**
 * Thin Kotlin repository wrapping the Go Core AAR (`mobile.NavigatorMobile`).
 */
class CoreRepository(context: Context) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val engine: NavigatorMobile = Mobile.open(context.filesDir.absolutePath)

    fun start(onEvent: (SyncEvent) -> Unit): SyncStatus {
        engine.setListener(object : EventListener {
            override fun onEvent(eventJSON: String) {
                runCatching { json.decodeFromString<SyncEvent>(eventJSON) }
                    .onSuccess(onEvent)
            }
        })
        // Symmetric P2P: Android also runs HTTP sync server + UDP beacon on LAN.
        val raw = runCatching { engine.startSync(true, 8787) }.getOrDefault("{}")
        return runCatching { json.decodeFromString<SyncStatus>(raw) }.getOrDefault(SyncStatus())
    }

    fun loadBoard(): BoardState {
        val raw = runCatching { engine.loadJSON() }.getOrDefault("{}")
        return runCatching { json.decodeFromString<BoardState>(raw) }.getOrDefault(BoardState())
    }

    fun saveTask(task: TaskItem) {
        val raw = json.encodeToString(task)
        runCatching { engine.saveTaskJSON(raw) }
    }

    fun completeTask(id: String, done: Boolean): List<TaskItem> {
        val raw = runCatching { engine.completeTask(id, done) }.getOrDefault("[]")
        return runCatching { json.decodeFromString<List<TaskItem>>(raw) }.getOrDefault(emptyList())
    }

    fun deleteTask(id: String, deleted: Boolean) {
        runCatching { engine.deleteTask(id, deleted) }
    }

    fun clearCompleted(listId: String?): List<TaskItem> {
        val raw = runCatching { engine.clearCompleted(listId ?: "") }.getOrDefault("[]")
        return runCatching { json.decodeFromString<List<TaskItem>>(raw) }.getOrDefault(emptyList())
    }

    fun saveList(list: TaskListItem) {
        val raw = json.encodeToString(list)
        runCatching { engine.saveListJSON(raw) }
    }

    fun deleteList(id: String) {
        runCatching { engine.deleteList(id) }
    }

    fun saveTag(tag: TagItem) {
        val raw = json.encodeToString(tag)
        runCatching { engine.saveTagJSON(raw) }
    }

    fun deleteTag(id: String) {
        runCatching { engine.deleteTag(id) }
    }

    fun generatePairingCode(): String {
        return runCatching { engine.generatePairingCode() }.getOrDefault("")
    }

    fun pairWithPeer(ip: String, port: Int, code: String): Result<com.lele.navigator.model.PairedPeer> {
        return runCatching {
            val raw = engine.pairWithPeer(ip, port.toLong(), code)
            json.decodeFromString<com.lele.navigator.model.PairedPeer>(raw)
        }
    }

    fun deletePairedPeer(deviceId: String) {
        runCatching { engine.deletePairedPeer(deviceId) }
    }

    fun syncWithPeer(deviceId: String): String? {
        return try {
            engine.syncWithPeer(deviceId)
            null
        } catch (e: Exception) {
            e.message ?: "同步失败"
        }
    }

    fun syncNow() {
        runCatching { engine.syncNow() }
    }

    fun syncStatus(): SyncStatus {
        val raw = runCatching { engine.syncStatusJSON() }.getOrDefault("{}")
        return runCatching { json.decodeFromString<SyncStatus>(raw) }.getOrDefault(SyncStatus())
    }

    fun saveAsset(bytes: ByteArray, ext: String = "jpg"): String {
        return runCatching { engine.saveAsset(bytes, ext) }.getOrDefault("")
    }

    fun assetPath(name: String): String {
        return runCatching { engine.assetPath(name) }.getOrDefault("")
    }

    fun exportMarkdown(): String {
        return runCatching { engine.exportMarkdown() }.getOrDefault("")
    }

    fun importJSON(raw: String): Boolean {
        return runCatching { engine.importJSON(raw) }.isSuccess
    }
}
