import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskRowView: View {
    let task: TaskItem
    @Bindable var store: NavigatorStore
    var accentTint: Color = NavTheme.accentBlue
    var showListBadge: Bool = false

    @State private var hovered = false
    @State private var showDuePopover = false
    @State private var showTagPopover = false
    @State private var showImagePopover = false
    @State private var draftTitle: String = ""
    @State private var draftNotes: String = ""
    @FocusState private var titleFocused: Bool

    private var isEditing: Bool {
        store.editingTaskID == task.id
    }

    private var isInspectorOpen: Bool {
        store.inspectorTaskID == task.id
    }

    private var taskTags: [TagItem] {
        task.tagIds.compactMap { id in store.liveTags.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                TaskCheckbox(
                    checked: task.isDone,
                    tint: accentTint,
                    size: 15.5,
                    onToggle: { store.toggleComplete(id: task.id) }
                )
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    if isEditing {
                        inlineEditorContent
                    } else {
                        readOnlyContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right-side indicators: Flag + (i) Inspector button
                HStack(spacing: 5) {
                    if task.isFlagged && !isEditing {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(NavTheme.flaggedOrange)
                    }

                    if isEditing || hovered || isInspectorOpen {
                        Button {
                            store.editingTaskID = task.id
                            store.inspectorTaskID = isInspectorOpen ? nil : task.id
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13.5))
                                .foregroundStyle(isEditing || isInspectorOpen ? NavTheme.flaggedOrange : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("检查器详情")
                        .popover(
                            isPresented: Binding(
                                get: { store.inspectorTaskID == task.id },
                                set: { if !$0 && store.inspectorTaskID == task.id { store.inspectorTaskID = nil } }
                            ),
                            arrowEdge: .trailing
                        ) {
                            TaskInspectorPopover(taskID: task.id, store: store)
                        }
                    }
                }
                .padding(.top, 1.5)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isEditing {
                    if let prev = store.editingTaskID, prev != task.id {
                        store.commitInlineEditIfEmpty(id: prev)
                    }
                    draftTitle = task.title
                    draftNotes = task.notes
                    store.editingTaskID = task.id
                }
            }

            Divider()
                .padding(.leading, 26)
        }
        .onHover { hovered = $0 }
        .onAppear {
            draftTitle = task.title
            draftNotes = task.notes
            if isEditing && task.title.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    titleFocused = true
                }
            }
        }
        .onChange(of: isEditing) { _, nowEditing in
            if nowEditing {
                draftTitle = task.title
                draftNotes = task.notes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    titleFocused = true
                }
            }
        }
        .onChange(of: task.title) { _, newVal in
            if !isEditing { draftTitle = newVal }
        }
        .onChange(of: task.notes) { _, newVal in
            if !isEditing { draftNotes = newVal }
        }
        .contextMenu {
            Button(task.isDone ? "标记为未完成" : "标记为已完成") {
                store.toggleComplete(id: task.id)
            }
            Button(task.isFlagged ? "取消旗标" : "添加旗标") {
                store.toggleFlag(id: task.id)
            }
            Button("粘贴剪贴板图片") {
                pasteImageFromClipboard()
            }
            Button("添加图片文件…") {
                pickImageFromDisk()
            }
            Button("检查器详情…") {
                store.editingTaskID = task.id
                store.inspectorTaskID = task.id
            }
            Menu("移动到列表") {
                ForEach(store.liveLists) { list in
                    Button(list.name) {
                        store.moveTaskToList(id: task.id, listID: list.id)
                    }
                }
            }
            Menu("优先级") {
                ForEach(TaskPriority.allCases) { p in
                    Button(p.label) {
                        store.setPriority(id: task.id, priority: p)
                    }
                }
            }
            Divider()
            Button("删除提醒事项", role: .destructive) {
                store.deleteTask(id: task.id)
            }
        }
    }

    // MARK: - Read-only compact row (with inline image thumbnails directly under notes)

    @ViewBuilder
    private var readOnlyContent: some View {
        HStack(spacing: 4) {
            if task.taskPriority != .none {
                Text(task.taskPriority.bangPrefix)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(accentTint)
            }
            Text(task.title.isEmpty ? "新建提醒事项" : task.title)
                .font(.system(size: 13.5))
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .strikethrough(task.isDone, color: .secondary.opacity(0.6))
        }

        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesWithClickableLinks(task.notes)
        }

        // Inline image thumbnails right inside the notes area — 1 click to preview!
        if !task.attachmentList.isEmpty {
            inlineThumbnailsStrip(editable: false)
                .padding(.top, 4)
        }

        if !task.cleanURL.isEmpty, let url = normalizedURL(task.cleanURL) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                        .font(.system(size: 10.5))
                    Text(task.cleanURL)
                        .font(.system(size: 12))
                        .underline()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(NavTheme.accentBlue)
            }
            .buttonStyle(.plain)
        }

        let badge = DateHelper.dueBadge(task.dueAt, settled: task.isDone)
        let hasMeta = badge != nil
            || !taskTags.isEmpty
            || task.checklistTotalCount > 0
            || showListBadge

        if hasMeta {
            FlowLayout(spacing: 6) {
                if let badge {
                    DueBadgeView(text: badge.text, tone: badge.tone, repeating: task.activeRepeat != .none)
                }

                if showListBadge {
                    let list = store.list(for: task.effectiveListID)
                    HStack(spacing: 4) {
                        Circle().fill(list.swiftUIColor).frame(width: 6, height: 6)
                        Text(list.name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(taskTags) { tag in
                    Text("#\(tag.label)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tag.hue.color)
                }

                if task.checklistTotalCount > 0 {
                    HStack(spacing: 4) {
                        MiniProgressRing(done: task.checklistDoneCount, total: task.checklistTotalCount)
                        Text("\(task.checklistDoneCount)/\(task.checklistTotalCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Inline Expanded Editor (multi-line notes + inline images + quick chips)

    @ViewBuilder
    private var inlineEditorContent: some View {
        HStack(spacing: 4) {
            if task.taskPriority != .none {
                Text(task.taskPriority.bangPrefix)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(accentTint)
            }
            TextField("新提醒事项", text: $draftTitle)
                .font(.system(size: 13.5))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onChange(of: draftTitle) { _, val in
                    store.debouncedPatchTask(id: task.id) { t, now in
                        t.title = val
                        t.stamps?["title"] = now
                    }
                }
                .onSubmit {
                    if draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.commitInlineEditIfEmpty(id: task.id)
                    } else {
                        _ = store.createInlineTask(in: task.effectiveListID)
                    }
                }
                .onExitCommand {
                    store.commitInlineEditIfEmpty(id: task.id)
                    store.editingTaskID = nil
                }
        }

        // Multi-line Notes field (supports Shift+Return / Enter wrapping, 2...10 lines)
        TextField("备注（支持多行，点击下方图像可贴图）", text: $draftNotes, axis: .vertical)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .textFieldStyle(.plain)
            .lineLimit(2...10)
            .onChange(of: draftNotes) { _, val in
                store.debouncedPatchTask(id: task.id) { t, now in
                    t.notes = val
                    t.stamps?["notes"] = now
                }
            }

        // Inline image thumbnails right under notes during editing (with delete & quick preview)
        if !task.attachmentList.isEmpty {
            inlineThumbnailsStrip(editable: true)
                .padding(.top, 4)
        }

        // Inline tags row ("添加标签" or existing #tags)
        if taskTags.isEmpty {
            Button {
                showTagPopover.toggle()
            } label: {
                Text("添加标签")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        } else {
            FlowLayout(spacing: 5) {
                ForEach(taskTags) { tag in
                    TagPillView(tag: tag, selected: true, interactive: true) {
                        toggleTag(tag.id)
                    }
                }
            }
            .padding(.top, 2)
        }

        // Quick Action Chips Row ([添加日期] [#] [旗标] [图像])
        HStack(spacing: 6) {
            Button {
                showDuePopover.toggle()
            } label: {
                let badge = DateHelper.dueBadge(task.dueAt, settled: task.isDone)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10.5))
                    Text(badge?.text ?? "添加日期")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(badge != nil ? NavTheme.accentBlue.opacity(0.12) : Color.primary.opacity(0.055))
                )
                .foregroundStyle(badge?.tone == .late ? NavTheme.danger : (badge != nil ? NavTheme.accentBlue : .secondary))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDuePopover, arrowEdge: .bottom) {
                DueDatePopover(
                    currentDue: task.dueAt,
                    currentRepeat: task.activeRepeat,
                    onApply: { newDue, newRepeat in
                        store.patchTask(id: task.id) { t, now in
                            t.dueAt = newDue
                            t.repeatRule = newDue == nil ? RepeatRule.none : newRepeat
                            t.stamps?["dueAt"] = now
                            t.stamps?["repeatRule"] = now
                        }
                    },
                    onDismiss: { showDuePopover = false }
                )
                .background(Color(nsColor: .textBackgroundColor))
                .presentationBackground(Color(nsColor: .textBackgroundColor))
            }

            Button {
                showTagPopover.toggle()
            } label: {
                Text("#")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                    )
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
                inlineTagPopover
                    .background(Color(nsColor: .textBackgroundColor))
                    .presentationBackground(Color(nsColor: .textBackgroundColor))
            }

            Button {
                store.toggleFlag(id: task.id)
            } label: {
                Image(systemName: task.isFlagged ? "flag.fill" : "flag")
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(task.isFlagged ? NavTheme.flaggedOrange.opacity(0.16) : Color.primary.opacity(0.055))
                    )
                    .foregroundStyle(task.isFlagged ? NavTheme.flaggedOrange : .secondary)
            }
            .buttonStyle(.plain)
            .help(task.isFlagged ? "取消旗标" : "添加旗标")

            Button {
                showImagePopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 10.5))
                    Text(task.attachmentList.isEmpty ? "图像" : "图像 \(task.attachmentList.count)")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(task.attachmentList.isEmpty ? Color.primary.opacity(0.055) : NavTheme.accentBlue.opacity(0.12))
                )
                .foregroundStyle(task.attachmentList.isEmpty ? .secondary : NavTheme.accentBlue)
            }
            .buttonStyle(.plain)
            .help("粘贴或选择图片（也可按 ⇧⌘V 快速贴图）")
            .popover(isPresented: $showImagePopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        showImagePopover = false
                        pasteImageFromClipboard()
                    } label: {
                        Label("粘贴剪贴板图片 (⇧⌘V)", systemImage: "doc.on.clipboard")
                            .font(.system(size: 12.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        showImagePopover = false
                        pickImageFromDisk()
                    } label: {
                        Label("从本地选择图片…", systemImage: "photo.on.rectangle")
                            .font(.system(size: 12.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(width: 195)
                .background(Color(nsColor: .textBackgroundColor))
                .presentationBackground(Color(nsColor: .textBackgroundColor))
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func inlineThumbnailsStrip(editable: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(task.attachmentList, id: \.self) { name in
                    if let url = store.assetURL(for: name), let img = NSImage(contentsOf: url) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                                .onTapGesture {
                                    store.previewImagePath = url.path
                                }

                            if editable {
                                Button {
                                    store.removeAttachment(from: task.id, name: name)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white, .black.opacity(0.65))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 3, y: -3)
                            }
                        }
                        .padding(.top, editable ? 3 : 0)
                        .padding(.trailing, editable ? 3 : 0)
                    }
                }
            }
        }
    }

    private var inlineTagPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择标签")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if store.liveTags.isEmpty {
                Text("暂无标签")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(store.liveTags) { tag in
                        let on = task.tagIds.contains(tag.id)
                        TagPillView(tag: tag, selected: on, interactive: true) {
                            toggleTag(tag.id)
                        }
                    }
                }
            }
            Divider()
            Button("管理标签…") {
                showTagPopover = false
                store.showTagManager = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(NavTheme.accentBlue)
        }
        .padding(12)
        .frame(width: 240)
    }

    private func toggleTag(_ tagID: String) {
        store.patchTask(id: task.id, rescheduleNotifications: false) { t, now in
            if t.tagIds.contains(tagID) {
                t.tagIds.removeAll { $0 == tagID }
            } else {
                t.tagIds.append(tagID)
            }
            t.stamps?["tagIds"] = now
        }
    }

    private func pickImageFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            store.attachImage(to: task.id, data: data, ext: ext)
        }
    }

    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png) {
            store.attachImage(to: task.id, data: png, ext: "png")
            return
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            store.attachImage(to: task.id, data: png, ext: "png")
            return
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first,
           let data = try? Data(contentsOf: first) {
            let ext = first.pathExtension.isEmpty ? "png" : first.pathExtension.lowercased()
            store.attachImage(to: task.id, data: data, ext: ext)
        }
    }

    @ViewBuilder
    private func notesWithClickableLinks(_ text: String) -> some View {
        let lines = text.components(separatedBy: .newlines)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let url = URL(string: trimmed),
                   let scheme = url.scheme?.lowercased(),
                   (scheme == "http" || scheme == "https") {
                    Link(destination: url) {
                        Text(trimmed)
                            .font(.system(size: 12.5))
                            .foregroundStyle(NavTheme.accentBlue)
                            .underline()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(line)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
    }

    private func normalizedURL(_ raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil { return url }
        return URL(string: "https://\(raw)")
    }
}

/// Dotted empty circle row at the bottom of every list/section (click to spawn inline reminder).
struct PhantomTaskRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 15.5, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(width: 19, height: 19)
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
