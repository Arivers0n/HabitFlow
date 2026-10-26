import SwiftUI
import SwiftData

/// Общая картина: ключевые цифры, тепловая карта, привычки и награды.
struct ProgressScreen: View {
    @Environment(HabitStore.self) private var store
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder)
    private var habits: [Habit]
    @State private var opened: Habit?

    private let stats = StatsEngine()

    var body: some View {
        let accent = Appearance.shared.accent
        let build = habits.filter { $0.kind == .build }
        let quit = habits.filter { $0.kind == .quit }
        let bestOverall = store.bestDaysOverall(habits)
        let badges = habits.reduce(0) { acc, h in
            let best = h.kind == .build ? store.engine.buildStreak(h.snapshot).best : store.engine.quitStreak(h.snapshot).bestDays
            return acc + RewardEngine.achieved(bestDays: best).count
        }
        let week = build.isEmpty ? 0 : build.map { stats.completionRate($0.snapshot, days: 7) }.reduce(0, +) / Double(build.count)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FriendsEntry()
                    if habits.isEmpty {
                        EmptyStateCard(symbol: "chart.bar.xaxis", title: "Пока нечего считать",
                                       subtitle: "Добавь привычку на вкладке «Сегодня» — здесь появятся серии, графики и награды.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            StatTile(value: pluralDays(bestOverall), caption: "Лучшая серия среди всех", symbol: "crown.fill", color: Palette.warning)
                            StatTile(value: "\(Int((week * 100).rounded()))%", caption: "Выполнение за 7 дней", symbol: "chart.pie.fill", color: accent)
                            StatTile(value: "\(badges)", caption: plural(badges, "награда", "награды", "наград") + " получено", symbol: "medal.fill", color: Color(hex: "B65CFF"))
                            StatTile(value: "\(habits.count)", caption: plural(habits.count, "активная привычка", "активные привычки", "активных привычек"), symbol: "square.stack.3d.up.fill", color: Palette.success)
                        }

                        WeeklyReviewCard(habits: habits)

                        if !build.isEmpty {
                            Heatmap(habits: build, color: accent)
                        }

                        if !build.isEmpty {
                            SectionTitle(title: "Формирую").padding(.top, 6)
                            ForEach(build) { h in row(h) }
                        }
                        if !quit.isEmpty {
                            SectionTitle(title: "Отказываюсь").padding(.top, 6)
                            ForEach(quit) { h in row(h) }
                        }

                        IconRewardsCard(bestDays: bestOverall)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
            .navigationTitle("Прогресс")
            .navigationDestination(item: $opened) { HabitDetailView(habit: $0) }
            .navigationDestination(isPresented: Binding(get: { AppRouter.shared.showFriends },
                                                        set: { AppRouter.shared.showFriends = $0 })) { FriendsView() }
        }
    }

    private func row(_ h: Habit) -> some View {
        let color = h.color
        let snap = h.snapshot
        return Button { opened = h; Haptics.tap() } label: {
            HStack(spacing: 14) {
                HabitIcon(symbol: h.symbol, color: color, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.name).font(.headline).foregroundStyle(.primary)
                    if h.kind == .build {
                        let rate = stats.completionRate(snap)
                        HStack(spacing: 8) {
                            Capsule().fill(color.opacity(0.15)).frame(height: 6)
                                .overlay(alignment: .leading) {
                                    GeometryReader { g in Capsule().fill(color.gradient).frame(width: max(6, g.size.width * rate)) }
                                }
                            Text("\(Int((rate * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    } else {
                        let q = store.engine.quitStreak(snap)
                        Text("\(DurationText.human(q.current)) · рекорд \(DurationText.human(q.best))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if h.kind == .build {
                    let s = store.engine.buildStreak(snap)
                    Label("\(s.current)", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(s.current > 0 ? color : Color.secondary)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .card(radius: 22)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

/// Тепловая карта за 18 недель: насколько выполнены полезные привычки в каждый день.
struct Heatmap: View {
    @Environment(HabitStore.self) private var store
    let habits: [Habit]
    let color: Color

    private let weeks = 18

    var body: some View {
        let cal = Calendar.habitFlow
        let thisWeek = cal.startOfWeek(.now)
        let start = cal.addingDays(-7 * (weeks - 1), to: thisWeek)
        let data = ratios(from: start)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Последние 4 месяца").font(.headline)
                Spacer()
                HStack(spacing: 3) {
                    Text("меньше").font(.caption2).foregroundStyle(.secondary)
                    ForEach([0.0, 0.33, 0.66, 1.0], id: \.self) { v in
                        RoundedRectangle(cornerRadius: 3).fill(fill(v)).frame(width: 10, height: 10)
                    }
                    Text("больше").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.addingDays(w * 7 + d, to: start)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day > .now ? Color.clear : fill(data[cal.startOfDay(for: day)] ?? -1))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    private func fill(_ v: Double) -> Color {
        if v < 0 { return Color.primary.opacity(0.04) }
        if v == 0 { return Color.primary.opacity(0.08) }
        return color.opacity(0.25 + 0.75 * v)
    }

    /// Доля выполненных привычек по дням; −1 — день без запланированных.
    private func ratios(from start: Date) -> [Date: Double] {
        let cal = Calendar.habitFlow
        let engine = store.engine
        let prepared = habits.map { (h: $0, snap: $0.snapshot, totals: engine.dailyTotals($0.snapshot)) }
        var result: [Date: Double] = [:]
        var day = start
        let today = cal.startOfDay(for: .now)
        while day <= today {
            var due = 0, done = 0
            for p in prepared where cal.startOfDay(for: engine.effectiveStart(p.snap)) <= day {
                guard engine.isScheduled(day, p.h.schedule) else { continue }
                due += 1
                if engine.isDone(p.totals[day] ?? 0, goal: p.h.goal) { done += 1 }
            }
            result[day] = due == 0 ? -1 : Double(done) / Double(due)
            day = cal.addingDays(1, to: day)
        }
        return result
    }
}

/// Наградные иконки приложения: открываются лучшей серией.
struct IconRewardsCard: View {
    let bestDays: Int

    var body: some View {
        let locked = AppIcons.all.filter { $0.requiredDays > 0 }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Иконки за серии").font(.headline)
                Spacer()
                NavigationLink {
                    IconPickerView()
                } label: {
                    Text("Сменить").font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 12) {
                ForEach(locked) { icon in
                    let open = bestDays >= icon.requiredDays
                    VStack(spacing: 6) {
                        Image(icon.preview)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .saturation(open ? 1 : 0)
                            .opacity(open ? 1 : 0.45)
                            .overlay {
                                if !open {
                                    Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(.white)
                                }
                            }
                        Text(open ? icon.title : "\(icon.requiredDays) д")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(open ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .card()
    }
}


/// Вход в «Друзья»: круг аватарок и число хлопков.
private struct FriendsEntry: View {
    var body: some View {
        let store = FriendsStore.shared
        let people = store.circles.flatMap(\.members).filter { !$0.me }
        let unique = Array(Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).prefix(4)
        Button { AppRouter.shared.showFriends = true; Haptics.tap() } label: {
            HStack(spacing: 14) {
                ZStack {
                    if unique.isEmpty {
                        Image(systemName: "person.2.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(LinearGradient(colors: [Color(hex: "FF8FB8"), Color(hex: "B65CFF")],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                    } else {
                        HStack(spacing: -14) {
                            ForEach(Array(unique)) { m in
                                let c = CompanionCatalog.character(m.companion)
                                ZStack {
                                    Circle().fill(Color(hex: c?.tintHex ?? "4C8DFF").opacity(0.3))
                                    if let c, m.stage > 0 {
                                        Image(c.imageName).resizable().aspectRatio(contentMode: .fit).padding(4)
                                    } else {
                                        Text(String(m.name.prefix(1))).font(.subheadline.weight(.bold))
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Друзья и семья").font(.headline).foregroundStyle(.primary)
                    Text(unique.isEmpty ? "Серии вместе и поддержка друг друга" : "\(people.count) \(plural(people.count, "человек", "человека", "человек")) в кругах")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .card(radius: 22)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .task { if store.circles.isEmpty { await store.load() } }
    }
}
