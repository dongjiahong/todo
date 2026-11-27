import Foundation
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case doing
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "待办"
        case .doing: return "进行中"
        case .done: return "已完成"
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
        switch self {
        case .blue: return Color(red: 0.20, green: 0.48, blue: 0.88)
        case .green: return Color(red: 0.16, green: 0.62, blue: 0.42)
        case .purple: return Color(red: 0.52, green: 0.36, blue: 0.84)
        case .amber: return Color(red: 0.78, green: 0.50, blue: 0.12)
        case .red: return Color(red: 0.84, green: 0.28, blue: 0.26)
        }
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

struct TaskItem: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var notes: String
    var status: TaskStatus
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
    var seeded: Bool
}

struct PeerStatus: Codable, Identifiable, Equatable {
    var addr: String
    var ok: Bool
    var at: Int64
    var typed: Bool
    var pair: String
    var retry: Int64

    var id: String { addr }
}

struct SyncStatus: Codable, Equatable {
    var listening: Bool = false
    var address: String = ""
    var pairCode: String?
    var peers: [PeerStatus] = []
    var unreachable: Bool = false
    var syncedAt: Int64 = 0
    var pair: String = "ok"
    var retry: Int64 = 0
}

struct SyncEvent: Codable {
    var type: String
    var tasks: [TaskItem]?
    var tags: [TagItem]?
    var status: SyncStatus?
    var at: Int64?
}

enum NavSection: Hashable {
    case today
    case doing
    case todo
    case upcoming
    case logbook
    case tag(String)
}

enum ViewMode: String, CaseIterable {
    case list
    case board
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

    static func todayPrefix() -> String {
        dayFormatter.string(from: Date())
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
            return ("已逾期 · \(dayStr) \(timeStr)", .late)
        }
        if !settled && cal.isDateInToday(d) {
            return ("今天 \(timeStr)", .soon)
        }
        return ("\(dayStr) \(timeStr)", .normal)
    }

    static func logbookGroupTitle(for ms: Int64?) -> String {
        guard let ms, ms > 0 else { return "更早" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }

    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
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
}

enum DueTone {
    case normal
    case soon
    case late
}
