import SwiftUI
import Charts

struct HabitDetailView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit

    @State private var editing = false
    @State private var relapsing = false
    @State private var confirmDelete = false
    @State private var relapseToDelete: Relapse?
    @State private var toast: String?
    @State private var burst = 0

    private let stats = StatsEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                if habit.kind == .build { buildActions } else { quitActions }
                MonthCalendar(habit: habit)
                tiles
                charts
                AchievementsCard(habit: habit)
                if habit.kind == .quit { relapseHistory }
                if !habit.note.isEmpty {
                    Text(habit.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .card(radius: 22)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Изменить", systemImage: "pencil") }
                    Button { store.setArchived(habit, true); dismiss() } label: { Label("В архив", systemImage: "archivebox") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.headline).frame(width: 36, height: 36)
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { HabitEditorForm(draft: HabitDraft(habit: habit), habit: habit) { editing = false } }
        }
        .sheet(isPresented: $relapsing) {
            RelapseSheet(habit: habit) { message in show(message) }
        }
        .confirmationDialog("Удалить «\(habit.name)» вместе с историей?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.delete(habit) }
            }
        }
        .confirmationDialog("Удалить запись о срыве?", isPresented: relapseDeleteBinding, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let r = relapseToDelete { withAnimation(Motion.smooth) { store.deleteRelapse(r) } }
            }
        } message: {
            Text("Серия и рекорд пересчитаются.")
        }
        .overlay(alignment: .bottom) { ToastView(text: toast) }
    }

    private var relapseDeleteBinding: Binding<Bool> {
        Binding(get: { relapseToDelete != nil }, set: { if !$0 { relapseToDelete = nil } })
    }

    // MARK: - Шапка

    @ViewBuilder
    private var hero: some View {
        let color = habit.color
        VStack(spacing: 14) {
            HabitIcon(symbol: habit.symbol, color: color, size: 64)
            if habit.kind == .build {
                let s = store.engine.buildStreak(habit.snapshot)
                VStack(spacing: 2) {
                    Text("\(s.current)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(s.current)))
                        .foregroundStyle(color.gradient)
                    Text(plural(s.current, "день подряд", "дня подряд", "дней подряд"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .animation(Motion.bouncy, value: s.current)
                Text(habit.scheduleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let q = store.engine.quitStreak(habit.snapshot, now: ctx.date)
                    VStack(spacing: 8) {
                        QuitCounter(seconds: q.current, color: color, showSeconds: true)
                        Text(q.relapseCount == 0 ? "без срывов с начала" : "без срыва · рекорд \(DurationText.human(q.best))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        MilestoneBar(days: q.current / 86_400, color: color, record: q.isRecordNow)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card(radius: 30, tint: color)
    }

    // MARK: - Действия

    @ViewBuilder
    private var buildActions: some View {
        let value = store.value(of: habit)
        let done = store.engine.isDone(value, goal: habit.goal)
        HStack(spacing: 12) {
            Button {
                if habit.goal.isBinary {
                    withAnimation(Motion.bouncy) { store.toggle(habit) }
                    if done { Haptics.tap() } else { burst += 1; Haptics.success() }
                } else {
                    withAnimation(Motion.bouncy) { store.add(habit.goal.step, to: habit) }
                    let nowDone = store.engine.isDone(value + habit.goal.step, goal: habit.goal)
                    if nowDone && !done { burst += 1; Haptics.success() } else { Haptics.soft() }
                }
            } label: {
                Label(actionTitle(done: done, value: value),
                      systemImage: done && habit.goal.isBinary ? "arrow.uturn.backward" : (habit.goal.isBinary ? "checkmark" : "plus"))
                    .contentTransition(.numericText())
            }
            .buttonStyle(PrimaryButtonStyle(color: done && habit.goal.isBinary ? .gray : habit.color))
            .overlay { SparkleBurst(trigger: burst, color: habit.color) }
        }
    }

    private func actionTitle(done: Bool, value: Double) -> String {
        let g = habit.goal
        if g.isBinary { return done ? "Отменить на сегодня" : "Отметить на сегодня" }
        return "+\(NumberText.value(g.step)) \(g.unit) · сегодня \(NumberText.value(value))"
    }

    private var quitActions: some View {
        Button { relapsing = true; Haptics.tap() } label: {
            Label(Copy.relapseButton, systemImage: "exclamationmark.triangle.fill")
        }
        .buttonStyle(PrimaryButtonStyle(color: Palette.danger))
    }

    // MARK: - Плитки

    @ViewBuilder
    private var tiles: some View {
        let snap = habit.snapshot
        let color = habit.color
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: cols, spacing: 12) {
            if habit.kind == .build {
                let s = store.engine.buildStreak(snap)
                StatTile(value: pluralDays(s.best), caption: "Лучшая серия", symbol: "crown.fill", color: color)
                StatTile(value: "\(Int((stats.completionRate(snap) * 100).rounded()))%", caption: "Выполнение за 30 дней", symbol: "chart.pie.fill", color: color)
                StatTile(value: "\(stats.doneDaysTotal(snap))", caption: "Всего дней с выполнением", symbol: "calendar", color: color)
                if habit.goal.isBinary {
                    StatTile(value: "\(stats.weeklyCounts(snap, weeks: 1).first?.count ?? 0) из 7", caption: "На этой неделе", symbol: "calendar.badge.clock", color: color)
                } else {
                    StatTile(value: "\(NumberText.value(stats.totalValue(snap))) \(habit.goal.unit)", caption: "Всего за всё время", symbol: "sum", color: color)
                }
            } else {
                let q = store.engine.quitStreak(snap)
                let unit = habit.unitName.isEmpty ? "раз" : habit.unitName
                StatTile(value: DurationText.human(q.best), caption: "Рекорд без срыва", symbol: "crown.fill", color: color)
                StatTile(value: "\(q.relapseCount)", caption: plural(q.relapseCount, "срыв", "срыва", "срывов") + " всего", symbol: "exclamationmark.triangle.fill", color: Palette.danger)
                if habit.baselinePerDay > 0 {
                    let avoided = stats.avoidedUnits(snap, baselinePerDay: habit.baselinePerDay)
                    StatTile(value: NumberText.value(avoided.rounded(.down)), caption: "\(unit) не употреблено", symbol: "leaf.fill", color: Palette.success)
                    if habit.costPerUnit > 0 {
                        StatTile(value: "\(NumberText.value((avoided * habit.costPerUnit).rounded(.down))) ₽", caption: "Сэкономлено", symbol: "banknote.fill", color: Palette.success)
                    } else {
                        StatTile(value: pluralDays(Calendar.habitFlow.daysBetween(habit.startDate, .now)), caption: "С начала отказа", symbol: "calendar", color: color)
                    }
                } else {
                    StatTile(value: pluralDays(Calendar.habitFlow.daysBetween(habit.startDate, .now)), caption: "С начала отказа", symbol: "calendar", color: color)
                    StatTile(value: NumberText.value(habit.relapses.reduce(0) { $0 + $1.amount }), caption: "\(unit) при срывах", symbol: "sum", color: Palette.warning)
                }
            }
        }
    }

    // MARK: - Графики

    @ViewBuilder
    private var charts: some View {
        let snap = habit.snapshot
        if habit.kind == .build {
            let weeks = stats.weeklyCounts(snap, weeks: 8)
            VStack(alignment: .leading, spacing: 12) {
                Text("По неделям").font(.headline)
                Chart(weeks) { w in
                    BarMark(x: .value("Неделя", w.weekStart, unit: .weekOfYear),
                            y: .value("Дней", w.count))
                        .foregroundStyle(habit.color.gradient)
                        .cornerRadius(6)
                }
                .chartYScale(domain: 0...7)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
                    }
                }
                .frame(height: 160)
            }
            .padding(16)
            .card()
        } else if !habit.relapses.isEmpty {
            let triggers = stats.triggers(snap).prefix(6)
            let months = stats.relapsesByMonth(snap, months: 6)
            VStack(alignment: .leading, spacing: 12) {
                Text("Что чаще всего срывает").font(.headline)
                Chart(Array(triggers)) { t in
                    BarMark(x: .value("Раз", t.count), y: .value("Причина", t.trigger))
                        .foregroundStyle(Palette.danger.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(t.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(1, triggers.count)) * 34 + 10)

                Divider().padding(.vertical, 4)

                Text("Срывы по месяцам").font(.headline)
                Chart(months) { m in
                    BarMark(x: .value("Месяц", m.monthStart, unit: .month), y: .value("Срывов", m.count))
                        .foregroundStyle(Palette.warning.gradient)
                        .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale(identifier: "ru_RU")))
                    }
                }
                .frame(height: 140)
            }
            .padding(16)
            .card()
        }
    }

    // MARK: - История срывов

    @ViewBuilder
    private var relapseHistory: some View {
        let list = habit.sortedRelapses
        VStack(alignment: .leading, spacing: 4) {
            Text("История срывов").font(.headline).padding(.bottom, 6)
            if list.isEmpty {
                Text("Срывов нет. Каждая минута идёт в серию.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { r in
                HStack(spacing: 12) {
                    Image(systemName: TriggerLibrary.shared.symbol(for: r.trigger))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.danger)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.danger.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.trigger.isEmpty ? "Без причины" : r.trigger)
                            .font(.subheadline.weight(.semibold))
                        Text(r.date.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "ru_RU"))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !r.note.isEmpty {
                            Text(r.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    Text("\(NumberText.value(r.amount)) \(habit.unitName.isEmpty ? "раз" : habit.unitName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Menu {
                        Button(role: .destructive) { relapseToDelete = r } label: { Label("Удалить запись", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                if r.id != list.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func show(_ text: String) {
        withAnimation(Motion.bouncy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(Motion.smooth) { if toast == text { toast = nil } }
        }
    }
}

/// Награды конкретной привычки: полученные цветные, будущие приглушённые.
struct AchievementsCard: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit

    var body: some View {
        let best: Int = habit.kind == .build
            ? store.engine.buildStreak(habit.snapshot).best
            : store.engine.quitStreak(habit.snapshot).bestDays
        let color = habit.color
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Награды").font(.headline)
                Spacer()
                Text("\(RewardEngine.achieved(bestDays: best).count) из \(RewardEngine.milestones.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                ForEach(RewardEngine.milestones) { m in
                    MilestoneBadge(milestone: m, unlocked: best >= m.days, color: color)
                }
            }
        }
        .padding(16)
        .card()
    }
}

struct MilestoneBadge: View {
    let milestone: Milestone
    let unlocked: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(unlocked ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
                Image(systemName: unlocked ? milestone.symbol : "lock.fill")
                    .font(.system(size: unlocked ? 20 : 14, weight: .semibold))
                    .foregroundStyle(unlocked ? Color.white : Color.secondary)
            }
            .frame(width: 48, height: 48)
            .shadow(color: unlocked ? color.opacity(0.4) : .clear, radius: 8, y: 3)
            Text(milestone.days < 365 ? "\(milestone.days) д" : "Год")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(unlocked ? .primary : .secondary)
        }
        .accessibilityLabel("\(milestone.title)\(unlocked ? ", получено" : "")")
    }
}
