import SwiftUI

/// Bespoke macOS Date, Time & Repeat popover panel.
/// Replaces the bare native DatePicker with quick presets, a custom Monday-first calendar grid,
/// quick time chips + hour/minute steppers, and integrated repeat cycle pills.
struct DueDatePopover: View {
    let currentDue: String?
    let currentRepeat: RepeatRule
    let onApply: (String?, RepeatRule) -> Void
    let onDismiss: () -> Void

    @State private var displayedMonth: Date
    @State private var selectedDay: Date
    @State private var hour: Int
    @State private var minute: Int
    @State private var repeatRule: RepeatRule

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.locale = Locale(identifier: "zh_CN")
        return c
    }()

    init(
        currentDue: String?,
        currentRepeat: RepeatRule,
        onApply: @escaping (String?, RepeatRule) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentDue = currentDue
        self.currentRepeat = currentRepeat
        self.onApply = onApply
        self.onDismiss = onDismiss

        let base = DateHelper.parseDue(currentDue) ?? Date()
        let c = Calendar.current
        _displayedMonth = State(initialValue: base)
        _selectedDay = State(initialValue: base)
        _hour = State(initialValue: currentDue != nil ? c.component(.hour, from: base) : 18)
        _minute = State(initialValue: currentDue != nil ? c.component(.minute, from: base) : 0)
        _repeatRule = State(initialValue: currentRepeat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Quick Preset Cards (2x2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                presetCard(title: "今天", sub: shortWeekday(offsetDays: 0), icon: "sun.max.fill", tint: Color(red: 0.90, green: 0.58, blue: 0.12)) {
                    pickPreset(daysOffset: 0, defaultHour: 18)
                }
                presetCard(title: "明天", sub: shortWeekday(offsetDays: 1), icon: "sunrise.fill", tint: Color(red: 0.20, green: 0.48, blue: 0.88)) {
                    pickPreset(daysOffset: 1, defaultHour: 9)
                }
                presetCard(title: "本周末", sub: shortDate(nextWeekendDate()), icon: "sparkles", tint: Color(red: 0.52, green: 0.36, blue: 0.84)) {
                    pickDate(nextWeekendDate(), defaultHour: 10)
                }
                presetCard(title: "下周一", sub: shortDate(nextMondayDate()), icon: "arrow.right.circle.fill", tint: Color(red: 0.16, green: 0.62, blue: 0.42)) {
                    pickDate(nextMondayDate(), defaultHour: 9)
                }
            }

            Divider()

            // 2. Custom Mini Month Calendar
            VStack(spacing: 8) {
                HStack {
                    Text(monthTitle(displayedMonth))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    HStack(spacing: 4) {
                        Button { shiftMonth(-1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button("今") {
                            let now = Date()
                            displayedMonth = now
                            selectedDay = now
                            commitSelection()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))

                        Button { shiftMonth(1) } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                }

                // Weekday headers (Mon..Sun)
                let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(weekdays, id: \.self) { wd in
                        Text(wd)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(height: 20)
                    }

                    ForEach(calendarCells(), id: \.date) { cell in
                        let isSelected = cal.isDate(cell.date, inSameDayAs: selectedDay)
                        let isToday = cal.isDateInToday(cell.date)
                        Button {
                            selectedDay = cell.date
                            if !cell.inMonth {
                                displayedMonth = cell.date
                            }
                            commitSelection()
                        } label: {
                            Text("\(cal.component(.day, from: cell.date))")
                                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isSelected ? .white : (cell.inMonth ? .primary : .secondary.opacity(0.45))
                                )
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(isSelected ? Color.accentColor : Color.clear)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(isToday && !isSelected ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1.2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // 3. Custom Time Picker (Presets + Steppers)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Text("时间")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()

                    // Clean HH:MM stepper control
                    HStack(spacing: 4) {
                        stepBtn("-") { adjustMinutes(-30) }
                        Text(String(format: "%02d:%02d", hour, minute))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 46)
                        stepBtn("+") { adjustMinutes(30) }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                HStack(spacing: 5) {
                    ForEach([(9, 0, "09:00"), (12, 0, "12:00"), (14, 0, "14:00"), (18, 0, "18:00"), (21, 0, "21:00")], id: \.2) { h, m, label in
                        let on = hour == h && minute == m
                        Button(label) {
                            hour = h
                            minute = m
                            commitSelection()
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(on ? .white : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(on ? Color.accentColor : Color.primary.opacity(0.05))
                        )
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // 4. Repeat Cycle Strip
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("重复")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    ForEach(RepeatRule.allCases) { rule in
                        let on = repeatRule == rule
                        Button(rule.label) {
                            repeatRule = rule
                            commitSelection()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(on ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(on ? Color.accentColor : Color.primary.opacity(0.05))
                        )
                        .buttonStyle(.plain)
                    }
                }
            }

            // 5. Footer
            HStack {
                if currentDue != nil {
                    Button("清除") {
                        onApply(nil, RepeatRule.none)
                        onDismiss()
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                }
                Spacer()
                Button("完成") {
                    commitSelection()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 296)
    }

    private func presetCard(title: String, sub: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(sub)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stepBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func adjustMinutes(_ delta: Int) {
        var total = hour * 60 + minute + delta
        if total < 0 { total += 24 * 60 }
        total %= (24 * 60)
        hour = total / 60
        minute = total % 60
        commitSelection()
    }

    private func pickPreset(daysOffset: Int, defaultHour: Int) {
        let d = cal.date(byAdding: .day, value: daysOffset, to: Date()) ?? Date()
        pickDate(d, defaultHour: defaultHour)
    }

    private func pickDate(_ date: Date, defaultHour: Int) {
        selectedDay = date
        displayedMonth = date
        if currentDue == nil {
            hour = defaultHour
            minute = 0
        }
        commitSelection()
    }

    private func commitSelection() {
        var comps = cal.dateComponents([.year, .month, .day], from: selectedDay)
        comps.hour = hour
        comps.minute = minute
        let finalDate = cal.date(from: comps) ?? selectedDay
        onApply(DateHelper.formatDue(finalDate), repeatRule)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return "\(y)年\(m)月"
    }

    private func shortWeekday(offsetDays: Int) -> String {
        let d = cal.date(byAdding: .day, value: offsetDays, to: Date()) ?? Date()
        let wd = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][cal.component(.weekday, from: d) - 1]
        return wd
    }

    private func shortDate(_ date: Date) -> String {
        "\(cal.component(.month, from: date))/\(cal.component(.day, from: date))"
    }

    private func nextWeekendDate() -> Date {
        let now = Date()
        let wd = cal.component(.weekday, from: now) // 1=Sun .. 7=Sat
        let daysToSat = (7 - wd + 7) % 7
        return cal.date(byAdding: .day, value: daysToSat == 0 ? 7 : daysToSat, to: now) ?? now
    }

    private func nextMondayDate() -> Date {
        let now = Date()
        let wd = cal.component(.weekday, from: now) // 1=Sun, 2=Mon
        let daysToMon = (2 - wd + 7) % 7
        return cal.date(byAdding: .day, value: daysToMon == 0 ? 7 : daysToMon, to: now) ?? now
    }

    private struct CalCell {
        let date: Date
        let inMonth: Bool
    }

    private func calendarCells() -> [CalCell] {
        let comps = cal.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        // Weekday index where Mon = 0 .. Sun = 6
        let firstWeekday = (cal.component(.weekday, from: firstOfMonth) + 5) % 7
        var cells: [CalCell] = []

        if firstWeekday > 0 {
            for offset in stride(from: firstWeekday, through: 1, by: -1) {
                if let d = cal.date(byAdding: .day, value: -offset, to: firstOfMonth) {
                    cells.append(CalCell(date: d, inMonth: false))
                }
            }
        }
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(CalCell(date: d, inMonth: true))
            }
        }
        while cells.count % 7 != 0 {
            let last = cells.last?.date ?? firstOfMonth
            if let next = cal.date(byAdding: .day, value: 1, to: last) {
                cells.append(CalCell(date: next, inMonth: false))
            }
        }
        return cells
    }
}
