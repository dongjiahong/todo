import Foundation
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case doing
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo, .doing: return "未完成"
        case .done: return "已完成"
        }
    }
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "无"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var bangPrefix: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}

enum ListColor: String, Codable, CaseIterable, Identifiable {
    case blue
    case orange
    case green
    case red
    case purple
    case pink
    case yellow
    case gray

    var id: String { rawValue }

    var color: Color {
        NavTheme.listColor(for: self)
    }

    var label: String {
        switch self {
        case .blue: return "蓝色"
        case .orange: return "橙色"
        case .green: return "绿色"
        case .red: return "红色"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .yellow: return "黄色"
        case .gray: return "灰色"
        }
    }
}

enum ListIcon: String, Codable, CaseIterable, Identifiable {
    case list
    case work
    case study
    case life
    case home
    case cart
    case star
    case book
    case code
    case heart

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .list: return "list.bullet"
        case .work: return "desktopcomputer"
        case .study: return "graduationcap.fill"
        case .life: return "gamecontroller.fill"
        case .home: return "house.fill"
        case .cart: return "cart.fill"
        case .star: return "star.fill"
        case .book: return "book.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .heart: return "heart.fill"
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none = ""
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "不重复"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

enum TagHue: String, Codable, CaseIterable, Identifiable {
    case blue
    case green
    case purple
    case amber
    case red

    var id: String { rawValue }

    var color: Color {
        NavTheme.tagColor(for: self)
    }

    var next: TagHue {
        let all = TagHue.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

struct SubtaskItem: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var done: Bool
    var order: Int
}

struct TaskListItem: Codable, Identifiable, Equatable, Hashable {
    static let defaultID = "list_reminders"

    var id: String
    var name: String
    var color: String
    var icon: String
    var order: Int
    var updatedAt: Int64
    var deleted: Bool?

    var isDeleted: Bool { deleted == true }
    var listColor: ListColor { ListColor(rawValue: color) ?? .blue }
    var listIcon: ListIcon { ListIcon(rawValue: icon) ?? .list }
    var swiftUIColor: Color { listColor.color }
    var symbolName: String { listIcon.symbolName }
}

struct TaskItem: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var notes: String
    var status: TaskStatus
    var listId: String?
    var parentId: String?
    var flagged: Bool?
    var priority: Int?
    var url: String?
    var subtasks: [SubtaskItem]
    var tagIds: [String]
    var dueAt: String?
    var repeatRule: RepeatRule?
    var attachments: [String]?
    var rank: Double
    var completedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64
    var deleted: Bool?
    var stamps: [String: Int64]?

    var isDeleted: Bool { deleted == true }
    var isDone: Bool { status == .done }
    var isFlagged: Bool { flagged == true }
    var effectiveListID: String {
        if let listId, !listId.isEmpty { return listId }
        return TaskListItem.defaultID
    }
    var effectiveParentID: String? {
        guard let parentId, !parentId.isEmpty else { return nil }
        return parentId
    }
    var isSubtask: Bool { effectiveParentID != nil }
    var taskPriority: TaskPriority { TaskPriority(rawValue: priority ?? 0) ?? .none }
    var cleanURL: String { (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var activeRepeat: RepeatRule { repeatRule ?? .none }
    var attachmentList: [String] { attachments ?? [] }

    var checklistDoneCount: Int { subtasks.filter(\.done).count }
    var checklistTotalCount: Int { subtasks.count }
}

struct TagItem: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var label: String
    var hue: TagHue
    var order: Int
    var updatedAt: Int64
    var deleted: Bool?

    var isDeleted: Bool { deleted == true }
}

struct BoardState: Codable {
    var tasks: [TaskItem]
    var tags: [TagItem]
    var lists: [TaskListItem]?
    var seeded: Bool
}

struct DiscoveredPeer: Codable, Identifiable, Equatable {
    var deviceId: String
    var deviceName: String
    var ip: String
    var httpPort: Int
    var lastSeenMs: Int64

    var id: String { deviceId }
}

struct PairedPeer: Codable, Identifiable, Equatable {
    var deviceId: String
    var deviceName: String
    var lastSyncAt: Int64 = 0
    var lastIp: String = ""
    var lastPort: Int = 8787
    var online: Bool = false

