import SwiftUI

/// Focused 2-column Kanban board: ONLY "待办" and "进行中".
/// Completed work flows into the Logbook instead of wasting half the horizontal space.
struct BoardView: View {
    @Bindable var store: NavigatorStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            BoardColumn(
                title: "待办",
                status: .todo,
                accent: NavTheme.inboxBlue,
                tasks: store.todoTasks,
                store: store
            )

            BoardColumn(
                title: "进行中",
                status: .doing,
                accent: NavTheme.doingBlue,
                tasks: store.doingTasks,
                store: store
            )
        }
        .padding(16)
    }
}

private struct BoardColumn: View {
    let title: String
    let status: TaskStatus
    let accent: Color
    let tasks: [TaskItem]
    @Bindable var store: NavigatorStore

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text("\(tasks.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button {
                    _ = store.createTask(title: "", status: status)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("在「\(title)」新建任务")
            }
            .padding(.horizontal, 6)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if tasks.isEmpty {
                        Text("把任务拖到这里")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ForEach(tasks) { task in
                            BoardCard(
                                task: task,
                                tags: store.liveTags,
                                isSelected: store.selectedTaskID == task.id,
                                onSelect: { store.selectedTaskID = task.id },
                                onComplete: { store.toggleComplete(id: task.id) },
                                onToggleDoing: { store.moveTask(id: task.id, to: task.status == .doing ? .todo : .doing) },
                                onDelete: { store.deleteTask(id: task.id) }
                            )
                            .draggable(task.id)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? NavTheme.accentBlue.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDropTargeted ? NavTheme.accentBlue.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            store.moveTask(id: id, to: status)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}

private struct BoardCard: View {
    let task: TaskItem
    let tags: [TagItem]
    let isSelected: Bool
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onToggleDoing: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var resolvedTags: [TagItem] {
        task.tagIds.compactMap { id in tags.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                TaskCheckbox(
                    checked: task.isDone,
                    isDoing: task.status == .doing,
                    size: 16,
                    onToggle: onComplete
                )
                .padding(.top, -2)

                Text(task.title.isEmpty ? "未命名任务" : task.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }

            if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(task.notes.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 30)
            }

            if task.dueAt != nil || task.checklistTotalCount > 0 || !task.attachmentList.isEmpty || !resolvedTags.isEmpty {
                FlowLayout(spacing: 6) {
                    if let badge = DateHelper.dueBadge(task.dueAt) {
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
                        TagPillView(tag: tag)
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.09 : 0.05), radius: hovering ? 4 : 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? NavTheme.accentBlue : (hovering ? Color.primary.opacity(0.14) : Color.primary.opacity(0.06)),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("标记为已完成", action: onComplete)
            Button(task.status == .doing ? "移回待办" : "移入进行中", action: onToggleDoing)
            Divider()
            Button("删除任务", role: .destructive, action: onDelete)
        }
    }
}
