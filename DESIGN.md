# Design — TODO (Apple Reminders Style)

## Information Architecture

- **5 Smart Lists**: `今天` (Overdue + Due Today), `计划` (Scheduled, grouped by date), `全部` (All active reminders grouped by custom List), `旗标` (Flagged), and `完成` (Completed, grouped by completion date).
- **Custom Lists (`我的列表`)**: User-defined lists with 8 Apple system colors and 10 semantic icons; default list `提醒` (`list_reminders`) is auto-provisioned.
- **Tags (`标签`)**: Flow-wrap `#tag` pills with `所有标签` overview and per-tag filtering.

## Unified Visual Language

- **Shared Apple Reminders Palette**: `#007AFF` (Today Blue), `#FF3B30` (Scheduled Red / Overdue), `#48484A` (All Dark), `#FF9500` (Flagged Orange), `#6E6E73` (Completed Gray), `#34C759` (Green), and 8 list colors.
- **Consistent Component Semantics**: Circular checkboxes (empty ring → colored ring with inner dot), priority prefixes (`!`, `!!`, `!!!`), `N 项完成 • 清除 | 显示/隐藏` header bar, and dotted `◌` phantom row at the bottom of every list/group.

## Platform Ergonomics

- **macOS (SwiftUI)**: 2-pane `NavigationSplitView` (Sidebar with Search + 2-column Smart Grid + My Lists + Tags + `+ 添加列表`; Main pane with inline editing, quick date/tag/flag chips, and floating `(i)` Inspector Popover).
- **Android (Jetpack Compose)**: Two-level Apple Reminders mobile flow — Home Hub (`OverviewScreen`: Search + 2-column Smart Grid + grouped `我的列表` card + `标签` + bottom `新提醒事项 / 添加列表` bar) → `TaskListScreen` (grouped `全部`, inline editing with quick chips, `◌` phantom row, right-swipe complete & left-swipe flag) → `(i)` `TaskInspectorSheet` (`ModalBottomSheet`).
