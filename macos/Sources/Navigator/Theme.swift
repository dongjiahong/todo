import SwiftUI

/// Centralized Things 3-inspired design tokens aligned with Android `ThingsTheme.kt`.
enum NavTheme {
    static let accentBlue = Color(red: 0.192, green: 0.471, blue: 0.965)      // #3178F6
    static let todayGold = Color(red: 0.949, green: 0.663, blue: 0.000)       // #F2A900
    static let inboxBlue = Color(red: 0.227, green: 0.510, blue: 0.965)       // #3A82F6
    static let upcomingCoral = Color(red: 0.898, green: 0.282, blue: 0.302)   // #E5484D
    static let logbookGreen = Color(red: 0.157, green: 0.655, blue: 0.431)    // #28A76E
    static let doingBlue = accentBlue
    static let danger = upcomingCoral

    static func tagColor(for hue: TagHue) -> Color {
        switch hue {
        case .blue: return Color(red: 0.192, green: 0.471, blue: 0.965)       // #3178F6
        case .green: return Color(red: 0.157, green: 0.655, blue: 0.431)      // #28A76E
        case .purple: return Color(red: 0.545, green: 0.361, blue: 0.965)     // #8B5CF6
        case .amber: return Color(red: 0.898, green: 0.584, blue: 0.000)      // #E59500
        case .red: return Color(red: 0.898, green: 0.282, blue: 0.302)        // #E5484D
        }
    }
}

/// Shared Things-style checkbox: rounded square for tasks, circular for subtasks.
struct TaskCheckbox: View {
    let checked: Bool
    var isDoing: Bool = false
    var isCircular: Bool = false
    var size: CGFloat = 17
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                if isCircular {
                    if checked {
                        Circle()
                            .fill(NavTheme.accentBlue)
                            .frame(width: size, height: size)
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.56, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.4)
                            .frame(width: size, height: size)
                    }
                } else {
                    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                    if checked {
                        shape
                            .fill(NavTheme.accentBlue)
                            .frame(width: size, height: size)
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.56, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        shape
                            .strokeBorder(
                                isDoing ? NavTheme.doingBlue : Color.secondary.opacity(0.5),
                                lineWidth: 1.5
                            )
                            .frame(width: size, height: size)
                    }
                }
            }
            .scaleEffect(checked ? 1.0 : 0.98)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: checked)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tiny circular progress ring for subtask checklists (matches Android `MiniProgressRing`).
struct MiniProgressRing: View {
    let done: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.32), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    done == total && total > 0 ? NavTheme.logbookGreen : NavTheme.accentBlue,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
    }
}

/// Unified due-date badge across list rows and board cards.
struct DueBadgeView: View {
    let text: String
    let tone: DueTone
    var repeating: Bool = false

    private var fg: Color {
        switch tone {
        case .late: return NavTheme.danger
        case .soon: return NavTheme.todayGold
        case .normal: return .secondary
        }
    }

    private var bg: Color {
        switch tone {
        case .late: return NavTheme.danger.opacity(0.12)
        case .soon: return NavTheme.todayGold.opacity(0.14)
        case .normal: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            if repeating {
                Image(systemName: "repeat")
                    .font(.system(size: 9.5))
            }
        }
        .padding(.horizontal, tone == .normal ? 0 : 6)
        .padding(.vertical, tone == .normal ? 0 : 2)
        .background(bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .foregroundStyle(fg)
    }
}

/// Unified tag pill used in task rows, board cards, detail inspector, and quick capture.
struct TagPillView: View {
    let tag: TagItem
    var selected: Bool = true
    var interactive: Bool = false
    var action: (() -> Void)? = nil

    private var pillContent: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.hue.color)
                .frame(width: 6, height: 6)
            Text(tag.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? tag.hue.color : .secondary)
        }
        .padding(.horizontal, interactive ? 8 : 6)
        .padding(.vertical, interactive ? 4 : 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? tag.hue.color.opacity(0.13) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(interactive && selected ? tag.hue.color.opacity(0.4) : .clear, lineWidth: 1)
        )
    }

    var body: some View {
        if let action {
            Button(action: action) {
                pillContent
            }
            .buttonStyle(.plain)
        } else {
            pillContent
        }
    }
}
