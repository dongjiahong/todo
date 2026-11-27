# Design — Navigator (Native v2)

## Information Architecture

- **Focus Views**: `今天` (Overdue + Due Today + Doing + collapsible Today Completed), `进行中`, `待办`, `计划` (Upcoming), `标签` (5 refined hues), and `日志簿` (Logbook).
- **Optional Board View (macOS)**: 2 spacious columns (`待办` and `进行中`) with native drag-and-drop. No Done or Archive columns.

## Platform Ergonomics

- **macOS**: Non-blocking right-side Detail Inspector replaces modal dialogs; `⌘N` Quick Capture supports continuous entry; 5-second Undo banner handles reversible complete/delete actions.
- **Android**: Bottom navigation frees horizontal gestures for row swipes (right = complete, left = toggle in-progress / delete); tapping a task navigates to a full-screen scrollable Detail screen so long notes and keyboards never collide.
