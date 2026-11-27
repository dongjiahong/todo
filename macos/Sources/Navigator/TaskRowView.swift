import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let tags: [TagItem]
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleComplete: () -> Void
    let onToggleDoing: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Instant completion circle
            Button(action: onToggleComplete) {
                ZStack {
                    if task.isDone {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.62, blue: 0.42))
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(
                                task.status == .doing ? Color.accentColor : Color.secondary.opacity(0.55),
                                lineWidth: 1.5
                            )
                            .frame(width: 17, height: 17)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(task.title.isEmpty ? "未命名任务" : task.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .strikethrough(task.isDone, color: .secondary)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    if hovering && !task.isDone {
                        Button(action: onToggleDoing) {
                            Image(systemName: task.status == .doing ? "flame.fill" : "flame")
                                .font(.system(size: 12))
                                .foregroundStyle(task.status == .doing ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(task.status == .doing ? "移回待办" : "标记为进行中")
                    }
                }

                if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.notes.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if hasMeta {
                    HStack(spacing: 10) {
                        if task.status == .doing && !task.isDone {
                            Label("进行中", systemImage: "flame.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }

                        if let badge = DateHelper.dueBadge(task.dueAt, settled: task.isDone) {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                Text(badge.text)
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, badge.tone == .normal ? 0 : 6)
                            .padding(.vertical, badge.tone == .normal ? 0 : 2)
                            .background(dueBg(badge.tone), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(dueFg(badge.tone))
                        }

                        if task.activeRepeat != .none {
                            Image(systemName: "repeat")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }

                        if task.checklistTotalCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 10.5))
                                Text("\(task.checklistDoneCount)/\(task.checklistTotalCount)")
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                        }

                        if !task.attachmentList.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "photo")
                                    .font(.system(size: 10))
                                if task.attachmentList.count > 1 {
                                    Text("\(task.attachmentList.count)")
                                        .font(.system(size: 11))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }

                        ForEach(resolvedTags) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(tag.hue.color)
                                    .frame(width: 6, height: 6)
                                Text(tag.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tag.hue.color)
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.11) : (hovering ? Color.primary.opacity(0.035) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(task.isDone ? "标记为未完成" : "标记为已完成", action: onToggleComplete)
            if !task.isDone {
                Button(task.status == .doing ? "移回待办" : "移入进行中", action: onToggleDoing)
            }
            Divider()
            Button("删除任务", role: .destructive, action: onDelete)
        }
    }

    private var resolvedTags: [TagItem] {
        task.tagIds.compactMap { id in tags.first { $0.id == id } }
    }

    private var hasMeta: Bool {
        (task.status == .doing && !task.isDone) ||
        task.dueAt != nil ||
        task.checklistTotalCount > 0 ||
        !task.attachmentList.isEmpty ||
        !resolvedTags.isEmpty
    }

    private func dueFg(_ tone: DueTone) -> Color {
        switch tone {
        case .late: return Color(red: 0.84, green: 0.26, blue: 0.24)
        case .soon: return Color(red: 0.78, green: 0.48, blue: 0.10)
        case .normal: return .secondary
        }
    }

    private func dueBg(_ tone: DueTone) -> Color {
        switch tone {
        case .late: return Color(red: 0.84, green: 0.26, blue: 0.24).opacity(0.12)
        case .soon: return Color(red: 0.86, green: 0.56, blue: 0.12).opacity(0.13)
        case .normal: return .clear
        }
    }
}
