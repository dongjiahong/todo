import SwiftUI

struct SidebarView: View {
    @Bindable var store: NavigatorStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.section) {
                Section("聚焦") {
                    SidebarRow(
                        title: "今天",
                        icon: "star.fill",
                        tint: NavTheme.todayGold,
                        badge: store.attentionCount
                    )
                    .tag(NavSection.today)

                    SidebarRow(
                        title: "进行中",
                        icon: "flame.fill",
                        tint: NavTheme.doingBlue,
                        badge: store.doingCount
                    )
                    .tag(NavSection.doing)

                    SidebarRow(
                        title: "待办",
                        icon: "tray.fill",
                        tint: NavTheme.inboxBlue,
                        badge: store.todoCount
                    )
                    .tag(NavSection.todo)

                    SidebarRow(
                        title: "计划",
                        icon: "calendar",
                        tint: NavTheme.upcomingCoral,
                        badge: 0
                    )
                    .tag(NavSection.upcoming)
                }

                Section {
                    ForEach(store.liveTags) { tag in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tag.hue.color)
                                .frame(width: 8, height: 8)
                            Text(tag.label)
                                .font(.system(size: 13))
                            Spacer()
                            let count = store.tasksForTag(tag.id).count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                        .tag(NavSection.tag(tag.id))
                    }
                } header: {
                    HStack {
                        Text("标签")
                        Spacer()
                        Button {
                            store.showTagManager = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("管理标签")
                    }
                }

                Section("归档历史") {
                    SidebarRow(
                        title: "日志簿",
                        icon: "book.closed.fill",
                        tint: NavTheme.logbookGreen,
                        badge: 0
                    )
                    .tag(NavSection.logbook)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Minimal bottom bar: sync status indicator only + Settings gear
            HStack(spacing: 8) {
                Button {
                    store.openSettings(tab: .sync)
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(syncDotColor)
                            .frame(width: 7, height: 7)
                        Text(syncStatusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看局域网同步设置")

                Spacer()

                Button {
                    store.openSettings(tab: .general)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("设置 (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var syncDotColor: Color {
        if store.syncStatus.syncedAt > 0 {
            return NavTheme.logbookGreen
        }
        return store.syncStatus.listening ? NavTheme.accentBlue : .gray
    }

    private var syncStatusText: String {
        if store.syncStatus.syncedAt > 0 {
            return "已同步"
        }
        return store.syncStatus.listening ? "等待同步" : "离线"
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let tint: Color
    let badge: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
