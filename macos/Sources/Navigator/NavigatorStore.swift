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

@Observable
@MainActor
final class NavigatorStore {
    var tasks: [TaskItem] = []
    var tags: [TagItem] = []
    var syncStatus: SyncStatus = SyncStatus()
    var dataDirPath: String = ""
    var notificationState: NotificationPermissionState = .unknown

    var leadReminderMinutes: Int = UserDefaults.standard.integer(forKey: "todo.leadReminderMinutes") {
        didSet {
            UserDefaults.standard.set(leadReminderMinutes, forKey: "todo.leadReminderMinutes")
            refreshSystemChrome()
        }
    }

    var section: NavSection = .today
    var viewMode: ViewMode = .list
    var selectedTaskID: String?
    var searchQuery: String = ""
    var focusSearchTrigger: Int = 0

    var appearance: AppAppearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "nav.appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "nav.appearance") }
    }

    var showQuickCapture: Bool = false
    var showTagManager: Bool = false
    var showSettings: Bool = false
    var settingsTab: SettingsTab = .general
    var showCommandPalette: Bool = false
    var previewImagePath: String?

    var undoBanner: UndoAction?
    private var undoTimer: Timer?

    private let bridge = CoreBridge.shared
    private let notifications = NotificationManager.shared

    var liveTasks: [TaskItem] {
        tasks.filter { !$0.isDeleted }
    }

    var liveTags: [TagItem] {
        tags.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var selectedTask: TaskItem? {
        guard let id = selectedTaskID else { return nil }
        return liveTasks.first { $0.id == id }
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
        refreshSystemChrome()
    }

    private func handleSyncEvent(_ event: SyncEvent) {
        if event.type == "status", let status = event.status {
            self.syncStatus = status
        } else if event.type == "rows" {
            reload()
        }
    }

    // MARK: - Filtered Collections

    func matchesSearch(_ task: TaskItem) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if task.title.lowercased().contains(q) || task.notes.lowercased().contains(q) {
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

    var todayOverdueTasks: [TaskItem] {
        liveTasks.filter { !$0.isDone && DateHelper.isOverdue($0.dueAt) && matchesSearch($0) }
    }

    var todayActiveTasks: [TaskItem] {
        liveTasks.filter {
            !$0.isDone && !DateHelper.isOverdue($0.dueAt) &&
            (DateHelper.isDueToday($0.dueAt) || $0.status == .doing) &&
            matchesSearch($0)
        }
    }

    var todayCompletedTasks: [TaskItem] {
        liveTasks.filter { $0.isDone && DateHelper.isCompletedToday($0.completedAt) && matchesSearch($0) }
    }

    var doingTasks: [TaskItem] {
        liveTasks.filter { $0.status == .doing && matchesSearch($0) }
    }

    var todoTasks: [TaskItem] {
        liveTasks.filter { $0.status == .todo && matchesSearch($0) }
    }

    var upcomingTasks: [TaskItem] {
        liveTasks.filter { !$0.isDone && ($0.dueAt?.isEmpty == false) && matchesSearch($0) }
            .sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
    }

    var logbookTasks: [TaskItem] {
        liveTasks.filter { $0.isDone && matchesSearch($0) }
            .sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
    }

    func tasksForTag(_ tagID: String) -> [TaskItem] {
        liveTasks.filter { !$0.isDone && $0.tagIds.contains(tagID) && matchesSearch($0) }
    }

    var attentionCount: Int {
        liveTasks.filter { !$0.isDone && (DateHelper.isOverdue($0.dueAt) || DateHelper.isDueToday($0.dueAt)) }.count
    }

    var doingCount: Int {
        liveTasks.filter { $0.status == .doing }.count
    }

    var todoCount: Int {
        liveTasks.filter { $0.status == .todo }.count
    }

    // MARK: - Task Mutations

    @discardableResult
    func createTask(
        title: String,
        notes: String = "",
        status: TaskStatus = .todo,
        tagIds: [String] = [],
        dueAt: String? = nil,
        repeatRule: RepeatRule = .none
    ) -> TaskItem {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let minRank = liveTasks.map(\.rank).min() ?? 1000
        let item = TaskItem(
            id: "t_\(UUID().uuidString.prefix(12).lowercased())",
            title: title,
            notes: notes,
            status: status,
            subtasks: [],
            tagIds: tagIds,
            dueAt: dueAt,
            repeatRule: dueAt == nil ? .none : repeatRule,
            attachments: [],
            rank: minRank - 100,
            completedAt: nil,
            createdAt: now,
            updatedAt: now,
            deleted: false,
            stamps: [
                "title": now, "notes": now, "status": now,
                "subtasks": now, "tagIds": now, "dueAt": now,
                "repeatRule": now, "rank": now, "deleted": now
            ]
        )
        let saved = bridge.saveTask(item)
        reload()
        selectedTaskID = saved.id
        return saved
    }

    func patchTask(id: String, mutate: (inout TaskItem, Int64) -> Void) {
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
        bridge.saveTask(task)
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx] = task
        }
        refreshSystemChrome()
    }

    func moveTask(id: String, to status: TaskStatus) {
        if status == .done {
            toggleComplete(id: id, forceDone: true)
            return
        }
        patchTask(id: id) { t, now in
            t.status = status
            t.completedAt = nil
            t.stamps?["status"] = now
            t.stamps?["completedAt"] = now
        }
        reload()
    }

    func toggleComplete(id: String, forceDone: Bool? = nil) {
        guard let task = liveTasks.first(where: { $0.id == id }) else { return }
        let nextDone = forceDone ?? !task.isDone
        _ = bridge.completeTask(id: id, done: nextDone)
        reload()
        if nextDone {
            showUndo(message: "已完成「\(task.title.isEmpty ? "未命名任务" : task.title)」") { [weak self] in
                guard let self else { return }
                _ = self.bridge.completeTask(id: id, done: false)
                self.reload()
            }
        }
    }

    func deleteTask(id: String) {
        guard let task = liveTasks.first(where: { $0.id == id }) else { return }
        if selectedTaskID == id {
            selectedTaskID = nil
        }
        bridge.deleteTask(id: id, deleted: true)
        reload()
        showUndo(message: "已删除「\(task.title.isEmpty ? "未命名任务" : task.title)」") { [weak self] in
            guard let self else { return }
            self.bridge.deleteTask(id: id, deleted: false)
            self.reload()
            self.selectedTaskID = id
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

    // MARK: - Structured Subtasks

    func addSubtask(to taskID: String, title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        patchTask(id: taskID) { t, now in
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
        patchTask(id: taskID) { t, now in
            if let idx = t.subtasks.firstIndex(where: { $0.id == subtaskID }) {
                t.subtasks[idx].done.toggle()
                t.stamps?["subtasks"] = now
            }
        }
    }

    func updateSubtaskTitle(taskID: String, subtaskID: String, title: String) {
        patchTask(id: taskID) { t, now in
            if let idx = t.subtasks.firstIndex(where: { $0.id == subtaskID }) {
                t.subtasks[idx].title = title
                t.stamps?["subtasks"] = now
            }
        }
    }

    func deleteSubtask(taskID: String, subtaskID: String) {
        patchTask(id: taskID) { t, now in
            t.subtasks.removeAll { $0.id == subtaskID }
            t.stamps?["subtasks"] = now
        }
    }

    // MARK: - Attachments

    func attachImage(to taskID: String, data: Data, ext: String = "png") {
        let name = bridge.saveAsset(data: data, ext: ext)
        guard !name.isEmpty else { return }
        patchTask(id: taskID) { t, now in
            var list = t.attachmentList
            guard list.count < 6, !list.contains(name) else { return }
            list.append(name)
            t.attachments = list
            t.stamps?["attachments"] = now
        }
    }

    func removeAttachment(from taskID: String, name: String) {
        patchTask(id: taskID) { t, now in
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
            section = .today
        }
        reload()
    }

    // MARK: - Sync & Export

    func regeneratePairCode() {
        _ = bridge.regeneratePairCode()
        syncStatus = bridge.syncStatus()
    }

    func syncNow() {
        bridge.syncNow()
        syncStatus = bridge.syncStatus()
    }

    func connectManualPeer(address: String, code: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            bridge.addPeerAddress(trimmed)
        }
        let digits = code.filter(\.isNumber)
        if digits.count == 6 {
            bridge.setPeerCode(digits)
        }
        bridge.syncNow()
        syncStatus = bridge.syncStatus()
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
        notifications.requestPermission { [weak self] state in
            Task { @MainActor [weak self] in
                self?.notificationState = state
                self?.refreshSystemChrome()
            }
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func sendTestNotification() {
        notifications.sendTest()
        showUndo(message: "已发送测试通知，2 秒后送达") {}
    }

    private func refreshSystemChrome() {
        let count = attentionCount
        NSApplication.shared.dockTile.badgeLabel = count == 0 ? nil : (count > 99 ? "99+" : "\(count)")
        notifications.reschedule(tasks: liveTasks, leadMinutes: leadReminderMinutes)
        refreshNotificationStatus()
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

    func requestPermission(completion: @escaping (NotificationPermissionState) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else {
            completion(.unsupported)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion(granted ? .authorized : .denied)
        }
    }

    func sendTest() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "TODO 通知测试"
        content.body = "通知权限已正常生效，到期任务会准时提醒你。"
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
                content.title = task.title.isEmpty ? "任务到期" : task.title
                content.body = task.notes.isEmpty ? "截止时间到了" : task.notes
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
                    early.title = "即将到期：\(task.title.isEmpty ? "未命名任务" : task.title)"
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
