import SwiftUI

// MARK: - Полезная привычка

struct BuildHabitCard: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    var day: Date = .now
    var onOpen: () -> Void

    @State private var burst = 0
    @State private var askValue = false
    @State private var valueText = ""

    var body: some View {
        let ap = Appearance.shared
        let snap = habit.snapshot
        let streak = store.engine.buildStreak(snap)
        let value = store.value(of: habit, on: day)
        let goal = habit.goal
        let done = store.engine.isDone(value, goal: goal)
        let progress = min(1, value / goal.target)
        let color = habit.color
        let compact = ap.s.density == .compact

        HStack(spacing: 14) {
            HabitIcon(symbol: habit.symbol, color: color, size: compact ? 38 : 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if streak.current > 0 {
                        Label("\(streak.current)", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(streak.todayDone ? color : Color.secondary)
                            .contentTransition(.numericText())
                    }
                    Text(subtitle(value: value, goal: goal, streak: streak))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                if !goal.isBinary && !compact {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(color.gradient).frame(width: max(6, g.size.width * progress))
                            }
                        }
                        .padding(.top, 2)
                        .animation(Motion.bouncy, value: progress)
                }
            }
            Spacer(minLength: 4)

            CheckButton(progress: progress, done: done, color: color, isVolume: !goal.isBinary, burst: burst) {
                tap(done: done, value: value)
            }
            .contextMenu {
                if !goal.isBinary {
                    Button { valueText = ""; askValue = true } label: { Label("Ввести количество", systemImage: "number") }
                    Button { store.undoLast(habit, on: day); Haptics.tap() } label: { Label("Отменить последнее", systemImage: "arrow.uturn.backward") }
                }
                Button(role: .destructive) { withAnimation(Motion.smooth) { store.clear(habit, on: day) } } label: {
                    Label("Сбросить день", systemImage: "xmark.circle")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 12 : 16)
        .card(tint: done ? color : nil)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
        .animation(Motion.smooth, value: done)
        .alert("Сколько добавить, \(goal.unit)?", isPresented: $askValue) {
            TextField(NumberText.value(goal.step), text: $valueText)
                .keyboardType(.decimalPad)
            Button("Добавить") {
                let v = Double(valueText.replacingOccurrences(of: ",", with: ".")) ?? 0
                if v > 0 { add(v, wasDone: done, value: value) }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func subtitle(value: Double, goal: Goal, streak: BuildStreak) -> String {
        if !goal.isBinary {
            return "\(NumberText.value(value)) / \(NumberText.value(goal.target)) \(goal.unit)"
        }
        if case .timesPerWeek = habit.schedule {
            return "\(streak.weekDone) из \(streak.weekTarget) на неделе"
        }
        return habit.scheduleText
    }

    private func tap(done: Bool, value: Double) {
        if habit.goal.isBinary {
            withAnimation(Motion.bouncy) { store.toggle(habit, on: day) }
            if done { Haptics.tap() } else { burst += 1; Haptics.success() }
        } else {
            add(habit.goal.step, wasDone: done, value: value)
        }
    }

    private func add(_ v: Double, wasDone: Bool, value: Double) {
        withAnimation(Motion.bouncy) { store.add(v, to: habit, on: day) }
        let nowDone = store.engine.isDone(value + v, goal: habit.goal)
        if nowDone && !wasDone { burst += 1; Haptics.success() } else { Haptics.soft() }
    }
}

/// Круглая кнопка отметки: кольцо прогресса, заливка при выполнении и искры.
struct CheckButton: View {
    var progress: Double
    var done: Bool
    var color: Color
    var isVolume: Bool
    var burst: Int
    var size: CGFloat = 56
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                ProgressRing(progress: progress, color: color, lineWidth: 5)
                Circle()
                    .fill(color.gradient)
                    .padding(7)
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)
                Image(systemName: done ? "checkmark" : (isVolume ? "plus" : "checkmark"))
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(done ? Color.white : color.opacity(isVolume ? 1 : 0.35))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: burst)
                SparkleBurst(trigger: burst, color: color)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .animation(Motion.bouncy, value: done)
            .animation(Motion.bouncy, value: progress)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(done ? "Выполнено" : "Отметить")
    }
}

/// Короткий разлёт искр вокруг кнопки при выполнении.
struct SparkleBurst: View {
    var trigger: Int
    var color: Color
    @State private var fly = false
    @State private var visible = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * 2 * .pi
                Circle()
                    .fill(i.isMultiple(of: 2) ? color : .white)
                    .frame(width: i.isMultiple(of: 2) ? 6 : 4)
                    .offset(x: fly ? cos(angle) * 40 : 0, y: fly ? sin(angle) * 40 : 0)
                    .opacity(visible ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard Motion.enabled else { return }
            fly = false
            visible = true
            withAnimation(.easeOut(duration: 0.55)) { fly = true }
            withAnimation(.easeIn(duration: 0.3).delay(0.3)) { visible = false }
        }
    }
}

