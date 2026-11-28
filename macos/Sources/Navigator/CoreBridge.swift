import Foundation
import CNavigatorCore

private final class CallbackRegistry {
    static let shared = CallbackRegistry()
    var handler: ((String) -> Void)?
}

private let cSyncCallback: nav_event_cb = { rawPtr in
    guard let rawPtr else { return }
    let json = String(cString: rawPtr)
    DispatchQueue.main.async {
        CallbackRegistry.shared.handler?(json)
    }
}

/// Thin Swift facade over the compiled Go Core C-ABI (`libnavigator_core.a`).
final class CoreBridge {
    static let shared = CoreBridge()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private func takeString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "" }
        defer { NavFreeString(ptr) }
        return String(cString: ptr)
    }

    func open(dataDir: String, onEvent: @escaping (SyncEvent) -> Void) {
        CallbackRegistry.shared.handler = { [weak self] json in
            guard let self, let data = json.data(using: .utf8),
                  let ev = try? self.decoder.decode(SyncEvent.self, from: data) else { return }
            onEvent(ev)
        }
        NavSetEventCallback(cSyncCallback)
        _ = dataDir.withCString { takeString(NavOpen($0)) }
    }

    func loadBoard() -> BoardState {
        let raw = takeString(NavLoadJSON())
        guard let data = raw.data(using: .utf8),
              let state = try? decoder.decode(BoardState.self, from: data) else {
            return BoardState(tasks: [], tags: [], lists: [], seeded: false)
        }
        return state
    }

    @discardableResult
    func saveTask(_ task: TaskItem) -> TaskItem {
        guard let data = try? encoder.encode(task),
              let json = String(data: data, encoding: .utf8) else { return task }
        let out = json.withCString { takeString(NavSaveTaskJSON($0)) }
        if let outData = out.data(using: .utf8),
           let saved = try? decoder.decode(TaskItem.self, from: outData) {
            return saved
        }
        return task
    }

    func completeTask(id: String, done: Bool) -> [TaskItem] {
        let out = id.withCString { takeString(NavCompleteTask($0, done ? 1 : 0)) }
        if let data = out.data(using: .utf8),
           let list = try? decoder.decode([TaskItem].self, from: data) {
            return list
        }
        return []
    }

    func deleteTask(id: String, deleted: Bool) {
        _ = id.withCString { takeString(NavDeleteTask($0, deleted ? 1 : 0)) }
    }

    @discardableResult
    func clearCompleted(listID: String?) -> [TaskItem] {
        let target = listID ?? ""
        let out = target.withCString { takeString(NavClearCompleted($0)) }
        if let data = out.data(using: .utf8),
           let list = try? decoder.decode([TaskItem].self, from: data) {
            return list
        }
        return []
    }

    @discardableResult
    func saveList(_ list: TaskListItem) -> TaskListItem {
        guard let data = try? encoder.encode(list),
              let json = String(data: data, encoding: .utf8) else { return list }
        let out = json.withCString { takeString(NavSaveListJSON($0)) }
        if let outData = out.data(using: .utf8),
           let saved = try? decoder.decode(TaskListItem.self, from: outData) {
            return saved
        }
        return list
    }

    func deleteList(id: String) {
        _ = id.withCString { takeString(NavDeleteList($0)) }
    }

    @discardableResult
    func saveTag(_ tag: TagItem) -> TagItem {
        guard let data = try? encoder.encode(tag),
              let json = String(data: data, encoding: .utf8) else { return tag }
        let out = json.withCString { takeString(NavSaveTagJSON($0)) }
        if let outData = out.data(using: .utf8),
           let saved = try? decoder.decode(TagItem.self, from: outData) {
            return saved
        }
        return tag
    }

    func deleteTag(id: String) {
        _ = id.withCString { takeString(NavDeleteTag($0)) }
    }

    func saveAsset(data: Data, ext: String) -> String {
        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return "" }
            return ext.withCString { extPtr in
                takeString(NavSaveAsset(base, Int32(data.count), extPtr))
            }
        }
    }

    func assetPath(name: String) -> String {
        name.withCString { takeString(NavAssetPath($0)) }
    }

    func startSync(serve: Bool = true, port: Int = 8787) -> SyncStatus {
        let raw = takeString(NavStartSync(serve ? 1 : 0, Int32(port)))
        if let data = raw.data(using: .utf8),
           let status = try? decoder.decode(SyncStatus.self, from: data) {
            return status
        }
        return SyncStatus()
    }

    func hostPairCode() -> String {
        takeString(NavHostPairCode())
    }

    func regeneratePairCode() -> String {
        takeString(NavRegeneratePairCode())
    }

    func setPeerCode(_ code: String) {
        _ = code.withCString { takeString(NavSetPeerCode($0)) }
    }

    func addPeerAddress(_ addr: String) {
        addr.withCString { NavAddPeerAddress($0) }
    }

    func syncNow() {
        NavSyncNow()
    }

    func syncStatus() -> SyncStatus {
        let raw = takeString(NavSyncStatusJSON())
        if let data = raw.data(using: .utf8),
           let status = try? decoder.decode(SyncStatus.self, from: data) {
            return status
        }
        return SyncStatus()
    }

    func exportMarkdown() -> String {
        takeString(NavExportMarkdown())
    }

    func importJSON(_ raw: String) {
        _ = raw.withCString { takeString(NavImportJSON($0)) }
    }
}
