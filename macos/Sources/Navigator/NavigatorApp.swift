import AppKit
import SwiftUI

@main
struct NavigatorApp: App {
    @State private var store = NavigatorStore()

    var body: some Scene {
        WindowGroup("TODO") {
            ContentView(store: store)
                .frame(minWidth: 880, minHeight: 560)
                .preferredColorScheme(store.appearance.colorScheme)
                .onAppear {
                    store.bootstrap()
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    store.openSettings(tab: .general)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("新建任务") {
                    store.showQuickCapture = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("全局搜索") {
                    store.focusSearchTrigger += 1
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("命令面板") {
                    store.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

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
    @State private var showTodayCompleted = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 250)
        } content: {
            VStack(spacing: 0) {
                inlineSearchBar
                Divider()
                mainWorkspace
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 500)
        } detail: {
            if let id = store.selectedTaskID {
                TaskDetailView(taskID: id, store: store)
                    .id(id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("选择任务查看详情，或按 ⌘N 快速新建")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: store.focusSearchTrigger) { _, _ in
            searchFocused = true
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.section != .logbook && !store.isSearching {
                    Picker("视图", selection: $store.viewMode) {
                        Image(systemName: "list.bullet").tag(ViewMode.list)
                        Image(systemName: "rectangle.split.2x1").tag(ViewMode.board)
                    }
                    .pickerStyle(.segmented)
                    .help("切换聚焦列表 / 精简双列看板")
                }

                Button {
                    store.showQuickCapture = true
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .help("新建任务 (⌘N)")
            }
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
        .sheet(isPresented: $store.showQuickCapture) {
            QuickCaptureView(store: store)
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
                VStack {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                    Button("关闭") { store.previewImagePath = nil }
                        .padding(.bottom, 12)
                }
                .frame(minWidth: 520, minHeight: 420)
            }
        }
    }

    private var inlineSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5))
                .foregroundStyle(searchFocused ? Color.accentColor : .secondary)

            TextField("全局搜索标题、备注、子任务或标签…", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand {
                    store.searchQuery = ""
                    searchFocused = false
                }

            if store.isSearching {
                Text("\(store.globalSearchResults.count) 条结果")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    store.searchQuery = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            } else {
                Text("⌘F")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    @ViewBuilder
    private var mainWorkspace: some View {
        if store.isSearching {
            globalSearchView
                .navigationTitle("搜索结果")
        } else if store.viewMode == .board && store.section != .logbook {
            BoardView(store: store)
                .navigationTitle("精简看板")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    switch store.section {
                    case .today:
                        todayView
                    case .doing:
                        flatSection(title: "进行中", tasks: store.doingTasks, empty: "当前没有进行中的任务")
                    case .todo:
                        flatSection(title: "待办", tasks: store.todoTasks, empty: "待办已清空，按 ⌘N 记一笔")
                    case .upcoming:
                        flatSection(title: "计划", tasks: store.upcomingTasks, empty: "没有设置了截止时间的任务")
                    case .logbook:
                        logbookView
                    case .tag(let tagID):
                        let name = store.liveTags.first(where: { $0.id == tagID })?.label ?? "标签"
                        flatSection(title: name, tasks: store.tasksForTag(tagID), empty: "该标签下暂无未完成任务")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .navigationTitle(sectionTitle)
        }
    }

    @ViewBuilder
    private var globalSearchView: some View {
        let all = store.globalSearchResults
        let doing = all.filter { $0.status == .doing }
        let todo = all.filter { $0.status == .todo }
        let done = all.filter { $0.status == .done }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if all.isEmpty {
                    emptyState("没有找到匹配「\(store.searchQuery)」的任务")
                } else {
                    if !doing.isEmpty {
                        sectionHeader("进行中", count: doing.count, tint: Color.accentColor)
                        ForEach(doing) { task in row(task) }
                    }
                    if !todo.isEmpty {
                        sectionHeader("待办", count: todo.count, tint: .primary)
                        ForEach(todo) { task in row(task) }
                    }
                    if !done.isEmpty {
                        sectionHeader("日志簿（已完成）", count: done.count, tint: .secondary)
                        ForEach(done) { task in row(task) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var todayView: some View {
        if !store.todayOverdueTasks.isEmpty {
            sectionHeader("已逾期", count: store.todayOverdueTasks.count, tint: .red)
            ForEach(store.todayOverdueTasks) { task in row(task) }
        }

        sectionHeader("今日聚焦", count: store.todayActiveTasks.count, tint: .primary)
        if store.todayActiveTasks.isEmpty && store.todayOverdueTasks.isEmpty {
            emptyState("今天很清静，没有待处理事项")
        } else {
            ForEach(store.todayActiveTasks) { task in row(task) }
        }

        if !store.todayCompletedTasks.isEmpty {
            DisclosureGroup(isExpanded: $showTodayCompleted) {
                ForEach(store.todayCompletedTasks) { task in row(task) }
            } label: {
                Text("今日已完成 \(store.todayCompletedTasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var logbookView: some View {
        let grouped = Dictionary(grouping: store.logbookTasks) {
            DateHelper.logbookGroupTitle(for: $0.completedAt)
        }
        let orderedKeys = store.logbookTasks.reduce(into: [String]()) { acc, item in
            let k = DateHelper.logbookGroupTitle(for: item.completedAt)
            if !acc.contains(k) { acc.append(k) }
        }
        if orderedKeys.isEmpty {
            emptyState("日志簿还是空的，完成的任务会自动记录在这里")
        } else {
            ForEach(orderedKeys, id: \.self) { day in
                sectionHeader(day, count: grouped[day]?.count ?? 0, tint: .secondary)
                ForEach(grouped[day] ?? []) { task in row(task) }
            }
        }
    }

    @ViewBuilder
    private func flatSection(title: String, tasks: [TaskItem], empty: String) -> some View {
        if tasks.isEmpty {
            emptyState(empty)
        } else {
            ForEach(tasks) { task in row(task) }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRowView(
            task: task,
            tags: store.liveTags,
            isSelected: store.selectedTaskID == task.id,
            onSelect: { store.selectedTaskID = task.id },
            onToggleComplete: { store.toggleComplete(id: task.id) },
            onToggleDoing: { store.moveTask(id: task.id, to: task.status == .doing ? .todo : .doing) },
            onDelete: { store.deleteTask(id: task.id) }
        )
    }

    private func sectionHeader(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 48)
    }

    private var sectionTitle: String {
        switch store.section {
        case .today: return "今天"
        case .doing: return "进行中"
        case .todo: return "待办"
        case .upcoming: return "计划"
        case .logbook: return "日志簿"
        case .tag(let id): return store.liveTags.first(where: { $0.id == id })?.label ?? "标签"
        }
    }
}

// MARK: - Command Palette (⌘K)

struct CommandPaletteView: View {
    @Bindable var store: NavigatorStore
    @State private var query: String = ""
    @FocusState private var focused: Bool

    private var matchedTasks: [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Array(store.liveTasks.filter { !$0.isDone }.prefix(6)) }
        return Array(store.liveTasks.filter {
            $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q)
        }.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("跳转任务、切换视图或执行命令…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                Button("Esc") { store.showCommandPalette = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷操作")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                    paletteButton("新建任务", icon: "plus.circle", shortcut: "⌘N") {
                        store.showCommandPalette = false
                        store.showQuickCapture = true
                    }
                    paletteButton("切换列表 / 双列看板", icon: "rectangle.split.2x1", shortcut: "") {
                        store.viewMode = store.viewMode == .list ? .board : .list
                        store.showCommandPalette = false
                    }
                    paletteButton("打开设置（含局域网同步）", icon: "gearshape", shortcut: "⌘,") {
                        store.showCommandPalette = false
                        store.openSettings(tab: .general)
                    }
                    paletteButton("立即同步", icon: "arrow.triangle.2.circlepath", shortcut: "") {
                        store.syncNow()
                        store.showCommandPalette = false
                    }

                    if !matchedTasks.isEmpty {
                        Text("任务")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)

                        ForEach(matchedTasks) { task in
                            paletteButton(task.title.isEmpty ? "未命名任务" : task.title, icon: task.isDone ? "checkmark.circle.fill" : "circle", shortcut: task.status.label) {
                                store.selectedTaskID = task.id
                                store.showCommandPalette = false
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 480, height: 380)
        .onAppear { focused = true }
    }

    private func paletteButton(_ title: String, icon: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Capture Modal (Cmd+N)

struct QuickCaptureView: View {
    @Bindable var store: NavigatorStore
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var status: TaskStatus = .todo
    @State private var selectedTags: Set<String> = []
    @State private var dueAt: String? = nil
    @State private var keepAdding: Bool = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("要做什么？", text: $title)
                .font(.system(size: 17, weight: .semibold))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit { submit() }

            TextField("补充备注（可选）", text: $notes, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(2...4)

            HStack(spacing: 8) {
                Button(dueAt == nil ? "今天" : (DateHelper.dueBadge(dueAt)?.text ?? "今天")) {
                    dueAt = dueAt == nil ? DateHelper.presetDate(daysOffset: 0, hour: 18) : nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("明天") {
                    dueAt = DateHelper.presetDate(daysOffset: 1, hour: 9)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Picker("", selection: $status) {
                    Text("待办").tag(TaskStatus.todo)
                    Text("进行中").tag(TaskStatus.doing)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Spacer()
            }

            FlowLayout(spacing: 6) {
                ForEach(store.liveTags) { tag in
                    let on = selectedTags.contains(tag.id)
                    Button {
                        if on { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(tag.hue.color).frame(width: 6, height: 6)
                            Text(tag.label).font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(on ? tag.hue.color.opacity(0.16) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Toggle("连续添加", isOn: $keepAdding)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                Spacer()
                Button("取消") { store.showQuickCapture = false }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear { titleFocused = true }
    }

    private func submit() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        _ = store.createTask(
            title: clean,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            tagIds: Array(selectedTags),
            dueAt: dueAt
        )
        title = ""
        notes = ""
        if !keepAdding {
            store.showQuickCapture = false
        } else {
            titleFocused = true
        }
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
