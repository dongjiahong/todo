import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating Apple Reminders-style `(i)` Inspector Popover.
struct TaskInspectorPopover: View {
    let taskID: String
    @Bindable var store: NavigatorStore

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var urlText: String = ""
    @State private var showDatePicker: Bool = false
    @State private var pickerDate: Date = Date()
    @State private var showTagPicker: Bool = false

    private var task: TaskItem? {
        store.liveTasks.first { $0.id == taskID }
    }

    var body: some View {
        if let task {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header: Title + Flag toggle button (matching screenshot top-right button)
                    HStack(alignment: .top, spacing: 8) {
                        TextField("提醒事项标题", text: $title, axis: .vertical)
                            .font(.system(size: 15, weight: .semibold))
                            .textFieldStyle(.plain)
                            .onChange(of: title) { _, val in
                                store.debouncedPatchTask(id: taskID) { t, now in
                                    t.title = val
                                    t.stamps?["title"] = now
                                }
                            }

                        Button {
                            store.toggleFlag(id: taskID)
                        } label: {
                            Image(systemName: task.isFlagged ? "flag.fill" : "flag")
                                .font(.system(size: 13))
                                .foregroundStyle(task.isFlagged ? .white : .secondary)
                                .frame(width: 34, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(task.isFlagged ? NavTheme.flaggedOrange : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(task.isFlagged ? "取消旗标" : "添加旗标")
                    }

                    TextField("备注", text: $notes, axis: .vertical)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .onChange(of: notes) { _, val in
                            store.debouncedPatchTask(id: taskID) { t, now in
                                t.notes = val
                                t.stamps?["notes"] = now
                            }
                        }

                    Divider()

                    // Tags section
                    VStack(alignment: .leading, spacing: 6) {
                        let taskTags = task.tagIds.compactMap { id in store.liveTags.first { $0.id == id } }
                        if taskTags.isEmpty {
                            Button {
                                showTagPicker.toggle()
                            } label: {
                                Text("添加标签")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            FlowLayout(spacing: 5) {
                                ForEach(taskTags) { tag in
                                    TagPillView(tag: tag, selected: true, interactive: true) {
                                        toggleTag(tag.id)
                                    }
                                }
                                Button {
                                    showTagPicker.toggle()
                                } label: {
                                    Text("+ 标签")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if showTagPicker && !store.liveTags.isEmpty {
                            FlowLayout(spacing: 5) {
                                ForEach(store.liveTags) { tag in
                                    let on = task.tagIds.contains(tag.id)
                                    TagPillView(tag: tag, selected: on, interactive: true) {
                                        toggleTag(tag.id)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }

                    Divider()

                    // 提醒我 (指定日期 & 重复)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("提醒我")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("指定日期", isOn: Binding(
                                    get: { task.dueAt != nil && !task.dueAt!.isEmpty },
                                    set: { enabled in
                                        if enabled {
                                            let defaultDue = DateHelper.presetDate(daysOffset: 0, hour: 18)
                                            pickerDate = DateHelper.parseDue(defaultDue) ?? Date()
                                            store.patchTask(id: taskID) { t, now in
                                                t.dueAt = defaultDue
                                                t.stamps?["dueAt"] = now
                                            }
                                        } else {
                                            store.patchTask(id: taskID) { t, now in
                                                t.dueAt = nil
                                                t.repeatRule = RepeatRule.none
                                                t.stamps?["dueAt"] = now
                                                t.stamps?["repeatRule"] = now
                                            }
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12.5))

                                if task.dueAt != nil && !task.dueAt!.isEmpty {
                                    DatePicker(
                                        "",
                                        selection: $pickerDate,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .onChange(of: pickerDate) { _, d in
                                        let formatted = DateHelper.formatDue(d)
                                        store.patchTask(id: taskID) { t, now in
                                            t.dueAt = formatted
                                            t.stamps?["dueAt"] = now
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text("重复")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Picker("", selection: Binding(
                                            get: { task.activeRepeat },
                                            set: { rule in
                                                store.patchTask(id: taskID) { t, now in
                                                    t.repeatRule = rule
                                                    t.stamps?["repeatRule"] = now
                                                }
                                            }
                                        )) {
                                            ForEach(RepeatRule.allCases) { r in
                                                Text(r.label).tag(r)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 96)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // 优先级 & 列表
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("优先级")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)

                            Picker("", selection: Binding(
                                get: { task.taskPriority },
                                set: { p in store.setPriority(id: taskID, priority: p) }
                            )) {
                                ForEach(TaskPriority.allCases) { p in
                                    Text(p.label).tag(p)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 10) {
                            Text("列表")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)

                            Picker("", selection: Binding(
                                get: { task.effectiveListID },
                                set: { listID in store.moveTaskToList(id: taskID, listID: listID) }
                            )) {
                                ForEach(store.liveLists) { list in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(list.swiftUIColor)
                                            .frame(width: 8, height: 8)
                                        Text(list.name)
                                    }
                                    .tag(list.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()

                    // URL & 图像
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("URL")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)

                            TextField("无", text: $urlText)
                                .font(.system(size: 12.5))
                                .textFieldStyle(.plain)
                                .onChange(of: urlText) { _, val in
                                    store.debouncedPatchTask(id: taskID) { t, now in
                                        t.url = val.trimmingCharacters(in: .whitespacesAndNewlines)
                                        t.stamps?["url"] = now
                                    }
                                }

                            if !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               let u = URL(string: urlText.contains("://") ? urlText : "https://\(urlText)") {
                                Link(destination: u) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 12))
                                        .foregroundStyle(NavTheme.accentBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Text("图像")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Button {
                                        pickImageFromDisk()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 12))
                                            Text("添加图像…")
                                                .font(.system(size: 12.5))
                                        }
                                        .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        pasteImageFromClipboard()
                                    } label: {
                                        Text("粘贴")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(NavTheme.accentBlue)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if !task.attachmentList.isEmpty {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 6) {
                                        ForEach(task.attachmentList, id: \.self) { name in
                                            if let url = store.assetURL(for: name), let img = NSImage(contentsOf: url) {
                                                ZStack(alignment: .topTrailing) {
                                                    Image(nsImage: img)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 56, height: 56)
                                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                        .onTapGesture {
                                                            store.previewImagePath = url.path
                                                        }
                                                    Button {
                                                        store.removeAttachment(from: taskID, name: name)
                                                    } label: {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .font(.system(size: 13))
                                                            .foregroundStyle(.white, .black.opacity(0.65))
                                                    }
                                                    .buttonStyle(.plain)
                                                    .offset(x: 3, y: -3)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            store.deleteTask(id: taskID)
                        } label: {
                            Label("删除提醒事项", systemImage: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NavTheme.danger)
                    }
                }
                .padding(14)
            }
            .frame(width: 300)
            .frame(maxHeight: 480)
            .background(Color(nsColor: .textBackgroundColor))
            .presentationBackground(Color(nsColor: .textBackgroundColor))
            .onAppear { syncDrafts(from: task) }
            .onChange(of: task.id) { _, _ in syncDrafts(from: task) }
        }
    }

    private func syncDrafts(from task: TaskItem) {
        title = task.title
        notes = task.notes
        urlText = task.cleanURL
        if let d = DateHelper.parseDue(task.dueAt) {
            pickerDate = d
        }
    }

    private func toggleTag(_ tagID: String) {
        store.patchTask(id: taskID, rescheduleNotifications: false) { t, now in
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
            store.attachImage(to: taskID, data: data, ext: ext)
        }
    }

    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png) {
            store.attachImage(to: taskID, data: png, ext: "png")
            return
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            store.attachImage(to: taskID, data: png, ext: "png")
        }
    }
}