// MARK: - Отказ от вредного

struct QuitHabitCard: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    var onRelapse: () -> Void
    var onOpen: () -> Void

    var body: some View {
        let ap = Appearance.shared
        let color = habit.color
        let compact = ap.s.density == .compact
        // Снимок один на пересчёт карточки: внутри таймлайна меняется только «сейчас», а не данные.
        let snap = habit.snapshot

        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(spacing: 12) {
                HabitIcon(symbol: habit.symbol, color: color, size: compact ? 36 : 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(.headline).lineLimit(1)
                    let q = store.engine.quitStreak(snap)
                    Text(q.relapseCount == 0 ? "Без срывов с начала" : "Рекорд: \(DurationText.human(q.best))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            TimelineView(.periodic(from: .now, by: ap.s.liveSeconds ? 1 : 30)) { ctx in
                let q = store.engine.quitStreak(snap, now: ctx.date)
                VStack(alignment: .leading, spacing: 10) {
                    QuitCounter(seconds: q.current, color: color, showSeconds: ap.s.liveSeconds, big: !compact)
                    if !compact {
                        MilestoneBar(days: q.current / 86_400, color: color, record: q.isRecordNow)
                        if ap.s.showSavings, let saving = savingsText(snap, now: ctx.date) {
                            Label(saving, systemImage: "leaf.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            QuitActions(habit: habit, onRelapse: onRelapse)
        }
        .padding(16)
        .card(tint: color)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private func savingsText(_ snap: HabitSnapshot, now: Date) -> String? {
        guard habit.baselinePerDay > 0 else { return nil }
        let avoided = StatsEngine().avoidedUnits(snap, baselinePerDay: habit.baselinePerDay, now: now)
        let unit = habit.unitName.isEmpty ? "раз" : habit.unitName
        var text = "Избежал: \(NumberText.value(avoided.rounded(.down))) \(unit)"
        if habit.costPerUnit > 0 {
            text += " · \(NumberText.value((avoided * habit.costPerUnit).rounded(.down))) ₽"
        }
        return text
    }
}

/// Две крупные кнопки под большой палец: «Устоял» и «Был срыв».
struct QuitActions: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    var onRelapse: () -> Void
    var large = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                let xp = store.recordResist(habit)
                CompanionManager.shared.showResist(habit, xp: xp)
            } label: {
                pill("Устоял", "hand.raised.fill", Palette.success)
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Отметить, что удалось не поддаться искушению")

            Button {
                onRelapse()
                Haptics.tap()
            } label: {
                pill(Copy.relapseButton, "exclamationmark.triangle.fill", Palette.danger)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func pill(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font((large ? Font.headline : .subheadline).weight(.semibold))
            .foregroundStyle(large ? Color.white : color)
            .frame(maxWidth: .infinity, minHeight: large ? 56 : 44)
            .background(
                RoundedRectangle(cornerRadius: large ? 18 : 14, style: .continuous)
                    .fill(large ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15)))
            )
    }
}

/// Крупный счётчик «12 д 04 ч 31 м».
struct QuitCounter: View {
    var seconds: TimeInterval
    var color: Color
    var showSeconds: Bool
    var big: Bool = true

    var body: some View {
        let p = DurationText.parts(seconds)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            unit(p.days, "д")
            unit(p.hours, "ч", pad: true)
            unit(p.minutes, "м", pad: true)
            if showSeconds { unit(p.seconds, "с", pad: true) }
        }
    }

    private func unit(_ v: Int, _ label: String, pad: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(pad ? String(format: "%02d", v) : "\(v)")
                .font(.system(size: big ? 34 : 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(v)))
                .animation(Motion.smooth, value: v)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(.trailing, 6)
        }
    }
}

/// Полоска до следующей награды.
struct MilestoneBar: View {
    var days: Double
    var color: Color
    var record: Bool

    var body: some View {
        let p = RewardEngine.progressToNext(days: days)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color.gradient).frame(width: max(6, g.size.width * p.progress))
                }
            }
            .frame(height: 6)
            HStack {
                if let next = p.next {
                    Text("До «\(next.title)» — \(remaining(next.days))")
                } else {
                    Text("Все награды получены")
                }
                Spacer()
                if record {
                    Label(Copy.newRecord, systemImage: "crown.fill")
                        .foregroundStyle(Palette.warning)
                        .font(.caption.weight(.semibold))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func remaining(_ target: Int) -> String {
        let left = Double(target) - days
        if left >= 1 { return pluralDays(Int(left.rounded(.up))) }
        return DurationText.human(left * 86_400)
    }
}
