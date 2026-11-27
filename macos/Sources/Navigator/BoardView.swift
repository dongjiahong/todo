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
                accent: .secondary,
                tasks: store.todoTasks,
                store: store
            )

            BoardColumn(
                title: "进行中",
                status: .doing,
                accent: Color.accentColor,
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
                                onComplete: { store.toggleComplete(id: task.id) }
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
                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onComplete) {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1.4)
                        .frame(width: 15, height: 15)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)

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
            }

            HStack(spacing: 8) {
                if let badge = DateHelper.dueBadge(task.dueAt) {
                    Text(badge.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(badge.tone == .late ? .red : (badge.tone == .soon ? .orange : .secondary))
                        .monospacedDigit()
                }
                if task.checklistTotalCount > 0 {
                    Label("\(task.checklistDoneCount)/\(task.checklistTotalCount)", systemImage: "checklist")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                ForEach(task.tagIds.compactMap { id in tags.first { $0.id == id } }) { tag in
                    HStack(spacing: 4) {
                        Circle().fill(tag.hue.color).frame(width: 6, height: 6)
                        Text(tag.label).font(.system(size: 11, weight: .medium)).foregroundStyle(tag.hue.color)
                    }
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
