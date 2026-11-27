# Product — Navigator (Native v2)

## Architecture

- **Shared Core (`core/`)**: Pure Go (`modernc.org/sqlite`), field-level LWW merge with tombstone soft-deletion, 6-digit HMAC-SHA256 pairing code, UDP LAN discovery, active event-driven sync, separated binary image assets (`assets/`), daily 7-day rolling JSON snapshots, and Markdown/JSON export.
- **macOS Client (`macos/`)**: Native SwiftUI (macOS 14+), low memory footprint, `NavigationSplitView` 3-pane Master-Detail layout, optional 2-column Board (`待办` / `进行中`), `UNUserNotificationCenter` reminders, and Dock attention badge.
- **Android Client (`android/`)**: Native Kotlin + Jetpack Compose (Material 3, minSdk 28), bottom navigation (`今天` / `进行中` / `待办` / `更多`), `SwipeToDismissBox` one-handed gestures, full-screen scrollable Detail screen with `imePadding()`, and pull-to-sync.

## Core Decisions

1. **No permanent Done/Archive columns**: Completed work moves out of active focus into the **Logbook（日志簿）** grouped by completion date; today's completed items remain optionally collapsible in Today view.
2. **First-class Subtasks + Clean Notes**: Subtasks are structured records with native checkboxes and inline creation; notes stay clean plain text with auto-detected clickable URLs.
3. **Zero WebView overhead**: Both platforms render purely with native UI toolkits and share one Go core via CGo (macOS) and `gomobile` (Android).