    var id: String { deviceId }
}

struct SyncStatus: Codable, Equatable {
    var running: Bool = false
    var deviceId: String = ""
    var deviceName: String = "Mac 桌面端"
    var address: String = ""
    var httpPort: Int = 8787
    var activePairingCode: String?
    var pairingExpiresAt: Int64?
    var pairedPeers: [PairedPeer] = []
    var discoveredPeers: [DiscoveredPeer] = []
    var syncedAt: Int64 = 0
    var lastError: String?
}

struct SyncEvent: Codable {
    var type: String
    var tasks: [TaskItem]?
    var tags: [TagItem]?
    var lists: [TaskListItem]?
    var status: SyncStatus?
    var at: Int64?
}

enum NavSection: Hashable {
    case today
    case scheduled
    case all
    case flagged
    case completed
    case list(String)
    case allTags
    case tag(String)
}

enum DateHelper {
    private static let dueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseDue(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        return dueFormatter.date(from: str)
    }

    static func formatDue(_ date: Date) -> String {
        dueFormatter.string(from: date)
    }

    static func todayDayNumber() -> Int {
        Calendar.current.component(.day, from: Date())
    }

    static func presetDate(daysOffset: Int, hour: Int, minute: Int = 0) -> String {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: daysOffset, to: Date()) ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour
        comps.minute = minute
        let date = cal.date(from: comps) ?? base
        return formatDue(date)
    }

    static func isOverdue(_ dueAt: String?) -> Bool {
        guard let d = parseDue(dueAt) else { return false }
        return d < Date()
    }

    static func isDueToday(_ dueAt: String?) -> Bool {
        guard let d = parseDue(dueAt) else { return false }
        return Calendar.current.isDateInToday(d)
    }

    static func isCompletedToday(_ completedAt: Int64?) -> Bool {
        guard let ms = completedAt, ms > 0 else { return false }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        return Calendar.current.isDateInToday(date)
    }

    static func dueBadge(_ dueAt: String?, settled: Bool = false) -> (text: String, tone: DueTone)? {
        guard let d = parseDue(dueAt) else { return nil }
        let cal = Calendar.current
        let timeStr = String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
        let now = Date()
        let late = !settled && d < now

        let dayStr: String
        if cal.isDateInToday(d) {
            dayStr = "今天"
        } else if cal.isDateInTomorrow(d) {
            dayStr = "明天"
        } else if cal.isDateInYesterday(d) {
            dayStr = "昨天"
        } else {
            let month = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            let year = cal.component(.year, from: d)
            let curYear = cal.component(.year, from: now)
            dayStr = year == curYear ? "\(month)月\(day)日" : "\(year)年\(month)月\(day)日"
        }

        if late {
            return ("\(dayStr) \(timeStr)", .late)
        }
        if !settled && cal.isDateInToday(d) {
            return ("今天 \(timeStr)", .soon)
        }
        return ("\(dayStr) \(timeStr)", .normal)
    }

    private static let logbookFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func logbookGroupTitle(for ms: Int64?) -> String {
        guard let ms, ms > 0 else { return "更早" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return logbookFormatter.string(from: date)
    }

    static func extractURLs(from text: String) -> [URL] {
        guard let detector = linkDetector, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var urls: [URL] = []
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let url = match?.url, !seen.contains(url.absoluteString) {
                seen.insert(url.absoluteString)
                urls.append(url)
            }
        }
        return urls
    }

    static func upcomingGroupTitle(for dueAt: String?) -> String {
        guard let d = parseDue(dueAt) else { return "未定日期" }
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfDue = cal.startOfDay(for: d)
        let month = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        let wds = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let wd = wds[cal.component(.weekday, from: d) - 1]
        if startOfDue < startOfToday {
            return "已逾期"
        }
        if cal.isDateInToday(d) {
            return "今天 · \(month)月\(day)日"
        }
        if cal.isDateInTomorrow(d) {
            return "明天 · \(month)月\(day)日"
        }
        if let weekLater = cal.date(byAdding: .day, value: 7, to: startOfToday), startOfDue < weekLater {
            return "\(wd) · \(month)月\(day)日"
        }
        let year = cal.component(.year, from: d)
        let curYear = cal.component(.year, from: now)
        return year == curYear ? "\(month)月\(day)日 · \(wd)" : "\(year)年\(month)月\(day)日"
    }
}

enum DueTone {
    case normal
    case soon
    case late
}
