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
        HStack(alignment: .top, spacing: 8) {
            TaskCheckbox(
                checked: task.isDone,
                isDoing: task.status == .doing,
                onToggle: onToggleComplete
            )
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
                                .foregroundStyle(task.status == .doing ? NavTheme.doingBlue : .secondary)
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
                    FlowLayout(spacing: 6) {
                        if task.status == .doing && !task.isDone {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10))
                                Text("进行中")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NavTheme.doingBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .foregroundStyle(NavTheme.doingBlue)
                        }

                        if let badge = DateHelper.dueBadge(task.dueAt, settled: task.isDone) {
                            DueBadgeView(
                                text: badge.text,
                                tone: badge.tone,
                                repeating: task.activeRepeat != .none
                            )
                        }

                        if task.checklistTotalCount > 0 {
                            HStack(spacing: 4) {
                                MiniProgressRing(done: task.checklistDoneCount, total: task.checklistTotalCount)
                                Text("\(task.checklistDoneCount)/\(task.checklistTotalCount)")
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
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
                            .padding(.vertical, 2)
                        }

                        ForEach(resolvedTags) { tag in
                            TagPillView(tag: tag)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? NavTheme.accentBlue.opacity(0.11) : (hovering ? Color.primary.opacity(0.035) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? NavTheme.accentBlue.opacity(0.32) : Color.clear, lineWidth: 1)
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
}
