import SwiftUI

/// Месячный календарь привычки. Свайп влево/вправо листает месяцы,
/// тап по прошедшему дню у полезной привычки отмечает или снимает отметку.
struct MonthCalendar: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    @State private var month = Calendar.habitFlow.dateInterval(of: .month, for: .now)!.start
    @State private var direction: Edge = .trailing

    private var cal: Calendar { .habitFlow }

    var body: some View {
        let snap = habit.snapshot
        let totals = store.engine.dailyTotals(snap)
        let color = habit.color

        VStack(spacing: 14) {
            HStack {
                navButton("chevron.left") { shift(-1) }
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                Spacer()
                navButton("chevron.right") { shift(1) }
                    .disabled(isCurrentMonth)
                    .opacity(isCurrentMonth ? 0.3 : 1)
            }

            HStack(spacing: 0) {
                ForEach(WeekdayNames.mondayFirst, id: \.self) { wd in
                    Text(WeekdayNames.short[wd])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(day: day,
                                status: store.engine.status(of: day, for: snap, totals: totals),
                                progress: min(1, (totals[cal.startOfDay(for: day)] ?? 0) / habit.goal.target),
                                color: color,
                                isToday: cal.isDateInToday(day))
                            .onTapGesture { tap(day) }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .id(month)
            .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                    removal: .opacity))

            legend(color: color)
        }
        .padding(16)
        .card()
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    if v.translation.width < -50 { shift(1) }
                    if v.translation.width > 50 { shift(-1) }
                }
        )
    }

    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: .now, toGranularity: .month) }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    /// Дни месяца с пустыми ячейками до понедельника.
    private var cells: [Date?] {
        let range = cal.range(of: .day, in: .month, for: month)!
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday + 5) % 7
        return Array(repeating: nil, count: lead) + range.map { cal.addingDays($0 - 1, to: month) }
    }

    private func shift(_ by: Int) {
        let next = cal.date(byAdding: .month, value: by, to: month)!
        if by > 0 && next > .now { return }
        direction = by > 0 ? .trailing : .leading
        withAnimation(Motion.smooth) { month = next }
        Haptics.selection()
    }

    private func tap(_ day: Date) {
        guard habit.kind == .build, day <= .now else { return }
        let wasDone = store.engine.isDone(store.value(of: habit, on: day), goal: habit.goal)
        withAnimation(Motion.bouncy) { store.toggle(habit, on: day) }
        wasDone ? Haptics.tap() : Haptics.success()
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func legend(color: Color) -> some View {
        HStack(spacing: 14) {
            if habit.kind == .build {
                legendItem(Circle().fill(color), "Выполнено")
                legendItem(Circle().stroke(color, lineWidth: 2), "Частично")
                legendItem(Circle().fill(Color.primary.opacity(0.18)).frame(width: 6, height: 6), "Пропуск")
            } else {
                legendItem(Circle().fill(color.opacity(0.28)), "Чисто")
                legendItem(Circle().fill(Palette.danger), "Срыв")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ dot: some View, _ text: String) -> some View {
        HStack(spacing: 5) {
            dot.frame(width: 10, height: 10)
            Text(text)
        }
    }
}

private struct DayCell: View {
    let day: Date
    let status: DayStatus
    let progress: Double
    let color: Color
    let isToday: Bool

    var body: some View {
        let n = Calendar.habitFlow.component(.day, from: day)
        ZStack {
            switch status {
            case .done:
                Circle().fill(color.gradient)
            case .partial, .pending:
                ProgressRing(progress: progress, color: color, lineWidth: 2.5)
            case .clean:
                Circle().fill(color.opacity(0.22))
            case .relapse:
                Circle().fill(Palette.danger.gradient)
            case .missed:
                Circle().fill(Color.primary.opacity(0.05))
            default:
                EmptyView()
            }
            if isToday && status != .done && status != .relapse {
                Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
            }
            Text("\(n)")
                .font(.footnote.weight(isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(textColor)
        }
        .frame(height: 40)
        .frame(maxWidth: 40)
        .contentShape(Circle())
        .animation(Motion.bouncy, value: status)
    }

    private var textColor: Color {
        switch status {
        case .done, .relapse: .white
        case .future, .beforeStart: Color.primary.opacity(0.25)
        case .rest: Color.primary.opacity(0.45)
        case .missed: Color.primary.opacity(0.55)
        default: .primary
        }
    }
}
