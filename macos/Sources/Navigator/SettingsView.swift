import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: NavigatorStore
    @State private var copiedCode = false
    @State private var pairTarget: DiscoveredPeer?
    @State private var manualIP = ""
    @State private var pairCode = ""
    @State private var busyMsg: String?
    @State private var resultMsg: String?
    @State private var errorMsg: String?

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
        .frame(width: 540, height: 520)
        .onAppear {
            store.refreshNotificationStatus()
            store.refreshSyncStatus()
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

                    HStack(spacing: 6) {
                        if store.notificationState == .unknown {
                            Button("请求授权") {
                                store.requestNotificationPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else if store.notificationState == .authorized {
                            Button("发送测试") {
                                store.sendTestNotification()
                            }
                            .controlSize(.small)
                        }

                        Button("系统设置") {
                            store.openSystemNotificationSettings()
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
                shortcutRow("快速新建提醒", keys: "⌘ N")
                shortcutRow("新建列表", keys: "⌘ L")
                shortcutRow("粘贴图片到当前提醒", keys: "⇧ ⌘ V")
                shortcutRow("聚焦全局搜索", keys: "⌘ F")
                shortcutRow("打开命令面板", keys: "⌘ K")
                shortcutRow("打开设置", keys: "⌘ ,")
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

    // MARK: - TradeFlow-Style Symmetric LAN Sync Tab

    private var syncTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Local Device Card + Generate Pairing Code
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 7) {
                            Image(systemName: "wifi")
                                .foregroundStyle(store.syncStatus.running ? NavTheme.logbookGreen : .secondary)
                            Text("WiFi 局域网同步（macOS ⇄ Android）")
                                .font(.system(size: 13.5, weight: .semibold))
                        }
                        Spacer()
                        Text(store.syncStatus.running ? "UDP + HTTP 运行中" : "未启动")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(store.syncStatus.running ? NavTheme.logbookGreen : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (store.syncStatus.running ? NavTheme.logbookGreen : Color.gray).opacity(0.13),
                                in: Capsule()
                            )
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.syncStatus.deviceName.isEmpty ? "Mac 桌面端" : store.syncStatus.deviceName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(store.syncStatus.address.isEmpty ? "未检测到局域网 IP" : store.syncStatus.address)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            errorMsg = nil
                            store.generatePairingCode()
                        } label: {
                            Label("生成配对码", systemImage: "key.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if let code = store.syncStatus.activePairingCode, !code.isEmpty {
                        HStack {
                            Text("在另一台设备输入 6 位配对码（5 分钟有效）：")
                                .font(.system(size: 11.5))
                                .foregroundStyle(NavTheme.accentBlue)
                            Spacer()
                            Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                            Button(copiedCode ? "已复制" : "复制") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                                copiedCode = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedCode = false }
                            }
                            .controlSize(.mini)
                        }
                        .padding(10)
                        .background(NavTheme.accentBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                // Status / Result / Error Banner
                if let busy = busyMsg {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.system(size: 12))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
                if let ok = resultMsg {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NavTheme.logbookGreen)
                        Text(ok).font(.system(size: 12)).foregroundStyle(NavTheme.logbookGreen)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NavTheme.logbookGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                if let err = errorMsg {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NavTheme.danger)
                        Text(err).font(.system(size: 12)).foregroundStyle(NavTheme.danger)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NavTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Paired Devices
                VStack(alignment: .leading, spacing: 6) {
                    Text("已配对设备")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if store.syncStatus.pairedPeers.isEmpty {
                        Text("暂无已配对设备")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundStyle(.quaternary)
                            )
                    } else {
                        ForEach(store.syncStatus.pairedPeers) { peer in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(peer.online ? NavTheme.logbookGreen : Color.gray.opacity(0.45))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.deviceName)
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text(peerSubtitle(peer))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    busyMsg = "正在同步 \(peer.deviceName)…"
                                    resultMsg = nil
                                    errorMsg = nil
                                    store.syncWithPeer(deviceID: peer.deviceId) { err in
                                        busyMsg = nil
                                        if let err {
                                            errorMsg = err
                                        } else {
                                            resultMsg = "已与 \(peer.deviceName) 完成同步"
                                        }
                                    }
                                } label: {
                                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11.5))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(busyMsg != nil)

                                Button(role: .destructive) {
                                    store.deletePairedPeer(deviceID: peer.deviceId)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("解除配对")
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Discovered Devices (UDP)
                VStack(alignment: .leading, spacing: 6) {
                    Text("局域网发现的设备 (UDP)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if store.syncStatus.discoveredPeers.isEmpty {
                        Text("正在同一 Wi-Fi 下扫描其他 TODO 设备…")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundStyle(.quaternary)
                            )
                    } else {
                        ForEach(store.syncStatus.discoveredPeers) { peer in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(NavTheme.logbookGreen)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.deviceName)
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text("\(peer.ip):\(peer.httpPort)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("配对") {
                                    pairTarget = peer
                                    errorMsg = nil
                                }
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Pair Confirm / Manual IP Input
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pairTarget != nil
                             ? "与 \(pairTarget!.deviceName) (\(pairTarget!.ip)) 配对"
                             : "手动输入 IP 配对")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if pairTarget != nil {
                            Button("切换手动输入") { pairTarget = nil }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(NavTheme.accentBlue)
                        }
                    }

                    HStack(spacing: 8) {
                        if pairTarget == nil {
                            TextField("对方局域网 IP（如 192.168.1.20）", text: $manualIP)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        TextField("6位配对码", text: $pairCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100)
                        Button("确认配对") {
                            submitPair()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(busyMsg != nil || pairCode.filter(\.isNumber).count != 6 || (pairTarget == nil && manualIP.trimmingCharacters(in: .whitespaces).isEmpty))
                    }
                }
            }
            .padding(12)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                store.refreshSyncStatus()
            }
        }
    }

    private func submitPair() {
        let ip = pairTarget?.ip ?? manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = pairTarget?.httpPort ?? 8787
        let digits = pairCode.filter(\.isNumber)
        busyMsg = "正在与 \(ip) 配对…"
        errorMsg = nil
        resultMsg = nil
        store.pairWithPeer(ip: ip, port: port, code: digits) { res in
            busyMsg = nil
            switch res {
            case .success(let peer):
                pairTarget = nil
                pairCode = ""
                manualIP = ""
                resultMsg = "已成功配对 \(peer.deviceName)，正在自动同步"
            case .failure(let err):
                errorMsg = err.localizedDescription
            }
        }
    }

    private func peerSubtitle(_ peer: PairedPeer) -> String {
        let addr = peer.lastIp.isEmpty ? "离线" : "\(peer.lastIp):\(peer.lastPort > 0 ? peer.lastPort : 8787)"
        if peer.lastSyncAt > 0 {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            let t = f.string(from: Date(timeIntervalSince1970: Double(peer.lastSyncAt) / 1000.0))
            return "\(addr) · 上次 \(t)"
        }
        return addr
    }

    private var dataTab: some View {
        Form {
            Section("导出与导入") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导出为 Markdown")
                        Text("包含所有自定义列表与已完成提醒及子任务")
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
