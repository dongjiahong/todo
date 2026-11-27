# TODO

本地优先（Local-First）的个人任务与聚焦工具，采用 **Go 共享核心 + macOS SwiftUI + Android Jetpack Compose** 全原生架构。

## 核心设计理念

- **聚焦当下，砍掉死列**：不再用四列看板把“已完成”和“归档”常驻在主视野。已完成任务自动沉入侧边 **日志簿（Logbook）**（今天完成的任务可折叠查看），主界面只保留 **今天 / 进行中 / 待办 / 计划**。Mac 端可选一键切换 **精简双列看板（待办 / 进行中）**。
- **结构化子任务 + 纯净备注**：彻底告别“源码与预览两层皮”的割裂 Markdown  hack。子任务是一等结构化清单，备注是原生多行文本（自动识别可点击链接）。
- **双端第一方原生体验**：
  - **macOS（SwiftUI）**：三栏 Master-Detail 非阻塞右侧详情、原生 `UNUserNotificationCenter` 定时通知（含完成/推迟 1 小时按钮）、Dock 角标、键盘流（`⌘N` 快速捕获、`⌘⇧E` 导出 Markdown）。
  - **Android（Jetpack Compose）**：底部导航（今天 / 进行中 / 待办 / 更多）、单手左右滑动手势（右滑完成 + 撤销条，左滑切换进行中）、全屏可滚动详情页（支持 `imePadding()` 软键盘联动）、下拉主动同步。
- **局域网 P2P 主动同步**：基于 Go Core 的 SQLite + Tombstone 字段级合并 + 6 位配对码 HMAC-SHA256 认证 + UDP 广播发现 + 图片资产分离同步。

## 目录结构

```text
core/       Go 共享核心（SQLite、字段级 LWW 合并、局域网同步、资产分离、CGo & gomobile 桥接）
macos/      macOS 原生 SwiftUI 客户端（SwiftPM，链接 libnavigator_core.a）
android/    Android 原生 Kotlin Jetpack Compose 客户端（Gradle KTS，链接 navigator-core.aar）
Makefile    统一构建与发版命令（make macos-app / make android / make release v=0.2.0）
```

## 快速构建

```bash
# 编译 Go Core 静态库并构建 macOS .app
make macos-app

# 编译 Go Core Android AAR（需安装 gomobile）并打 APK
make android

# 打包 macOS .dmg 发版产物
make release v=0.2.0
```
