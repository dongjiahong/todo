import AppKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

struct UndoAction: Equatable {
    let id = UUID()
    let message: String
    let perform: () -> Void

    static func == (lhs: UndoAction, rhs: UndoAction) -> Bool {
        lhs.id == rhs.id
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SettingsTab: Hashable {
    case general
    case sync
    case data
}

enum NotificationPermissionState: String {
    case unknown
    case authorized
    case denied
    case unsupported

    var label: String {
        switch self {
        case .authorized: return "已开启"
        case .denied: return "已被系统拒绝"
        case .unknown: return "尚未授权"
        case .unsupported: return "当前运行环境不支持"
        }
    }
}

enum TaskFocusField: Equatable {
    case title
    case notes
}

struct TaskFocusRequest: Equatable {
    let id = UUID()
    let taskID: String
    let field: TaskFocusField
}

struct TaskDisplayRow: Identifiable, Equatable {
    let task: TaskItem
    let isSubtask: Bool
    let childCount: Int

    var id: String { task.id }
}

@Observable
@MainActor
final class NavigatorStore {
    var tasks: [TaskItem] = []
    var tags: [TagItem] = []
    var lists: [TaskListItem] = []
    var syncStatus: SyncStatus = SyncStatus()
    var isSyncing: Bool = false
    var dataDirPath: String = ""
    var notificationState: NotificationPermissionState = .unknown

    var leadReminderMinutes: Int = UserDefaults.standard.integer(forKey: "todo.leadReminderMinutes") {
        didSet {
            UserDefaults.standard.set(leadReminderMinutes, forKey: "todo.leadReminderMinutes")
            refreshSystemChrome()
        }
    }

    var section: NavSection = .all
    var selectedTaskID: String?
    var editingTaskID: String?
    var focusRequest: TaskFocusRequest?
    var inspectorTaskID: String?
    var collapsedParentIDs: Set<String> = []
    var showCompletedInSection: Bool = false
    var searchQuery: String = ""
    var focusSearchTrigger: Int = 0

    var appearance: AppAppearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "nav.appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "nav.appearance") }
    }

    var showAddListSheet: Bool = false
    var editingList: TaskListItem?
    var showTagManager: Bool = false
    var showSettings: Bool = false
    var settingsTab: SettingsTab = .general
    var showCommandPalette: Bool = false
    var previewImagePath: String?

    var undoBanner: UndoAction?
    private var undoTimer: Timer?
    private var pendingSaves: [String: Task<Void, Never>] = [:]

    private let bridge = CoreBridge.shared
    private let notifications = NotificationManager.shared

    var liveTasks: [TaskItem] {
        tasks.filter { !$0.isDeleted }
    }

    var liveTags: [TagItem] {
        tags.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var liveLists: [TaskListItem] {
        let active = lists.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
        if active.isEmpty {
            return [TaskListItem(
                id: TaskListItem.defaultID,
                name: "提醒",
                color: ListColor.orange.rawValue,
                icon: ListIcon.list.rawValue,
                order: 0,
                updatedAt: 0,
                deleted: false
            )]
        }
        return active
    }

    func list(for id: String?) -> TaskListItem {
        let target = (id?.isEmpty == false) ? id! : TaskListItem.defaultID
        return liveLists.first(where: { $0.id == target }) ?? liveLists[0]
    }

    func bootstrap() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.lele.navigator", isDirectory: true).path
        self.dataDirPath = dir
        bridge.open(dataDir: dir) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSyncEvent(event)
            }
        }
        reload()
        syncStatus = bridge.startSync(serve: true, port: 8787)
        notifications.setup(
            onComplete: { [weak self] id in self?.toggleComplete(id: id) },
            onSnooze: { [weak self] id in self?.snoozeTask(id: id, hours: 1) },
            onOpen: { [weak self] id in
                self?.selectedTaskID = id
                self?.editingTaskID = nil
                self?.inspectorTaskID = id
                NSApp.activate(ignoringOtherApps: true)
            }
        )
        refreshSystemChrome()
    }

    func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        showSettings = true
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var globalSearchResults: [TaskItem] {
        guard isSearching else { return [] }
        return liveTasks.filter { matchesSearch($0) }
    }

    func reload() {
        let state = bridge.loadBoard()
        self.tasks = state.tasks
        self.tags = state.tags
        self.lists = state.lists ?? []
        refreshSystemChrome()
    }

    private func handleSyncEvent(_ event: SyncEvent) {
        if event.type == "status", let status = event.status {
            self.syncStatus = status
        } else if event.type == "rows" {
            reload()
        }
    }

    // MARK: - Smart Lists & Counts

    func matchesSearch(_ task: TaskItem) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if task.title.lowercased().contains(q)
            || task.notes.lowercased().contains(q)
            || task.cleanURL.lowercased().contains(q) {
            return true
        }
        if task.subtasks.contains(where: { $0.title.lowercased().contains(q) }) {
            return true
        }
        for tid in task.tagIds {
            if let tag = liveTags.first(where: { $0.id == tid }),
               tag.label.lowercased().contains(q) {
                return true
            }
        }
        return false
    }

    var todayTasks: [TaskItem] {
        liveTasks.filter { !$0.isDone && (DateHelper.isOverdue($0.dueAt) || DateHelper.isDueToday($0.dueAt)) }
    }

    var scheduledTasks: [TaskItem] {
        liveTasks.filter { !$0.isDone && ($0.dueAt?.isEmpty == false) }
            .sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
    }

    var allActiveTasks: [TaskItem] {
        liveTasks.filter { !$0.isDone }
    }

    var flaggedTasks: [TaskItem] {
        liveTasks.filter { !$0.isDone && $0.isFlagged }
    }

    var completedTasks: [TaskItem] {
        liveTasks.filter { $0.isDone }
            .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
    }

    func activeTasks(in listID: String) -> [TaskItem] {
        liveTasks.filter { !$0.isDone && $0.effectiveListID == listID }
    }

    func completedTasks(in listID: String) -> [TaskItem] {
        liveTasks.filter { $0.isDone && $0.effectiveListID == listID }
            .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
    }

    func activeTasks(forTag tagID: String) -> [TaskItem] {
        liveTasks.filter { !$0.isDone && $0.tagIds.contains(tagID) }
    }

    func allTaggedActiveTasks() -> [TaskItem] {
        liveTasks.filter { !$0.isDone && !$0.tagIds.isEmpty }
    }

    var todayCount: Int { todayTasks.count }
    var scheduledCount: Int { scheduledTasks.count }
    var allActiveCount: Int { allActiveTasks.count }
    var flaggedCount: Int { flaggedTasks.count }

    var completedCountForCurrentSection: Int {
        switch section {
        case .all, .completed:
            return completedTasks.count
        case .today:
            return liveTasks.filter { $0.isDone && DateHelper.isCompletedToday($0.completedAt) }.count
        case .scheduled:
            return liveTasks.filter { $0.isDone && ($0.dueAt?.isEmpty == false) }.count
        case .flagged:
            return liveTasks.filter { $0.isDone && $0.isFlagged }.count
        case .list(let id):
            return completedTasks(in: id).count
        case .allTags:
            return liveTasks.filter { $0.isDone && !$0.tagIds.isEmpty }.count
        case .tag(let id):
            return liveTasks.filter { $0.isDone && $0.tagIds.contains(id) }.count
        }
    }

    var completedTasksForCurrentSection: [TaskItem] {
        switch section {
        case .all, .completed:
            return completedTasks
        case .today:
            return liveTasks.filter { $0.isDone && DateHelper.isCompletedToday($0.completedAt) }
                .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
        case .scheduled:
            return liveTasks.filter { $0.isDone && ($0.dueAt?.isEmpty == false) }
                .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
        case .flagged:
            return liveTasks.filter { $0.isDone && $0.isFlagged }
                .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
        case .list(let id):
            return completedTasks(in: id)
        case .allTags:
            return liveTasks.filter { $0.isDone && !$0.tagIds.isEmpty }
                .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
        case .tag(let id):
            return liveTasks.filter { $0.isDone && $0.tagIds.contains(id) }
                .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
        }
    }

    // MARK: - Selection, Focus & Subtask Hierarchy

    func selectTask(_ id: String?) {
        if let prev = editingTaskID {
            commitInlineEditIfEmpty(id: prev)
            editingTaskID = nil
            focusRequest = nil
        }
        selectedTaskID = id
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func beginEditing(_ id: String, field: TaskFocusField) {
        if let prev = editingTaskID, prev != id {
            commitInlineEditIfEmpty(id: prev)
        }
        selectedTaskID = id
        editingTaskID = id
        focusRequest = TaskFocusRequest(taskID: id, field: field)
    }

    func endEditing(keepSelection: Bool = true) {
        if let prev = editingTaskID {
            commitInlineEditIfEmpty(id: prev)
        }
        editingTaskID = nil
        focusRequest = nil
        if !keepSelection {
            selectedTaskID = nil
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func toggleCollapse(parentID: String) {
        if collapsedParentIDs.contains(parentID) {
            collapsedParentIDs.remove(parentID)
        } else {
            collapsedParentIDs.insert(parentID)
        }
    }

    func isCollapsed(parentID: String) -> Bool {
        collapsedParentIDs.contains(parentID)
    }

    func activeSubtasks(of parentID: String) -> [TaskItem] {
        liveTasks.filter { !$0.isDone && $0.effectiveParentID == parentID }
    }

    func subtaskProgress(of parentID: String) -> (done: Int, total: Int) {
        let kids = liveTasks.filter { $0.effectiveParentID == parentID }
        guard !kids.isEmpty else { return (0, 0) }
        return (kids.filter(\.isDone).count, kids.count)
    }

    func orderedHierarchy(from source: [TaskItem], includeCompletedChildren: Bool = false) -> [TaskDisplayRow] {
        let idSet = Set(source.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        var childrenByParent: [String: [TaskItem]] = [:]
        var childIDSet = Set<String>()

        for task in source {
            if let pid = task.effectiveParentID,
               pid != task.id,
               idSet.contains(pid),
               byID[pid]?.effectiveParentID == nil {
                childrenByParent[pid, default: []].append(task)
                childIDSet.insert(task.id)
            }
        }

        var completedChildrenByParent: [String: [TaskItem]] = [:]
        if includeCompletedChildren {
            for task in liveTasks where task.isDone {
                if let pid = task.effectiveParentID,
                   !idSet.contains(task.id),
                   let parent = byID[pid],
                   !parent.isDone,
                   parent.effectiveParentID == nil {
                    completedChildrenByParent[pid, default: []].append(task)
                }
            }
            for (pid, kids) in completedChildrenByParent {
                completedChildrenByParent[pid] = kids.sorted { a, b in
                    if a.rank != b.rank { return a.rank < b.rank }
                    return a.createdAt < b.createdAt
                }
            }
        }

        var rows: [TaskDisplayRow] = []
        rows.reserveCapacity(source.count)
        for task in source where !childIDSet.contains(task.id) {
            let activeKids = childrenByParent[task.id] ?? []
            let doneKids = completedChildrenByParent[task.id] ?? []
            let totalKids = activeKids.count + doneKids.count
            rows.append(TaskDisplayRow(task: task, isSubtask: false, childCount: totalKids))
            if totalKids > 0 && !collapsedParentIDs.contains(task.id) {
                for child in activeKids {
                    rows.append(TaskDisplayRow(task: child, isSubtask: true, childCount: 0))
                }
                for child in doneKids {
                    rows.append(TaskDisplayRow(task: child, isSubtask: true, childCount: 0))
                }
            }
        }
        return rows
    }

    var visibleActiveParentIDsInCurrentSection: Set<String> {
        let activeSource: [TaskItem]
        switch section {
        case .all:
            activeSource = allActiveTasks
        case .today:
            activeSource = todayTasks
        case .scheduled:
            activeSource = scheduledTasks
        case .flagged:
            activeSource = flaggedTasks
        case .completed:
            return []
        case .list(let listID):
            activeSource = activeTasks(in: listID)
        case .allTags:
            activeSource = allTaggedActiveTasks()
        case .tag(let tagID):
            activeSource = activeTasks(forTag: tagID)
        }
        return Set(activeSource.filter { !$0.isDone && $0.effectiveParentID == nil }.map(\.id))
    }

    var completedTasksNotUnderActiveParentsForCurrentSection: [TaskItem] {
        let activeParents = visibleActiveParentIDsInCurrentSection
        return completedTasksForCurrentSection.filter { task in
            guard let pid = task.effectiveParentID else { return true }
            return !activeParents.contains(pid)
        }
    }

    var activeActionTaskID: String? {
        selectedTaskID ?? editingTaskID
    }

    func canIndentTask(id: String) -> Bool {
        guard let task = liveTasks.first(where: { $0.id == id }),
              !task.isDone,
              task.effectiveParentID == nil,
              activeSubtasks(of: id).isEmpty else {
            return false
        }
        let topLevel = activeTasks(in: task.effectiveListID).filter { $0.effectiveParentID == nil }
        guard let idx = topLevel.firstIndex(where: { $0.id == id }) else { return false }
        return idx > 0
    }

    func indentTask(id: String) {
        guard canIndentTask(id: id),
              let task = liveTasks.first(where: { $0.id == id }) else { return }
        let listTasks = activeTasks(in: task.effectiveListID)
        let topLevel = listTasks.filter { $0.effectiveParentID == nil }
        guard let idx = topLevel.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        let newParent = topLevel[idx - 1]
        let existingKids = listTasks.filter { $0.effectiveParentID == newParent.id }
        let nextRank = (existingKids.map(\.rank).max() ?? newParent.rank) + 100

        collapsedParentIDs.remove(newParent.id)
        patchTask(id: id, rescheduleNotifications: false) { t, now in
            t.parentId = newParent.id
            t.rank = nextRank
            t.stamps?["parentId"] = now
            t.stamps?["rank"] = now
        }
        reload()
        selectedTaskID = id
    }

    func canOutdentTask(id: String) -> Bool {
        guard let task = liveTasks.first(where: { $0.id == id }),
              !task.isDone else { return false }
        return task.effectiveParentID != nil
    }

    func outdentTask(id: String) {
        guard let task = liveTasks.first(where: { $0.id == id }),
              !task.isDone,
              let oldParentID = task.effectiveParentID else { return }
        let listTasks = activeTasks(in: task.effectiveListID)
        let topLevel = listTasks.filter { $0.effectiveParentID == nil }
        let newRank: Double
        if let pIdx = topLevel.firstIndex(where: { $0.id == oldParentID }) {
            let parentRank = topLevel[pIdx].rank
            if pIdx + 1 < topLevel.count {
                let nextRank = topLevel[pIdx + 1].rank
                newRank = nextRank > parentRank ? (parentRank + nextRank) / 2.0 : parentRank + 500
            } else {
                newRank = (liveTasks.map(\.rank).max() ?? parentRank) + 1000
            }
        } else {
            newRank = (liveTasks.map(\.rank).max() ?? 0) + 1000
        }

        patchTask(id: id, rescheduleNotifications: false) { t, now in
            t.parentId = nil
            t.rank = newRank
            t.stamps?["parentId"] = now
            t.stamps?["rank"] = now
        }
        reload()
        selectedTaskID = id
    }

    var canIndentSelectedTask: Bool {
        guard let id = activeActionTaskID else { return false }
        return canIndentTask(id: id)
    }

    var canOutdentSelectedTask: Bool {
        guard let id = activeActionTaskID else { return false }
        return canOutdentTask(id: id)
    }

    func indentSelectedTask() {
        guard let id = activeActionTaskID else { return }
        indentTask(id: id)
    }

    func outdentSelectedTask() {
        guard let id = activeActionTaskID else { return }
        outdentTask(id: id)
    }

    var visibleOrderedTaskIDs: [String] {
        if isSearching {
            return orderedHierarchy(from: globalSearchResults).map(\.id)
        }
        let showDone = showCompletedInSection
        var ids: [String] = []
        switch section {
        case .all:
            for list in liveLists {
                ids.append(contentsOf: orderedHierarchy(from: activeTasks(in: list.id), includeCompletedChildren: showDone).map(\.id))
            }
        case .today:
            ids = orderedHierarchy(from: todayTasks, includeCompletedChildren: showDone).map(\.id)
        case .scheduled:
            let items = scheduledTasks
            let grouped = Dictionary(grouping: items) { DateHelper.upcomingGroupTitle(for: $0.dueAt) }
            let orderedKeys = items.reduce(into: [String]()) { acc, item in
                let k = DateHelper.upcomingGroupTitle(for: item.dueAt)
                if !acc.contains(k) { acc.append(k) }
            }
            for day in orderedKeys {
                ids.append(contentsOf: orderedHierarchy(from: grouped[day] ?? [], includeCompletedChildren: showDone).map(\.id))
            }
        case .flagged:
            ids = orderedHierarchy(from: flaggedTasks, includeCompletedChildren: showDone).map(\.id)
        case .completed:
            let items = completedTasks
            let grouped = Dictionary(grouping: items) { DateHelper.logbookGroupTitle(for: $0.completedAt) }
            let orderedKeys = items.reduce(into: [String]()) { acc, item in
                let k = DateHelper.logbookGroupTitle(for: item.completedAt)
                if !acc.contains(k) { acc.append(k) }
            }
            for day in orderedKeys {
                ids.append(contentsOf: orderedHierarchy(from: grouped[day] ?? []).map(\.id))
            }
        case .list(let listID):
            ids = orderedHierarchy(from: activeTasks(in: listID), includeCompletedChildren: showDone).map(\.id)
        case .allTags:
            ids = orderedHierarchy(from: allTaggedActiveTasks(), includeCompletedChildren: showDone).map(\.id)
        case .tag(let tagID):
            ids = orderedHierarchy(from: activeTasks(forTag: tagID), includeCompletedChildren: showDone).map(\.id)
        }
        if section != .completed && showDone {
            ids.append(contentsOf: orderedHierarchy(from: completedTasksNotUnderActiveParentsForCurrentSection).map(\.id))
        }
        return ids
    }

    func moveSelection(by delta: Int) {
        let ids = visibleOrderedTaskIDs
        guard !ids.isEmpty else { return }
        guard let current = selectedTaskID, let idx = ids.firstIndex(of: current) else {
            selectTask(delta > 0 ? ids.first : ids.last)
            return
        }
        let next = min(max(idx + delta, 0), ids.count - 1)
        selectTask(ids[next])
    }

    // MARK: - Task Mutations

    @discardableResult
    func createInlineTask(
        in listID: String? = nil,
        parentID: String? = nil,
        title: String = "",
        dueAt: String? = nil,
        flagged: Bool = false,
        tagIds: [String] = []
    ) -> TaskItem {
        let targetListID: String
        if let parentID, let parent = liveTasks.first(where: { $0.id == parentID }) {
            targetListID = parent.effectiveListID
            collapsedParentIDs.remove(parentID)
        } else if let listID, !listID.isEmpty {
            targetListID = listID
        } else if case .list(let cur) = section {
            targetListID = cur
        } else {
            targetListID = liveLists.first?.id ?? TaskListItem.defaultID
        }

        let effectiveDue: String? = dueAt ?? (section == .today ? DateHelper.presetDate(daysOffset: 0, hour: 18) : nil)
        let effectiveFlagged = flagged || (section == .flagged)
        var effectiveTags = tagIds
        if case .tag(let tid) = section, !effectiveTags.contains(tid) {
            effectiveTags.append(tid)
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let nextRank: Double
        if let parentID {
            let kids = activeSubtasks(of: parentID)
            let parentRank = liveTasks.first(where: { $0.id == parentID })?.rank ?? 0
            nextRank = (kids.map(\.rank).max() ?? parentRank) + 100
        } else {
            nextRank = (liveTasks.map(\.rank).max() ?? 0) + 1000
        }
        let item = TaskItem(
            id: "t_\(UUID().uuidString.prefix(12).lowercased())",
            title: title,
            notes: "",
            status: .todo,
            listId: targetListID,
            parentId: parentID,
            flagged: effectiveFlagged,
            priority: 0,
            url: nil,
            subtasks: [],
            tagIds: effectiveTags,
            dueAt: effectiveDue,
            repeatRule: RepeatRule.none,
            attachments: [],
            rank: nextRank,
            completedAt: nil,
            createdAt: now,
            updatedAt: now,
            deleted: false,
            stamps: [
                "title": now, "notes": now, "status": now,
                "listId": now, "parentId": now, "flagged": now, "priority": now,
                "url": now, "subtasks": now, "tagIds": now,
                "dueAt": now, "repeatRule": now, "rank": now, "deleted": now
            ]
        )
        let saved = bridge.saveTask(item)
        reload()
        selectedTaskID = saved.id
        editingTaskID = saved.id
        focusRequest = TaskFocusRequest(taskID: saved.id, field: .title)
        return saved
    }

    func commitInlineEditIfEmpty(id: String) {
        guard let task = liveTasks.first(where: { $0.id == id }) else { return }
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && task.subtasks.isEmpty
            && task.attachmentList.isEmpty
            && activeSubtasks(of: id).isEmpty {
            bridge.deleteTask(id: id, deleted: true)
            if selectedTaskID == id { selectedTaskID = nil }
            if editingTaskID == id { editingTaskID = nil }
            if inspectorTaskID == id { inspectorTaskID = nil }
            reload()
        }
    }

    func patchTask(id: String, rescheduleNotifications: Bool = true, mutate: (inout TaskItem, Int64) -> Void) {
        guard var task = liveTasks.first(where: { $0.id == id }) else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if task.stamps == nil { task.stamps = [:] }
        mutate(&task, now)
        task.updatedAt = now
        if task.dueAt == nil || task.dueAt?.isEmpty == true {
            task.dueAt = nil
            task.repeatRule = RepeatRule.none
            task.stamps?["repeatRule"] = now
        }
        pendingSaves.removeValue(forKey: id)?.cancel()
        bridge.saveTask(task)
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx] = task
        }
        refreshSystemChrome(rescheduleNotifications: rescheduleNotifications)
    }

    func debouncedPatchTask(id: String, mutate: (inout TaskItem, Int64) -> Void) {
        guard var task = liveTasks.first(where: { $0.id == id }) else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if task.stamps == nil { task.stamps = [:] }
        mutate(&task, now)
        task.updatedAt = now
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx] = task
        }
        let snapshot = task
        pendingSaves.removeValue(forKey: id)?.cancel()
        pendingSaves[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.bridge.saveTask(snapshot)
            self.pendingSaves.removeValue(forKey: id)
        }
    }

    func toggleFlag(id: String) {
        patchTask(id: id, rescheduleNotifications: false) { t, now in
            t.flagged = !t.isFlagged
            t.stamps?["flagged"] = now
        }
    }

    func setPriority(id: String, priority: TaskPriority) {
        patchTask(id: id, rescheduleNotifications: false) { t, now in
            t.priority = priority.rawValue
            t.stamps?["priority"] = now
        }
    }

    func moveTaskToList(id: String, listID: String) {
        guard let task = liveTasks.first(where: { $0.id == id }) else { return }
        let children = liveTasks.filter { $0.effectiveParentID == id }
        patchTask(id: id, rescheduleNotifications: false) { t, now in
            t.listId = listID
            t.stamps?["listId"] = now
            if t.effectiveParentID != nil && task.effectiveListID != listID {
                t.parentId = nil
                t.stamps?["parentId"] = now
            }
        }
        for child in children {
            patchTask(id: child.id, rescheduleNotifications: false) { c, now in
                c.listId = listID
                c.stamps?["listId"] = now
            }
        }
    }

    func toggleComplete(id: String, forceDone: Bool? = nil) {
        guard let task = liveTasks.first(where: { $0.id == id }) else { return }
        pendingSaves.removeValue(forKey: id)?.cancel()
        let nextDone = forceDone ?? !task.isDone
        let saved = bridge.completeTask(id: id, done: nextDone)
        let spawned = nextDone ? saved.first(where: { $0.id != id }) : nil
        if nextDone && editingTaskID == id { editingTaskID = nil }
        if nextDone && selectedTaskID == id { selectedTaskID = nil }
        reload()
        if nextDone {
            showUndo(message: "已完成「\(task.title.isEmpty ? "未命名提醒" : task.title)」") { [weak self] in
                guard let self else { return }
                _ = self.bridge.completeTask(id: id, done: false)
                if let spawned {
                    self.bridge.deleteTask(id: spawned.id, deleted: true)
                }
                self.reload()
            }
        }
    }

    func clearCompletedForCurrentSection() {
        let listFilter: String?
        if case .list(let id) = section {
            listFilter = id
        } else {
            listFilter = nil
        }
        let cleared = bridge.clearCompleted(listID: listFilter)
        guard !cleared.isEmpty else { return }
        reload()
        let clearedIDs = cleared.map(\.id)
        showUndo(message: "已清除 \(cleared.count) 项已完成提醒") { [weak self] in
            guard let self else { return }
            for id in clearedIDs {
                self.bridge.deleteTask(id: id, deleted: false)
            }
            self.reload()
        }
    }

    func deleteTask(id: String) {
        guard let task = liveTasks.first(where: { $0.id == id }) else { return }
        let childIDs = liveTasks.filter { $0.effectiveParentID == id }.map(\.id)
        let allDeletedIDs = [id] + childIDs
        if let sel = selectedTaskID, allDeletedIDs.contains(sel) { selectedTaskID = nil }
        if let ed = editingTaskID, allDeletedIDs.contains(ed) { editingTaskID = nil }
        if let ins = inspectorTaskID, allDeletedIDs.contains(ins) { inspectorTaskID = nil }
        for targetID in allDeletedIDs {
            bridge.deleteTask(id: targetID, deleted: true)
        }
        reload()
        let suffix = childIDs.isEmpty ? "" : "及 \(childIDs.count) 项子任务"
        showUndo(message: "已删除「\(task.title.isEmpty ? "未命名提醒" : task.title)」\(suffix)") { [weak self] in
            guard let self else { return }
            for targetID in allDeletedIDs {
                self.bridge.deleteTask(id: targetID, deleted: false)
            }
            self.reload()
        }
    }

    func snoozeTask(id: String, hours: Int) {
        let next = Date().addingTimeInterval(TimeInterval(hours * 3600))
        let formatted = DateHelper.formatDue(next)
        patchTask(id: id) { t, now in
            t.dueAt = formatted
            t.stamps?["dueAt"] = now
        }
        reload()
    }

    // MARK: - Lists

    func createList(name: String, color: ListColor, icon: ListIcon) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let order = (liveLists.map(\.order).max() ?? -1) + 1
        let list = TaskListItem(
            id: "list_\(UUID().uuidString.prefix(8).lowercased())",
            name: clean,
            color: color.rawValue,
            icon: icon.rawValue,
            order: order,
            updatedAt: now,
            deleted: false
        )
        let saved = bridge.saveList(list)
        reload()
        section = .list(saved.id)
    }

    func updateList(_ list: TaskListItem) {
        var copy = list
        copy.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        bridge.saveList(copy)
        reload()
    }

    func deleteList(id: String) {
        guard liveLists.count > 1 else { return }
        bridge.deleteList(id: id)
        if case .list(let cur) = section, cur == id {
            section = .all
        }
        reload()
    }

    // MARK: - Structured Subtasks

    func addSubtask(to taskID: String, title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        patchTask(id: taskID, rescheduleNotifications: false) { t, now in
            let nextOrder = (t.subtasks.map(\.order).max() ?? -1) + 1
            t.subtasks.append(SubtaskItem(
                id: "s_\(UUID().uuidString.prefix(8).lowercased())",
                title: clean,
                done: false,
                order: nextOrder
            ))
            t.stamps?["subtasks"] = now
        }
    }

    func toggleSubtask(taskID: String, subtaskID: String) {
        patchTask(id: taskID, rescheduleNotifications: false) { t, now in
            if let idx = t.subtasks.firstIndex(where: { $0.id == subtaskID }) {
                t.subtasks[idx].done.toggle()
                t.stamps?["subtasks"] = now
            }
        }
    }

    func updateSubtaskTitle(taskID: String, subtaskID: String, title: String) {
        debouncedPatchTask(id: taskID) { t, now in
            if let idx = t.subtasks.firstIndex(where: { $0.id == subtaskID }) {
                t.subtasks[idx].title = title
                t.stamps?["subtasks"] = now
            }
        }
    }

    func deleteSubtask(taskID: String, subtaskID: String) {
        patchTask(id: taskID, rescheduleNotifications: false) { t, now in
            t.subtasks.removeAll { $0.id == subtaskID }
            t.stamps?["subtasks"] = now
        }
    }

    // MARK: - Attachments

    func attachImage(to taskID: String, data: Data, ext: String = "png") {
        let name = bridge.saveAsset(data: data, ext: ext)
        guard !name.isEmpty else { return }
        patchTask(id: taskID, rescheduleNotifications: false) { t, now in
            var list = t.attachmentList
            guard list.count < 6, !list.contains(name) else { return }
            list.append(name)
            t.attachments = list
            t.stamps?["attachments"] = now
        }
    }

    func removeAttachment(from taskID: String, name: String) {
        patchTask(id: taskID, rescheduleNotifications: false) { t, now in
            t.attachments = t.attachmentList.filter { $0 != name }
            t.stamps?["attachments"] = now
        }
    }

    func assetURL(for name: String) -> URL? {
        let p = bridge.assetPath(name: name)
        return p.isEmpty ? nil : URL(fileURLWithPath: p)
    }

    // MARK: - Tags

    func createTag(label: String, hue: TagHue = .blue) {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let order = (liveTags.map(\.order).max() ?? -1) + 1
        let tag = TagItem(
            id: "tag_\(UUID().uuidString.prefix(8).lowercased())",
            label: clean,
            hue: hue,
            order: order,
            updatedAt: now,
            deleted: false
        )
        bridge.saveTag(tag)
        reload()
    }

    func updateTag(_ tag: TagItem) {
        var copy = tag
        copy.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        bridge.saveTag(copy)
        reload()
    }

    func deleteTag(id: String) {
        bridge.deleteTag(id: id)
        if case .tag(let active) = section, active == id {
            section = .all
        }
        reload()
    }

    // MARK: - Sync & Export

    func refreshSyncStatus() {
        syncStatus = bridge.syncStatus()
    }

    func generatePairingCode() {
        _ = bridge.generatePairingCode()
        syncStatus = bridge.syncStatus()
    }

    func pairWithPeer(ip: String, port: Int = 8787, code: String, completion: @escaping (Result<PairedPeer, Error>) -> Void) {
        isSyncing = true
        let trimmedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = code.filter(\.isNumber)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let res = CoreBridge.shared.pairWithPeer(ip: trimmedIP, port: port, code: digits)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSyncing = false
                self.syncStatus = self.bridge.syncStatus()
                if let peer = res.peer {
                    completion(.success(peer))
                } else {
                    completion(.failure(NSError(domain: "Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: res.error ?? "配对失败"])))
                }
            }
        }
    }

    func deletePairedPeer(deviceID: String) {
        bridge.deletePairedPeer(deviceID: deviceID)
        syncStatus = bridge.syncStatus()
    }

    func syncWithPeer(deviceID: String, completion: ((String?) -> Void)? = nil) {
        isSyncing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let err = CoreBridge.shared.syncWithPeer(deviceID: deviceID)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSyncing = false
                self.reload()
                self.syncStatus = self.bridge.syncStatus()
                completion?(err)
            }
        }
    }

    func syncNow() {
        bridge.syncNow()
        syncStatus = bridge.syncStatus()
    }

    var syncBadgeInfo: (color: Color, label: String, detail: String) {
        if isSyncing {
            return (NavTheme.accentBlue, "同步中…", "正在与局域网设备同步")
        }
        if let err = syncStatus.lastError, !err.isEmpty {
            return (NavTheme.danger, "同步异常", err)
        }
        let onlinePaired = syncStatus.pairedPeers.filter(\.online).count
        if !syncStatus.pairedPeers.isEmpty {
            if syncStatus.syncedAt > 0 {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                let t = f.string(from: Date(timeIntervalSince1970: Double(syncStatus.syncedAt) / 1000.0))
                if onlinePaired > 0 {
                    return (NavTheme.logbookGreen, "已同步 · \(t)", "\(onlinePaired) 台设备在线")
                }
                return (NavTheme.logbookGreen.opacity(0.75), "已同步 · \(t)", "已配对设备当前离线")
            }
            if onlinePaired > 0 {
                return (NavTheme.logbookGreen, "\(onlinePaired) 台在线", "点击立即同步")
            }
            return (.gray, "已配对 · 离线", "等待设备加入同一 Wi-Fi")
        }
        if !syncStatus.discoveredPeers.isEmpty {
            return (NavTheme.flaggedOrange, "发现 \(syncStatus.discoveredPeers.count) 台设备", "点击前往配对")
        }
        return (syncStatus.running ? NavTheme.accentBlue : .gray, "未配对", "点击配置局域网同步")
    }

    func importJSON(_ raw: String) {
        bridge.importJSON(raw)
        reload()
        showUndo(message: "已合并剪贴板中的 JSON 数据") {}
    }

    func copyMarkdownExport() {
        let md = bridge.exportMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        showUndo(message: "已复制 Markdown 导出内容到剪贴板") {}
    }

    // MARK: - Undo & System Chrome

    private func showUndo(message: String, perform: @escaping () -> Void) {
        undoTimer?.invalidate()
        undoBanner = UndoAction(message: message, perform: perform)
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.undoBanner = nil
            }
        }
    }

    func triggerUndo() {
        undoTimer?.invalidate()
        let action = undoBanner
        undoBanner = nil
        action?.perform()
    }

    func dismissUndo() {
        undoTimer?.invalidate()
        undoBanner = nil
    }

    func refreshNotificationStatus() {
        notifications.queryStatus { [weak self] state in
            Task { @MainActor [weak self] in
                self?.notificationState = state
            }
        }
    }

    func requestNotificationPermission() {
        NSApp.activate(ignoringOtherApps: true)
        notifications.requestPermission { [weak self] state, shouldOpenSettings in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.notificationState = state
                self.refreshSystemChrome()
                if shouldOpenSettings {
                    self.openSystemNotificationSettings()
                }
            }
        }
    }

    func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lele.todo"
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func sendTestNotification() {
        notifications.sendTest()
        showUndo(message: "已发送测试通知，2 秒后送达") {}
    }

    private func refreshSystemChrome(rescheduleNotifications: Bool = true) {
        let count = todayCount
        NSApplication.shared.dockTile.badgeLabel = count == 0 ? nil : (count > 99 ? "99+" : "\(count)")
        if rescheduleNotifications {
            notifications.reschedule(tasks: liveTasks, leadMinutes: leadReminderMinutes)
            refreshNotificationStatus()
        }
    }
}

