# Design — Navigator (Native v2)

## Information Architecture

- **Focus Views**: `今天` (Overdue + Due Today + Doing + collapsible Today Completed), `进行中`, `待办`, `计划` (Upcoming, grouped by date on both platforms), `标签` (5 unified semantic hues), and `日志簿` (Logbook).
- **Optional Board View (macOS)**: 2 spacious columns (`待办` and `进行中`) with native drag-and-drop. No Done or Archive columns.

## Unified Visual Language

- **Shared Things 3-Inspired Tokens**: `NavTheme` (macOS) and `ThingsTheme` (Android) share the same palette (`#3178F6` accent, `#F2A900` today gold, `#E5484D` coral/danger, `#28A76E` logbook green, and 5 semantic tag hues).
- **Consistent Component Semantics**: Rounded-square checkboxes for primary tasks, circular checkboxes for subtasks, circular `MiniProgressRing` for subtask progress, and unified tag/due pills across list, board, detail, and quick capture.

## Platform Ergonomics

- **macOS**: Non-blocking right-side Detail Inspector replaces modal dialogs; `⌘N` Quick Capture with `DueDatePopover` supports continuous entry; `⌘K` Command Palette supports full keyboard navigation (`↑`/`↓`/`↩`/`Esc`); 5-second Undo banner handles reversible complete/delete actions (including cleaning up spawned repeating occurrences).
- **Android**: Things 3-style Lists Overview Hub (`OverviewScreen`) with hierarchical Predictive Back navigation (`TaskDetail` → search → `Overview` → double-back exit); `SwipeToDismissBox` with 42% threshold and haptics for one-handed gestures; full-screen floating-card Detail screen with `imePadding()`, inline subtask editing, clickable note links, and full-screen image preview.
