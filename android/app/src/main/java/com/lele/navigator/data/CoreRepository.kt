package com.lele.navigator.data

import android.content.Context
import com.lele.navigator.model.BoardState
import com.lele.navigator.model.SyncEvent
import com.lele.navigator.model.SyncStatus
import com.lele.navigator.model.TagItem
import com.lele.navigator.model.TaskItem
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
        // Phone acts as active LAN watcher/client; Mac serves on port 8787.
        val raw = runCatching { engine.startSync(false, 8787) }.getOrDefault("{}")
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

    fun saveTag(tag: TagItem) {
        val raw = json.encodeToString(tag)
        runCatching { engine.saveTagJSON(raw) }
    }

    fun deleteTag(id: String) {
        runCatching { engine.deleteTag(id) }
    }

    fun setPeerCode(code: String) {
        runCatching { engine.setPeerCode(code) }
    }

    fun addPeerAddress(addr: String) {
        runCatching { engine.addPeerAddress(addr) }
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