// MARK: - Native macOS Notification Center

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let categoryID = "todo.reminder"
    private var onComplete: ((String) -> Void)?
    private var onSnooze: ((String) -> Void)?
    private var onOpen: ((String) -> Void)?

    func setup(
        onComplete: @escaping (String) -> Void,
        onSnooze: @escaping (String) -> Void,
        onOpen: @escaping (String) -> Void
    ) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        self.onComplete = onComplete
        self.onSnooze = onSnooze
        self.onOpen = onOpen

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let doneAction = UNNotificationAction(identifier: "done", title: "完成")
        let snoozeAction = UNNotificationAction(identifier: "snooze", title: "推迟 1 小时")
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [doneAction, snoozeAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func queryStatus(completion: @escaping (NotificationPermissionState) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else {
            completion(.unsupported)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(.authorized)
            case .denied:
                completion(.denied)
            default:
                completion(.unknown)
            }
        }
    }

    func requestPermission(completion: @escaping (NotificationPermissionState, Bool) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else {
            completion(.unsupported, true)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                completion(.authorized, false)
            } else {
                completion(error != nil ? .unknown : .denied, true)
            }
        }
    }

    func sendTest() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "TODO 通知测试"
        content.body = "通知权限已正常生效，到期提醒会准时送达。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(identifier: "todo.test.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    func reschedule(tasks: [TaskItem], leadMinutes: Int = 0) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        for task in tasks where !task.isDone {
            guard let due = DateHelper.parseDue(task.dueAt) else { continue }
            let interval = due.timeIntervalSince(now)
            if interval > 1 {
                let content = UNMutableNotificationContent()
                content.title = task.title.isEmpty ? "提醒到期" : task.title
                content.body = task.notes.isEmpty ? "设定的提醒时间到了" : task.notes
                content.sound = .default
                content.categoryIdentifier = categoryID

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let req = UNNotificationRequest(identifier: "nav.\(task.id)", content: content, trigger: trigger)
                center.add(req)
            }

            if leadMinutes > 0 {
                let earlyInterval = interval - TimeInterval(leadMinutes * 60)
                if earlyInterval > 1 {
                    let early = UNMutableNotificationContent()
                    early.title = "即将到期：\(task.title.isEmpty ? "未命名提醒" : task.title)"
                    early.body = "距离截止还有 \(leadMinutes) 分钟"
                    early.sound = .default
                    early.categoryIdentifier = categoryID

                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: earlyInterval, repeats: false)
                    let req = UNNotificationRequest(identifier: "nav.\(task.id).pre", content: early, trigger: trigger)
                    center.add(req)
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let rawId = response.notification.request.identifier
            .replacingOccurrences(of: "nav.", with: "")
            .replacingOccurrences(of: ".pre", with: "")
        await MainActor.run {
            switch response.actionIdentifier {
            case "done": onComplete?(rawId)
            case "snooze": onSnooze?(rawId)
            case UNNotificationDefaultActionIdentifier: onOpen?(rawId)
            default: break
            }
        }
    }
}
