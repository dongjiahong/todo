# Product — Navigator (Native v2)

## Architecture

- **Shared Core (`core/`)**: Pure Go (`modernc.org/sqlite`), field-level LWW merge with tombstone soft-deletion, 6-digit HMAC-SHA256 pairing code, UDP LAN discovery, active event-driven sync with `HEAD`-based attachment deduplication, separated binary image assets (`assets/`) with automatic 24-hour orphan cleanup, daily 7-day rolling JSON snapshots, and Markdown/JSON export.
- **macOS Client (`macos/`)**: Native SwiftUI (macOS 14+), low memory footprint, `NavigationSplitView` 3-pane Master-Detail layout, optional 2-column Board (`待办` / `进行中`), debounced editing, `UNUserNotificationCenter` reminders (with configurable lead time), and Dock attention badge.
- **Android Client (`android/`)**: Native Kotlin + Jetpack Compose (Material 3, minSdk 28), Things 3-style Overview Hub + modular `ui/` screens (`OverviewScreen`, `TaskListScreen`, `TaskDetailScreen`, `DueDateSheet`, `Sheets`), `SwipeToDismissBox` one-handed gestures, theme & lead-reminder preferences, Markdown/JSON export & import, and pull-to-sync.

## Core Decisions

1. **No permanent Done/Archive columns**: Completed work moves out of active focus into the **Logbook（日志簿）** grouped by completion date; today's completed items remain optionally collapsible in Today view.
2. **First-class Subtasks + Clean Notes**: Subtasks are structured records with native circular checkboxes and inline editing/creation on both platforms; notes stay clean plain text with auto-detected clickable URLs.
3. **Zero WebView overhead**: Both platforms render purely with native UI toolkits and share one Go core via CGo (macOS) and `gomobile` (Android).
