# Product — TODO (Native Apple Reminders Style)

## Architecture

- **Shared Core (`core/`)**: Pure Go (`modernc.org/sqlite`), field-level LWW merge with tombstone soft-deletion for Tasks, Tags, and Lists (`lists` table), automatic migration from legacy `doing` status to `flagged=true` and default `提醒` list, 6-digit HMAC-SHA256 pairing code, UDP LAN discovery, active event-driven sync with `HEAD`-based attachment deduplication, separated binary image assets (`assets/`) with 24-hour orphan cleanup, daily 7-day rolling JSON snapshots, and Markdown/JSON export.
- **macOS Client (`macos/`)**: Native SwiftUI (macOS 14+), 2-pane `NavigationSplitView`, Apple Reminders sidebar (Search + 5 Smart List cards + My Lists + Tags + `+ 添加列表`), inline row editing with `◌` phantom rows, floating `(i)` Inspector Popover (Title, Flag, Notes, Tags, Date/Repeat, Priority, List, URL, Images, Subtasks), `UNUserNotificationCenter` reminders, and Dock badge.
- **Android Client (`android/`)**: Native Kotlin + Jetpack Compose (Material 3, minSdk 28), Apple Reminders Home Hub + List Stream with inline editing & `◌` phantom rows, `(i)` `ModalBottomSheet` Inspector, swipe-to-complete / swipe-to-flag gestures, theme & lead-reminder preferences, Markdown/JSON export & import, and pull-to-sync.
