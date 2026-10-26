import SwiftUI

/// Фиксация срыва: когда, сколько и что спровоцировало. Серия обнуляется,
/// рекорд и история остаются.
struct RelapseSheet: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    var onSaved: (String) -> Void

    @State private var date = Date.now
    @State private var amount: Double = 1
    @State private var trigger = ""
    @State private var customTrigger = ""
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private var library: TriggerLibrary { .shared }

    var body: some View {
        let danger = Palette.danger
        let q = store.engine.quitStreak(habit.snapshot)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        if let c = CompanionManager.shared.character {
                            CompanionScene(config: SceneConfig(character: c,
                                                               stage: max(XPRules.stage(for: CompanionManager.shared.state.lastSeenLevel), .baby),
                                                               mood: .caring,
                                                               headwear: CompanionManager.shared.state.headwear,
                                                               decor: []),
                                           size: 170)
                            Text(CompanionManager.shared.caringLine())
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
                        } else {
                            HabitIcon(symbol: habit.symbol, color: habit.color, size: 56)
                        }
                        Text(Copy.relapseTitle)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Текущая серия: \(DurationText.compact(q.current)). Рекорд сохранится.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Когда
                    HStack {
                        Label("Когда", systemImage: "clock")
                            .font(.headline)
                        Spacer()
                        DatePicker("", selection: $date, in: habit.startDate.addingTimeInterval(-86_400 * 365)...Date.now,
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    .padding(16)
                    .card(radius: 22)

                    // Сколько
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Сколько", systemImage: "number")
                            .font(.headline)
                        HStack(spacing: 16) {
                            stepButton("minus") { amount = max(0, amount - 1) }
                            VStack(spacing: 0) {
                                Text(NumberText.value(amount))
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: amount))
                                Text(habit.unitName.isEmpty ? "раз" : habit.unitName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            stepButton("plus") { amount += 1 }
                        }
                        .animation(Motion.press, value: amount)
                    }
                    .padding(16)
                    .card(radius: 22)

                    // Причина
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Что спровоцировало?", systemImage: "exclamationmark.bubble")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(library.items) { item in
                                Button {
                                    trigger = trigger == item.name ? "" : item.name
                                    customTrigger = ""
                                    Haptics.selection()
                                } label: {
                                    Chip(title: item.name, symbol: item.symbol, selected: trigger == item.name, color: danger)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        TextField("Своя причина", text: $customTrigger)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
                            .onChange(of: customTrigger) { _, v in if !v.isEmpty { trigger = "" } }
                    }
                    .padding(16)
                    .card(radius: 22)

                    // Заметка
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Заметка", systemImage: "note.text")
                            .font(.headline)
                        TextField("Где был, что чувствовал — поможет заметить закономерность", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($noteFocused)
                    }
                    .padding(16)
                    .card(radius: 22)

                    Button(action: save) {
                        Text(Copy.relapseSave)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: danger))
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    private func save() {
        let reason = customTrigger.trimmingCharacters(in: .whitespaces).isEmpty
            ? trigger : customTrigger.trimmingCharacters(in: .whitespaces)
        let before = store.recordRelapse(habit, date: date, amount: amount, trigger: reason, note: note)
        Haptics.warning()
        let record = max(before.best, store.engine.quitStreak(habit.snapshot).best)
        onSaved(Copy.relapseSaved(previous: DurationText.human(record)))
        dismiss()
    }
}
