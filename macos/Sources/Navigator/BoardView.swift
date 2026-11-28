import SwiftUI

/// Sheet for creating or editing a custom Reminder List (name, color circle, SF Symbol icon).
struct AddListSheet: View {
    @Bindable var store: NavigatorStore
    var editing: TaskListItem?

    @State private var name: String = ""
    @State private var color: ListColor = .blue
    @State private var icon: ListIcon = .list
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Live Preview Badge
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: 56, height: 56)
                    .shadow(color: color.color.opacity(0.32), radius: 8, y: 3)
                Image(systemName: icon.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            TextField("列表名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .onSubmit { save() }

            // Color Picker Row
            HStack(spacing: 10) {
                ForEach(ListColor.allCases) { c in
                    Button {
                        color = c
                    } label: {
                        ZStack {
                            Circle()
                                .fill(c.color)
                                .frame(width: 24, height: 24)
                            if color == c {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.4), lineWidth: 2)
                                    .frame(width: 30, height: 30)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Icon Picker Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(ListIcon.allCases) { ic in
                    let selected = icon == ic
                    Button {
                        icon = ic
                    } label: {
                        ZStack {
                            Circle()
                                .fill(selected ? color.color.opacity(0.18) : Color.primary.opacity(0.06))
                                .frame(width: 34, height: 34)
                            Image(systemName: ic.symbolName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selected ? color.color : .secondary)
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(selected ? color.color : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(editing == nil ? "创建" : "保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 310)
        .onAppear {
            if let editing {
                name = editing.name
                color = editing.listColor
                icon = editing.listIcon
            }
            nameFocused = true
        }
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if var existing = editing {
            existing.name = clean
            existing.color = color.rawValue
            existing.icon = icon.rawValue
            store.updateList(existing)
        } else {
            store.createList(name: clean, color: color, icon: icon)
        }
        dismiss()
    }

    private func dismiss() {
        store.showAddListSheet = false
        store.editingList = nil
    }
}
