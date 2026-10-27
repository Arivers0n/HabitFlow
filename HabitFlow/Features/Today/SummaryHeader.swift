import SwiftUI

/// Сводка дня: кольцо выполненных привычек и лучшая текущая серия без срыва.
struct SummaryHeader: View {
    @Environment(HabitStore.self) private var store
    let build: [Habit]
    let quit: [Habit]
    let day: Date

    var body: some View {
        let engine = store.engine
        // Одни и те же числа, что у напарника и в подписи «X из Y»: считает домен, а не экран.
        let summary = CompanionEngine(calendar: engine.calendar).summary(build.map(\.snapshot), on: day)
        let dueCount = summary.scheduled
        let done = summary.scheduledDone
        let ratio = summary.screenRatio ?? 0
        let accent = Appearance.shared.accent
        let bestQuit = quit.map { engine.quitStreak($0.snapshot) }.max { $0.current < $1.current }

        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: ratio, color: accent, lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(Int((ratio * 100).rounded()))%")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("дня").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 78, height: 78)
            .animation(Motion.bouncy, value: ratio)

            VStack(alignment: .leading, spacing: 6) {
                Text(Copy.greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(headline(done: done, due: dueCount))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let q = bestQuit, q.current > 3_600 {
                    Label(Copy.cleanFor(DurationText.human(q.current)), systemImage: "shield.lefthalf.filled")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .card(radius: 28)
    }

    private func headline(done: Int, due: Int) -> String {
        if due == 0 { return build.isEmpty ? "Добавь первую полезную привычку" : "Сегодня день отдыха" }
        if done == due { return Copy.allDone }
        return Copy.remaining(due - done)
    }
}

/// Неделя с понедельника: кольцо выполнения на каждый день, тап — посмотреть или отметить другой день.
struct WeekStrip: View {
    @Environment(HabitStore.self) private var store
    let habits: [Habit]
    @Binding var selected: Date

    var body: some View {
        let cal = Calendar.habitFlow
        let start = cal.startOfWeek(.now)
        let days = (0..<7).map { cal.addingDays($0, to: start) }
        let accent = Appearance.shared.accent

        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let future = d > cal.startOfDay(for: .now)
                let isSel = cal.isDate(d, inSameDayAs: selected)
                Button {
                    guard !future else { return }
                    withAnimation(Motion.smooth) { selected = d }
                    Haptics.selection()
                } label: {
                    VStack(spacing: 6) {
                        Text(WeekdayNames.short[cal.component(.weekday, from: d)])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSel ? accent : .secondary)
                        ZStack {
                            ProgressRing(progress: future ? 0 : ratio(d), color: accent, lineWidth: 3.5)
                            Text("\(cal.component(.day, from: d))")
                                .font(.footnote.weight(isSel ? .bold : .medium))
                                .monospacedDigit()
                                .foregroundStyle(future ? .tertiary : .primary)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSel ? accent.opacity(0.14) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(future)
            }
        }
        .padding(8)
        .card(radius: 24)
    }

    private func ratio(_ d: Date) -> Double {
        CompanionEngine(calendar: store.engine.calendar).summary(habits.map(\.snapshot), on: d).screenRatio ?? 0
    }
}
