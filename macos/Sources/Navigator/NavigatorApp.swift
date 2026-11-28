import AppKit
import SwiftUI

@main
struct NavigatorApp: App {
    @State private var store = NavigatorStore()

    var body: some Scene {
        WindowGroup("TODO") {
            ContentView(store: store)
                .frame(minWidth: 740, minHeight: 520)
                .preferredColorScheme(store.appearance.colorScheme)
                .onAppear {
                    store.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    store.openSettings(tab: .general)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("新建提醒事项") {
                    _ = store.createInlineTask()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("新建列表…") {
                    store.showAddListSheet = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("搜索") {
                    store.focusSearchTrigger += 1
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("命令面板") {
                    store.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("粘贴图片到当前提醒") {
                    guard let id = store.editingTaskID ?? store.inspectorTaskID else { return }
                    let pb = NSPasteboard.general
                    if let png = pb.data(forType: .png) {
                        store.attachImage(to: id, data: png, ext: "png")
                    } else if let tiff = pb.data(forType: .tiff),
                              let rep = NSBitmapImageRep(data: tiff),
                              let png = rep.representation(using: .png, properties: [:]) {
                        store.attachImage(to: id, data: png, ext: "png")
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("导出为 Markdown（复制到剪贴板）") {
                    store.copyMarkdownExport()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

struct ContentView: View {
    @Bindable var store: NavigatorStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 255)
        } detail: {
            mainDetailArea
                .background(Color(nsColor: .textBackgroundColor))
        }
        .overlay(alignment: .bottom) {
            if let undo = store.undoBanner {
                HStack(spacing: 12) {
                    Text(undo.message)
                        .font(.system(size: 13, weight: .medium))
                    Button("撤销") {
                        store.triggerUndo()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button {
                        store.dismissUndo()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $store.showAddListSheet) {
            AddListSheet(store: store, editing: nil)
        }
        .sheet(item: $store.editingList) { list in
            AddListSheet(store: store, editing: list)
        }
        .sheet(isPresented: $store.showTagManager) {
            TagManagerView(store: store)
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView(store: store)
        }
        .sheet(isPresented: $store.showCommandPalette) {
            CommandPaletteView(store: store)
        }
        .sheet(isPresented: Binding(
            get: { store.previewImagePath != nil },
            set: { if !$0 { store.previewImagePath = nil } }
        )) {
            if let path = store.previewImagePath, let img = NSImage(contentsOfFile: path) {
                ImageLightboxView(image: img, filePath: path) {
                    store.previewImagePath = nil
                }
            }
        }
    }

    // MARK: - Main Right Pane (Apple Reminders style)

    @ViewBuilder
    private var mainDetailArea: some View {
        VStack(spacing: 0) {
            // Compact top-right "+" button bar
            HStack {
                Spacer()
                if !store.isSearching && store.section != .completed {
                    Button {
                        _ = store.createInlineTask()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("新建提醒事项 (⌘N)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 5)

            // Compact Colored Header Title + Count
            HStack(alignment: .firstTextBaseline) {
                Text(store.isSearching ? "搜索「\(store.searchQuery)」" : sectionTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(store.isSearching ? .primary : sectionTitleColor)

                Spacer()

                if !store.isSearching, let rightCount = headerRightCount {
                    Text("\(rightCount)")
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(sectionTitleColor.opacity(0.85))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 5)

            // Completed Counter Bar ("N 项完成 • 清除" | "显示 / 隐藏")
            if !store.isSearching && (store.completedCountForCurrentSection > 0 || store.section == .completed) {
                HStack(spacing: 5) {
                    Text("\(store.completedCountForCurrentSection) 项完成")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if store.completedCountForCurrentSection > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Button("清除") {
                            store.clearCompletedForCurrentSection()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if store.section != .completed && store.completedCountForCurrentSection > 0 {
                        Button(store.showCompletedInSection ? "隐藏" : "显示") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.showCompletedInSection.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                Divider()
                    .padding(.horizontal, 16)
            } else {
                Divider()
                    .padding(.horizontal, 16)
            }

            // Main Scrollable Reminder Stream
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.isSearching {
                        searchResultsStream
                    } else {
                        switch store.section {
                        case .all:
                            allGroupedStream
                        case .today:
                            flatStream(tasks: store.todayTasks, listID: nil, accent: NavTheme.accentBlue, showListBadge: true)
                        case .scheduled:
                            scheduledStream
                        case .flagged:
                            flatStream(tasks: store.flaggedTasks, listID: nil, accent: NavTheme.flaggedOrange, showListBadge: true)
                        case .completed:
                            completedStream
                        case .list(let listID):
                            let list = store.list(for: listID)
                            flatStream(tasks: store.activeTasks(in: listID), listID: listID, accent: list.swiftUIColor, showListBadge: false)
                        case .allTags:
                            flatStream(tasks: store.allTaggedActiveTasks(), listID: nil, accent: NavTheme.accentBlue, showListBadge: true)
                        case .tag(let tagID):
                            let tagColor = store.liveTags.first(where: { $0.id == tagID })?.hue.color ?? NavTheme.accentBlue
                            flatStream(tasks: store.activeTasks(forTag: tagID), listID: nil, accent: tagColor, showListBadge: true)
                        }

                        if store.section != .completed && store.showCompletedInSection {
                            let doneItems = store.completedTasksForCurrentSection
                            if !doneItems.isEmpty {
                                Text("已完成")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 16)
                                    .padding(.bottom, 4)
                                ForEach(doneItems) { task in
                                    TaskRowView(
                                        task: task,
                                        store: store,
                                        accentTint: store.list(for: task.effectiveListID).swiftUIColor,
                                        showListBadge: store.section != .list(task.effectiveListID)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Section Streams

    @ViewBuilder
    private var allGroupedStream: some View {
        ForEach(store.liveLists) { list in
            let listTasks = store.activeTasks(in: list.id)
            VStack(alignment: .leading, spacing: 0) {
                Text(list.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(list.swiftUIColor)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                ForEach(listTasks) { task in
                    TaskRowView(task: task, store: store, accentTint: list.swiftUIColor, showListBadge: false)
                }

                PhantomTaskRow {
                    _ = store.createInlineTask(in: list.id)
                }

                Divider()
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var scheduledStream: some View {
        let items = store.scheduledTasks
        let grouped = Dictionary(grouping: items) { DateHelper.upcomingGroupTitle(for: $0.dueAt) }
        let orderedKeys = items.reduce(into: [String]()) { acc, item in
            let k = DateHelper.upcomingGroupTitle(for: item.dueAt)
            if !acc.contains(k) { acc.append(k) }
        }
        if orderedKeys.isEmpty {
            PhantomTaskRow {
                _ = store.createInlineTask(dueAt: DateHelper.presetDate(daysOffset: 0, hour: 18))
            }
        } else {
            ForEach(orderedKeys, id: \.self) { day in
                Text(day)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(day == "已逾期" ? NavTheme.danger : .primary)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                ForEach(grouped[day] ?? []) { task in
                    TaskRowView(
                        task: task,
                        store: store,
                        accentTint: store.list(for: task.effectiveListID).swiftUIColor,
                        showListBadge: true
                    )
                }
            }
            PhantomTaskRow {
                _ = store.createInlineTask(dueAt: DateHelper.presetDate(daysOffset: 0, hour: 18))
            }
        }
    }

    @ViewBuilder
    private var completedStream: some View {
        let items = store.completedTasks
        let grouped = Dictionary(grouping: items) { DateHelper.logbookGroupTitle(for: $0.completedAt) }
        let orderedKeys = items.reduce(into: [String]()) { acc, item in
            let k = DateHelper.logbookGroupTitle(for: item.completedAt)
            if !acc.contains(k) { acc.append(k) }
        }
        if orderedKeys.isEmpty {
            Text("暂无已完成的提醒事项")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
        } else {
            ForEach(orderedKeys, id: \.self) { day in
                Text(day)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                ForEach(grouped[day] ?? []) { task in
                    TaskRowView(
                        task: task,
                        store: store,
                        accentTint: store.list(for: task.effectiveListID).swiftUIColor,
                        showListBadge: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func flatStream(tasks: [TaskItem], listID: String?, accent: Color, showListBadge: Bool) -> some View {
        ForEach(tasks) { task in
            TaskRowView(
                task: task,
                store: store,
                accentTint: listID == nil ? store.list(for: task.effectiveListID).swiftUIColor : accent,
                showListBadge: showListBadge
            )
        }
        PhantomTaskRow {
            _ = store.createInlineTask(in: listID)
        }
    }

    @ViewBuilder
    private var searchResultsStream: some View {
        let results = store.globalSearchResults
        if results.isEmpty {
            Text("没有找到匹配「\(store.searchQuery)」的提醒事项")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
        } else {
            ForEach(results) { task in
                TaskRowView(
                    task: task,
                    store: store,
                    accentTint: store.list(for: task.effectiveListID).swiftUIColor,
                    showListBadge: true
                )
            }
        }
    }

    // MARK: - Section Metadata

    private var sectionTitle: String {
        switch store.section {
        case .today: return "今天"
        case .scheduled: return "计划"
        case .all: return "全部"
        case .flagged: return "旗标"
        case .completed: return "完成"
        case .list(let id): return store.list(for: id).name
        case .allTags: return "所有标签"
        case .tag(let id):
            let lbl = store.liveTags.first(where: { $0.id == id })?.label ?? "标签"
            return "#\(lbl)"
        }
    }

    private var sectionTitleColor: Color {
        switch store.section {
        case .today: return NavTheme.accentBlue
        case .scheduled: return NavTheme.scheduledRed
        case .all: return .primary
        case .flagged: return NavTheme.flaggedOrange
        case .completed: return NavTheme.completedGray
        case .list(let id): return store.list(for: id).swiftUIColor
        case .allTags: return .primary
        case .tag(let id): return store.liveTags.first(where: { $0.id == id })?.hue.color ?? NavTheme.accentBlue
        }
    }

    private var headerRightCount: Int? {
        switch store.section {
        case .all, .completed: return nil
        case .today: return store.todayCount
        case .scheduled: return store.scheduledCount
        case .flagged: return store.flaggedCount
        case .list(let id): return store.activeTasks(in: id).count
        case .allTags: return store.allTaggedActiveTasks().count
        case .tag(let id): return store.activeTasks(forTag: id).count
        }
    }
}

// MARK: - Command Palette (⌘K)

private struct PaletteEntry: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcut: String
    let group: String
    let action: () -> Void
}

struct CommandPaletteView: View {
    @Bindable var store: NavigatorStore
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var hoveredID: String?
    @FocusState private var focused: Bool

    private var entries: [PaletteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list: [PaletteEntry] = [
            PaletteEntry(id: "cmd_new", title: "新建提醒事项", icon: "plus.circle", shortcut: "⌘N", group: "快捷操作") {
                store.showCommandPalette = false
                _ = store.createInlineTask()
            },
            PaletteEntry(id: "cmd_new_list", title: "添加新列表", icon: "folder.badge.plus", shortcut: "⌘L", group: "快捷操作") {
                store.showCommandPalette = false
                store.showAddListSheet = true
            },
            PaletteEntry(id: "cmd_settings", title: "打开设置（含局域网同步）", icon: "gearshape", shortcut: "⌘,", group: "快捷操作") {
                store.showCommandPalette = false
                store.openSettings(tab: .general)
            },
            PaletteEntry(id: "cmd_sync", title: "立即同步", icon: "arrow.triangle.2.circlepath", shortcut: "", group: "快捷操作") {
                store.syncNow()
                store.showCommandPalette = false
            }
        ]
        if !q.isEmpty {
            list = list.filter { $0.title.lowercased().contains(q) }
        }
        let tasks: [TaskItem] = q.isEmpty
            ? Array(store.liveTasks.filter { !$0.isDone }.prefix(6))
            : Array(store.liveTasks.filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) }.prefix(8))
        for task in tasks {
            list.append(PaletteEntry(
                id: "task_\(task.id)",
                title: task.title.isEmpty ? "未命名提醒" : task.title,
                icon: task.isDone ? "checkmark.circle.fill" : "circle",
                shortcut: store.list(for: task.effectiveListID).name,
                group: "提醒事项"
            ) {
                store.section = .list(task.effectiveListID)
                store.editingTaskID = task.id
                store.showCommandPalette = false
            })
        }
        return list
    }

    var body: some View {
        let items = entries
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("跳转提醒事项、列表或执行命令…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit {
                        if items.indices.contains(selectedIndex) {
                            items[selectedIndex].action()
                        }
                    }
                Button("Esc") { store.showCommandPalette = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if items.isEmpty {
                        Text("没有匹配的命令或提醒事项")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, entry in
                            if idx == 0 || items[idx - 1].group != entry.group {
                                Text(entry.group)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, idx == 0 ? 6 : 10)
                                    .padding(.bottom, 2)
                            }
                            let isHighlighted = idx == selectedIndex || hoveredID == entry.id
                            Button(action: entry.action) {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(isHighlighted ? NavTheme.accentBlue : .secondary)
                                        .frame(width: 18)
                                    Text(entry.title)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Spacer()
                                    if !entry.shortcut.isEmpty {
                                        Text(entry.shortcut)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isHighlighted ? NavTheme.accentBlue.opacity(0.12) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { over in
                                hoveredID = over ? entry.id : nil
                                if over { selectedIndex = idx }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 480, height: 380)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onKeyPress(.downArrow) {
            if !items.isEmpty { selectedIndex = (selectedIndex + 1) % items.count }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if !items.isEmpty { selectedIndex = (selectedIndex - 1 + items.count) % items.count }
            return .handled
        }
        .onKeyPress(.escape) {
            store.showCommandPalette = false
            return .handled
        }
    }
}

// MARK: - Zoomable Image Lightbox

struct ImageLightboxView: View {
    let image: NSImage
    let filePath: String
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.92)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    let next = min(max(lastScale * value.magnification, 1.0), 5.0)
                                    scale = next
                                    if next <= 1.01 {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1.01 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if scale > 1.2 {
                                    resetZoom()
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                }
            }

            HStack(spacing: 12) {
                Button {
                    zoom(by: -0.5)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(scale <= 1.01)

                Button("\(Int(scale * 100))%") {
                    withAnimation(.easeInOut(duration: 0.16)) { resetZoom() }
                }
                .buttonStyle(.borderless)
                .monospacedDigit()
                .frame(minWidth: 46)

                Button {
                    zoom(by: 0.5)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(scale >= 5.0)

                Divider()
                    .frame(height: 16)

                Button("用预览打开") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                }
                .controlSize(.small)

                Spacer()

                Text("双击放大 · 滚轮/双指缩放 · 拖拽移动")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("关闭") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 920, minHeight: 500, idealHeight: 680)
        .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in
            zoom(by: 0.5)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-")) { _ in
            zoom(by: -0.5)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "0")) { _ in
            withAnimation(.easeInOut(duration: 0.16)) { resetZoom() }
            return .handled
        }
    }

    private func zoom(by delta: CGFloat) {
        withAnimation(.easeInOut(duration: 0.15)) {
            let next = min(max(scale + delta, 1.0), 5.0)
            scale = next
            lastScale = next
            if next <= 1.01 {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Tag Manager Sheet

struct TagManagerView: View {
    @Bindable var store: NavigatorStore
    @State private var draftLabel: String = ""
    @State private var draftHue: TagHue = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("管理标签")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("完成") { store.showTagManager = false }
            }

            VStack(spacing: 8) {
                ForEach(store.liveTags) { tag in
                    HStack(spacing: 8) {
                        Button {
                            var copy = tag
                            copy.hue = tag.hue.next
                            store.updateTag(copy)
                        } label: {
                            Circle().fill(tag.hue.color).frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .help("点击切换颜色")

                        TextField("", text: Binding(
                            get: { tag.label },
                            set: { val in
                                var copy = tag
                                copy.label = val
                                store.updateTag(copy)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button(role: .destructive) {
                            store.deleteTag(id: tag.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    draftHue = draftHue.next
                } label: {
                    Circle().fill(draftHue.color).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                TextField("新标签名称", text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.createTag(label: draftLabel, hue: draftHue)
                        draftLabel = ""
                    }

                Button("添加") {
                    store.createTag(label: draftLabel, hue: draftHue)
                    draftLabel = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
