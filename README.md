# TODO

本地优先（Local-First）的个人任务与聚焦工具，采用 **Go 共享核心 + macOS SwiftUI + Android Jetpack Compose** 全原生架构。

## 核心特性

- **聚焦当下，砍掉死列**：已完成任务自动沉入 **日志簿（Logbook）**（今日已完成支持折叠查看），主视野只保留 **今天 / 进行中 / 待办 / 计划**。macOS 端可选切换精简双列看板（待办 / 进行中）。
- **结构化子任务 + 纯净备注**：子任务作为一等结构化清单管理，备注采用原生多行文本（自动识别可点击链接），支持图片附件。
- **双端原生体验**：
  - **macOS（SwiftUI）**：三栏 Master-Detail 与非阻塞右侧详情、支持 `⌘V` 直接粘贴剪贴板截图或 Finder 图片文件、原生 `UNUserNotificationCenter` 定时提醒（含完成/推迟 1 小时操作）、Dock 角标、键盘流（`⌘N` 快速捕获、`⌘⇧E` 导出 Markdown）。
  - **Android（Jetpack Compose）**：Things 3 风格极简视觉与交互（列表总览 Hub + 通透纯白任务流 + 圆形蓝色 Magic Plus 悬浮按钮）、支持今天 / 进行中 / 待办 / 计划 / 标签管理 / 日志簿与全局快速查找、悬浮白卡详情编辑器、单手左右滑动手势（右滑完成 + 撤销条，左滑切换进行中）及下拉主动同步。
- **局域网 P2P 主动同步**：基于 Go Core 的 SQLite + Tombstone 字段级合并 + 6 位配对码 HMAC-SHA256 认证 + UDP 广播发现 + 图片资产分离同步。

## 目录结构

```text
core/       Go 共享核心（SQLite、字段级 LWW 合并、局域网同步、资产分离、CGo & gomobile 桥接）
macos/      macOS 原生 SwiftUI 客户端
android/    Android 原生 Kotlin Jetpack Compose 客户端
Makefile    统一版本检查、Release 构建与 GitHub 一键发版命令
```

## 构建与发版

所有构建均使用 Release 配置：

```bash
# 检查各端版本号与一致性
make version

# 编译 macOS TODO.app（Release）
make macos-app

# 编译 Android Release APK（需安装 gomobile）
make android-release

# 编译并通过 adb 安装 Android Release APK
make install-android

# 打包双端 Release 产物（.dmg + .apk），并自动打 Tag 上传至 GitHub Release
make release v=0.2.0
```
