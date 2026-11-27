import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Non-blocking right-side Inspector panel.
/// First-class structured subtasks + clean native Notes editor (zero dual-layer hacks).
struct TaskDetailView: View {
    let taskID: String
    @Bindable var store: NavigatorStore

    @State private var newSubtaskTitle: String = ""
    @State private var showDuePopover: Bool = false
    @State private var showImageImporter: Bool = false
    @State private var keyMonitor: Any?

    private var task: TaskItem? {
        store.liveTasks.first { $0.id == taskID }
    }

    var body: some View {
        if let task {
            VStack(spacing: 0) {
                // Top action strip
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { task.status },
                        set: { store.moveTask(id: task.id, to: $0) }
                    )) {
                        ForEach(TaskStatus.allCases) { st in
                            Text(st.label).tag(st)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)

                    Spacer()

                    Button {
                        if !pasteImageFromClipboard(taskID: task.id) {
                            showImageImporter = true
                        }
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("粘贴剪贴板图片 (⌘V) 或选择图片")

                    Button(role: .destructive) {
                        store.deleteTask(id: task.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("删除任务（可撤销）")

                    Button {
                        store.selectedTaskID = nil
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("关闭详情")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        TextField(
                            "要做什么？",
                            text: Binding(
                                get: { task.title },
                                set: { val in
                                    store.debouncedPatchTask(id: task.id) { t, now in
                                        t.title = val
                                        t.stamps?["title"] = now
                                    }
                                }
                            ),
                            axis: .vertical
                        )
                        .font(.system(size: 19, weight: .semibold))
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)

                        // Due & Repeat compact pill (opens bespoke DueDatePopover)
                        HStack(spacing: 8) {
                            Button {
                                showDuePopover.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11.5))
                                    Text(DateHelper.dueBadge(task.dueAt, settled: task.isDone)?.text ?? "设置截止时间")
                                        .font(.system(size: 12, weight: .medium))
                                        .monospacedDigit()
                                    if task.activeRepeat != .none {
                                        Text("· \(task.activeRepeat.label)")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
                            }

                            if task.dueAt != nil && store.notificationState != .authorized {
                                Button {
                                    if store.notificationState == .denied {
                                        store.openSystemNotificationSettings()
                                    } else {
                                        store.requestNotificationPermission()
                                    }
                                } label: {
                                    Label(
                                        store.notificationState == .denied ? "通知被拒，去开启" : "开启到期通知",
                                        systemImage: "bell.badge"
                                    )
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(NavTheme.todayGold)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Tags row
                        FlowLayout(spacing: 6) {
                            ForEach(store.liveTags) { tag in
                                let selected = task.tagIds.contains(tag.id)
                                TagPillView(tag: tag, selected: selected, interactive: true) {
                                    store.patchTask(id: task.id, rescheduleNotifications: false) { t, now in
                                        if selected {
                                            t.tagIds.removeAll { $0 == tag.id }
                                        } else {
                                            t.tagIds.append(tag.id)
                                        }
                                        t.stamps?["tagIds"] = now
                                    }
                                }
                            }
                        }

                        Divider()

                        // First-class Structured Subtasks Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("子任务")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                if task.checklistTotalCount > 0 {
                                    Text("\(task.checklistDoneCount)/\(task.checklistTotalCount)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                                Spacer()
                            }

                            ForEach(task.subtasks) { sub in
                                HStack(spacing: 4) {
                                    TaskCheckbox(
                                        checked: sub.done,
                                        isCircular: true,
                                        size: 14,
                                        onToggle: { store.toggleSubtask(taskID: task.id, subtaskID: sub.id) }
                                    )

                                    TextField(
                                        "子任务内容",
                                        text: Binding(
                                            get: { sub.title },
                                            set: { store.updateSubtaskTitle(taskID: task.id, subtaskID: sub.id, title: $0) }
                                        )
                                    )
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .foregroundStyle(sub.done ? .secondary : .primary)
                                    .strikethrough(sub.done)

                                    Button {
                                        store.deleteSubtask(taskID: task.id, subtaskID: sub.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 1)
                            }

                            // Inline quick add subtask
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                TextField("添加子任务，回车确认…", text: $newSubtaskTitle)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .onSubmit {
                                        store.addSubtask(to: task.id, title: newSubtaskTitle)
                                        newSubtaskTitle = ""
                                    }
                            }
                            .padding(.top, 2)
                        }

                        Divider()

                        // Clean Native Notes Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ZStack(alignment: .topLeading) {
                                if task.notes.isEmpty {
                                    Text("补充细节、背景或链接…")
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 5)
                                        .padding(.leading, 4)
                                }
                                TextEditor(text: Binding(
                                    get: { task.notes },
                                    set: { val in
                                        store.debouncedPatchTask(id: task.id) { t, now in
                                            t.notes = val
                                            t.stamps?["notes"] = now
                                        }
                                    }
                                ))
                                .font(.system(size: 13.5))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 140)
                            }

                            // Auto-detected clickable links
                            let urls = DateHelper.extractURLs(from: task.notes)
                            if !urls.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(urls, id: \.absoluteString) { url in
                                        Link(destination: url) {
                                            HStack(spacing: 5) {
                                                Image(systemName: "link")
                                                    .font(.system(size: 11))
                                                Text(url.absoluteString)
                                                    .font(.system(size: 12))
                                                    .lineLimit(1)
                                            }
                                            .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }

                        // Attachments strip
                        if !task.attachmentList.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("图片附件")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(task.attachmentList, id: \.self) { name in
                                            if let url = store.assetURL(for: name) {
                                                AttachmentThumbView(
                                                    url: url,
                                                    onTap: { store.previewImagePath = url.path },
                                                    onRemove: { store.removeAttachment(from: task.id, name: name) }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .fileImporter(
                isPresented: $showImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first,
                   let data = try? Data(contentsOf: url) {
                    store.attachImage(to: task.id, data: data, ext: url.pathExtension.isEmpty ? "png" : url.pathExtension)
                }
            }
            .onAppear {
                installPasteMonitor()
            }
            .onDisappear {
                removePasteMonitor()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("选择一张任务查看详情")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func installPasteMonitor() {
        removePasteMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v" else {
                return event
            }
            let targetID = store.selectedTaskID ?? taskID
            if pasteImageFromClipboard(taskID: targetID, allowWhenTextPresent: false) {
                return nil
            }
            return event
        }
    }

    private func removePasteMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    @discardableResult
    private func pasteImageFromClipboard(taskID: String, allowWhenTextPresent: Bool = true) -> Bool {
        let pb = NSPasteboard.general
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "gif", "tiff", "bmp"]

        // When invoked via ⌘V while clipboard also contains plain text (e.g. rich copy from browser),
        // let the focused text field handle normal text paste instead of hijacking it.
        if !allowWhenTextPresent,
           let str = pb.string(forType: .string),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fileURLs = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            let hasImageFiles = fileURLs.contains { imageExts.contains($0.pathExtension.lowercased()) }
            if !hasImageFiles {
                return false
            }
        }

        // 1. Direct image data (screenshots, browser "Copy Image", Snapzy, etc.)
        if let pngData = pb.data(forType: .png), !pngData.isEmpty {
            store.attachImage(to: taskID, data: pngData, ext: "png")
            return true
        }
        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let png = rep.representation(using: .png, properties: [:]) {
            store.attachImage(to: taskID, data: png, ext: "png")
            return true
        }

        // 2. Copied image file URL(s) from Finder
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let imgURLs = urls.filter { imageExts.contains($0.pathExtension.lowercased()) }
            if !imgURLs.isEmpty {
                for url in imgURLs {
                    if let data = try? Data(contentsOf: url), !data.isEmpty {
                        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
                        store.attachImage(to: taskID, data: data, ext: ext)
                    }
                }
                return true
            }
        }

        return false
    }
}

/// Simple horizontal wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 128
    }

    func thumbnail(for url: URL, maxPixelSize: Int = 180) -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key)
        return img
    }
}

private struct AttachmentThumbView: View {
    let url: URL
    let onTap: () -> Void
    let onRemove: () -> Void

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: onTap)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .task(id: url) {
            let targetURL = url
            let loaded = await Task.detached(priority: .utility) {
                ThumbnailCache.shared.thumbnail(for: targetURL)
            }.value
            self.image = loaded
        }
    }
}
