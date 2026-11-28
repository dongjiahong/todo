import SwiftUI

struct SidebarView: View {
    @Bindable var store: NavigatorStore
    @FocusState private var searchFocused: Bool

    private let gridColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Compact Top Search Bar
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onExitCommand {
                        store.searchQuery = ""
                        searchFocused = false
                    }
                if store.isSearching {
                    Button {
                        store.searchQuery = ""
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 9)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Compact 2-Column Smart List Grid
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        SmartListCard(
                            title: "今天",
                            count: store.todayCount,
                            tint: NavTheme.accentBlue,
                            selected: !store.isSearching && store.section == .today,
                            customBadgeText: "\(DateHelper.todayDayNumber())",
                            icon: "calendar"
                        ) {
                            selectSection(.today)
                        }

                        SmartListCard(
                            title: "计划",
                            count: store.scheduledCount,
                            tint: NavTheme.scheduledRed,
                            selected: !store.isSearching && store.section == .scheduled,
                            icon: "calendar"
                        ) {
                            selectSection(.scheduled)
                        }

                        SmartListCard(
                            title: "全部",
                            count: store.allActiveCount,
                            tint: NavTheme.allDark,
                            selected: !store.isSearching && store.section == .all,
                            icon: "tray.fill"
                        ) {
                            selectSection(.all)
                        }

                        SmartListCard(
                            title: "旗标",
                            count: store.flaggedCount,
                            tint: NavTheme.flaggedOrange,
                            selected: !store.isSearching && store.section == .flagged,
                            icon: "flag.fill"
                        ) {
                            selectSection(.flagged)
                        }

                        SmartListCard(
                            title: "完成",
                            count: nil,
                            tint: NavTheme.completedGray,
                            selected: !store.isSearching && store.section == .completed,
                            icon: "checkmark"
                        ) {
                            selectSection(.completed)
                        }
                    }
                    .padding(.horizontal, 10)

                    // 我的列表
                    VStack(alignment: .leading, spacing: 3) {
                        Text("我的列表")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 1)

                        VStack(spacing: 1) {
                            ForEach(store.liveLists) { list in
                                let isSelected = !store.isSearching && store.section == .list(list.id)
                                let count = store.activeTasks(in: list.id).count
                                Button {
                                    selectSection(.list(list.id))
                                } label: {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(list.swiftUIColor)
                                                .frame(width: 20, height: 20)
                                            Image(systemName: list.symbolName)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }

                                        Text(list.name)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text("\(count)")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? NavTheme.accentBlue : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("编辑列表…") {
                                        store.editingList = list
                                    }
                                    if store.liveLists.count > 1 {
                                        Divider()
                                        Button("删除列表", role: .destructive) {
                                            store.deleteList(id: list.id)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    // 标签
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("标签")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.showTagManager = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("管理标签")
                        }
                        .padding(.horizontal, 16)

                        FlowLayout(spacing: 6) {
                            SidebarTagChip(
                                title: "所有标签",
                                selected: !store.isSearching && store.section == .allTags
                            ) {
                                selectSection(.allTags)
                            }

                            ForEach(store.liveTags) { tag in
                                SidebarTagChip(
                                    title: "#\(tag.label)",
                                    selected: !store.isSearching && store.section == .tag(tag.id)
                                ) {
                                    selectSection(.tag(tag.id))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 16)
            }

            Divider()

            // Bottom Bar: + 添加列表 (left) + Sync dot & Settings (right)
            HStack(spacing: 8) {
                Button {
                    store.showAddListSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13.5))
                        Text("添加列表")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    store.openSettings(tab: .sync)
                } label: {
                    Circle()
                        .fill(syncDotColor)
                        .frame(width: 7, height: 7)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(syncTooltip)

                Button {
                    store.openSettings(tab: .general)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("设置 (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .onChange(of: store.focusSearchTrigger) { _, _ in
            searchFocused = true
        }
    }

    private func selectSection(_ next: NavSection) {
        if let editingID = store.editingTaskID {
            store.commitInlineEditIfEmpty(id: editingID)
        }
        store.editingTaskID = nil
        store.inspectorTaskID = nil
        store.searchQuery = ""
        store.section = next
    }

    private var syncDotColor: Color {
        if store.syncStatus.syncedAt > 0 { return NavTheme.logbookGreen }
        return store.syncStatus.listening ? NavTheme.accentBlue : .gray
    }

    private var syncTooltip: String {
        if store.syncStatus.syncedAt > 0 { return "局域网已同步" }
        return store.syncStatus.listening ? "等待局域网同步" : "离线"
    }
}

private struct SmartListCard: View {
    let title: String
    let count: Int?
    let tint: Color
    let selected: Bool
    var customBadgeText: String? = nil
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    ZStack {
                        Circle()
                            .fill(selected ? Color.white : tint)
                            .frame(width: 21, height: 21)
                        if let day = customBadgeText {
                            Text(day)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(selected ? tint : .white)
                                .monospacedDigit()
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(selected ? tint : .white)
                        }
                    }

                    Spacer()

                    if let count {
                        Text("\(count)")
                            .font(.system(size: 16.5, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .white : .primary)
                            .monospacedDigit()
                    }
                }

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(selected ? .white : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? tint : Color.primary.opacity(0.065))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarTagChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? .white : .primary.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? NavTheme.accentBlue : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
