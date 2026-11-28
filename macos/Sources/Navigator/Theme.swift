import SwiftUI

/// Apple Reminders-inspired design tokens aligned across macOS and Android.
enum NavTheme {
    // Smart list & semantic accent colors (Apple Reminders palette)
    static let accentBlue = Color(red: 0.000, green: 0.478, blue: 1.000)      // #007AFF (Today)
    static let scheduledRed = Color(red: 1.000, green: 0.231, blue: 0.188)    // #FF3B30 (Scheduled / Overdue)
    static let allDark = Color(red: 0.282, green: 0.282, blue: 0.290)         // #48484A (All)
    static let flaggedOrange = Color(red: 1.000, green: 0.584, blue: 0.000)   // #FF9500 (Flagged)
    static let completedGray = Color(red: 0.431, green: 0.431, blue: 0.451)   // #6E6E73 (Completed)
    static let logbookGreen = Color(red: 0.204, green: 0.780, blue: 0.349)    // #34C759
    static let todayGold = flaggedOrange
    static let danger = scheduledRed

    static func listColor(for color: ListColor) -> Color {
        switch color {
        case .blue: return Color(red: 0.000, green: 0.478, blue: 1.000)       // #007AFF
        case .orange: return Color(red: 1.000, green: 0.584, blue: 0.000)     // #FF9500
        case .green: return Color(red: 0.204, green: 0.780, blue: 0.349)      // #34C759
        case .red: return Color(red: 1.000, green: 0.231, blue: 0.188)        // #FF3B30
        case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)     // #AF52DE
        case .pink: return Color(red: 1.000, green: 0.176, blue: 0.333)       // #FF2D55
        case .yellow: return Color(red: 0.949, green: 0.686, blue: 0.000)     // #F2AF00
        case .gray: return Color(red: 0.557, green: 0.557, blue: 0.576)       // #8E8E93
        }
    }

    static func tagColor(for hue: TagHue) -> Color {
        switch hue {
        case .blue: return Color(red: 0.000, green: 0.478, blue: 1.000)
        case .green: return Color(red: 0.204, green: 0.780, blue: 0.349)
        case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
        case .amber: return Color(red: 1.000, green: 0.584, blue: 0.000)
        case .red: return Color(red: 1.000, green: 0.231, blue: 0.188)
        }
    }
}

/// Apple Reminders circular checkbox (empty ring when unchecked, inner filled dot + ring when checked).
struct TaskCheckbox: View {
    let checked: Bool
    var tint: Color = NavTheme.accentBlue
    var size: CGFloat = 15.5
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .strokeBorder(
                        checked ? tint : Color.secondary.opacity(0.45),
                        lineWidth: 1.35
                    )
                    .frame(width: size, height: size)
                if checked {
                    Circle()
                        .fill(tint)
                        .frame(width: size - 5, height: size - 5)
                }
            }
            .scaleEffect(checked ? 1.0 : 0.98)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: checked)
            .frame(width: 19, height: 19)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tiny circular progress ring for subtask checklists.
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

/// Unified due-date badge across rows.
struct DueBadgeView: View {
    let text: String
    let tone: DueTone
    var repeating: Bool = false

    private var fg: Color {
        switch tone {
        case .late: return NavTheme.danger
        case .soon: return NavTheme.accentBlue
        case .normal: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 10.5))
            Text(text)
                .font(.system(size: 11.5, weight: tone == .late ? .medium : .regular))
                .monospacedDigit()
            if repeating {
                Image(systemName: "repeat")
                    .font(.system(size: 9.5))
            }
        }
        .foregroundStyle(fg)
    }
}

/// Apple Reminders-style `#tag` pill.
struct TagPillView: View {
    let tag: TagItem
    var selected: Bool = true
    var interactive: Bool = false
    var action: (() -> Void)? = nil

    private var pillContent: some View {
        Text("#\(tag.label)")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(selected ? tag.hue.color : .secondary)
            .padding(.horizontal, interactive ? 8 : 6)
            .padding(.vertical, interactive ? 3 : 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? tag.hue.color.opacity(0.13) : Color.primary.opacity(0.06))
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

/// Wrapping flow layout shared by sidebar tags, inline tags, and inspector.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
