import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: NavigatorStore
    @State private var copiedAddress = false
    @State private var copiedCode = false
    @State private var manualAddr = ""
    @State private var peerCode = ""
    @State private var statusFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TODO 设置")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    store.showSettings = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            TabView(selection: $store.settingsTab) {
                generalTab
                    .tabItem { Label("通用与通知", systemImage: "bell.badge") }
                    .tag(SettingsTab.general)

                syncTab
                    .tabItem { Label("局域网同步", systemImage: "wifi") }
                    .tag(SettingsTab.sync)

                dataTab
                    .tabItem { Label("数据与备份", systemImage: "externaldrive") }
                    .tag(SettingsTab.data)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 520, height: 470)
        .onAppear {
            store.refreshNotificationStatus()
        }
    }

    private var generalTab: some View {
        Form {
            Section("系统通知权限与提醒") {
                HStack {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(notificationDotColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("通知权限状态：\(store.notificationState.label)")
                                .font(.system(size: 13, weight: .medium))
                            Text("开启后，即使退出 TODO，到期任务也会准时弹窗并支持一键完成或推迟。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if store.notificationState == .unknown {
                        Button("请求授权") {
                            store.requestNotificationPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if store.notificationState == .denied {
                        Button("系统设置") {
                            store.openSystemNotificationSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if store.notificationState == .authorized {
                        Button("发送测试") {
                            store.sendTestNotification()
                        }
                        .controlSize(.small)
                    }
                }

                Picker("提前提醒", selection: $store.leadReminderMinutes) {
                    Text("仅准点提醒").tag(0)
                    Text("提前 15 分钟").tag(15)
                    Text("提前 30 分钟").tag(30)
                    Text("提前 1 小时").tag(60)
                }
            }

            Section("外观") {
                Picker("主题模式", selection: $store.appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("快捷键") {
                shortcutRow("快速新建任务", keys: "⌘ N")
                shortcutRow("聚焦全局搜索", keys: "⌘ F")
                shortcutRow("打开命令面板", keys: "⌘ K")
                shortcutRow("打开设置", keys: "⌘ ,")
                shortcutRow("导出 Markdown", keys: "⇧ ⌘ E")
            }

            Section("关于") {
                LabeledContent("应用名称", value: "TODO")
                LabeledContent("版本", value: "0.3.0 (Native SwiftUI + Go Core)")
            }
        }
        .formStyle(.grouped)
    }

    private var notificationDotColor: Color {
        switch store.notificationState {
        case .authorized: return NavTheme.logbookGreen
        case .denied: return NavTheme.danger
        case .unknown: return NavTheme.todayGold
        case .unsupported: return .gray
        }
    }

    private var syncTab: some View {
        Form {
            Section("本机配对信息（供 Android 连接）") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("6 位配对码")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        let code = store.syncStatus.pairCode ?? "------"
                        Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    Button(copiedCode ? "已复制" : "复制") {
                        if let code = store.syncStatus.pairCode {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            copiedCode = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedCode = false }
                        }
                    }
                    .controlSize(.small)

                    Button("换一个") {
                        store.regeneratePairCode()
                    }
                    .controlSize(.small)
                }

                if !store.syncStatus.address.isEmpty {
                    HStack {
                        LabeledContent("本机局域网地址") {
                            Text(store.syncStatus.address)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Button(copiedAddress ? "已复制" : "复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.syncStatus.address, forType: .string)
                            copiedAddress = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedAddress = false }
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("已发现设备") {
                if store.syncStatus.peers.isEmpty {
                    HStack {
                        Text("同一 Wi-Fi 下会自动发现其他设备")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即同步") {
                            store.syncNow()
                        }
                        .controlSize(.small)
                    }
                } else {
                    ForEach(store.syncStatus.peers) { peer in
                        HStack {
                            Circle()
                                .fill(peer.ok ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(peer.addr)
                                .font(.system(size: 12.5, design: .monospaced))
                            Spacer()
                            Text(peer.ok ? "已同步" : (peer.pair == "wrong" ? "配对码错误" : "未连接"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("立即同步") { store.syncNow() }
                            .controlSize(.small)
                    }
                }
            }

            Section("连接另一台 Mac（可选）") {
                HStack(spacing: 8) {
                    TextField("对方地址 (如 192.168.1.5:8787)", text: $manualAddr)
                    TextField("6 位码", text: $peerCode)
                        .frame(width: 76)
                    Button("连接") {
                        store.connectManualPeer(address: manualAddr, code: peerCode)
                        statusFeedback = "已触发连接，正在同步…"
                    }
                    .disabled(peerCode.filter(\.isNumber).count != 6)
                }
                if let msg = statusFeedback {
                    Text(msg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            Section("导出与导入") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导出为 Markdown")
                        Text("包含所有进行中、待办与日志簿任务及子任务")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("复制到剪贴板") {
                        store.copyMarkdownExport()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("从剪贴板导入 JSON")
                        Text("按字段级时间戳安全合并，不会覆盖更新的记录")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("导入") {
                        if let raw = NSPasteboard.general.string(forType: .string), !raw.isEmpty {
                            store.importJSON(raw)
                        }
                    }
                }
            }

            Section("本地存储") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SQLite 数据库与每日快照")
                        Text(store.dataDirPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("在访达中打开") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: store.dataDirPath))
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
