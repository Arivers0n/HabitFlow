import Foundation

struct WeekCount: Identifiable, Hashable, Sendable {
    let weekStart: Date
    let count: Int
    var id: Date { weekStart }
}

struct TriggerCount: Identifiable, Hashable, Sendable {
    let trigger: String
    let count: Int
    var id: String { trigger }
}

struct MonthCount: Identifiable, Hashable, Sendable {
    let monthStart: Date
    let count: Int
    let amount: Double
    var id: Date { monthStart }
}

struct StatsEngine: Sendable {
    var engine: StreakEngine
    var calendar: Calendar { engine.calendar }

    init(calendar: Calendar = .habitFlow) {
        engine = StreakEngine(calendar: calendar)
    }

    /// Доля выполненных запланированных дней за последние `days` дней (без сегодняшнего, если он ещё не закрыт).
    func completionRate(_ h: HabitSnapshot, days: Int = 30, now: Date = .now) -> Double {
        let totals = engine.dailyTotals(h)
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: engine.effectiveStart(h))
        let from = max(start, calendar.addingDays(-(days - 1), to: today))
        guard from <= today else { return 0 }

        var done = 0
        var planned = 0
        var day = from
        while day <= today {
            let ok = engine.isDone(totals[day] ?? 0, goal: h.goal)
            let isToday = day == today
            if ok { done += 1 }
            if engine.isScheduled(day, h.schedule), !(isToday && !ok) { planned += 1 }
            day = calendar.addingDays(1, to: day)
        }

        if case .timesPerWeek(let n) = h.schedule {
            let span = Double(calendar.daysBetween(from, today) + 1)
            let expected = max(1, Double(n) * span / 7)
            return min(1, Double(done) / expected)
        }
        guard planned > 0 else { return done > 0 ? 1 : 0 }
        return min(1, Double(done) / Double(planned))
    }

    /// Сколько дней выполнено по неделям, последние `weeks` недель включая текущую.
    func weeklyCounts(_ h: HabitSnapshot, weeks: Int = 8, now: Date = .now) -> [WeekCount] {
        let totals = engine.dailyTotals(h)
        let thisWeek = calendar.startOfWeek(now)
        return (0..<weeks).reversed().map { back in
            let ws = calendar.addingDays(-7 * back, to: thisWeek)
            let count = (0..<7).reduce(0) { acc, i in
                acc + (engine.isDone(totals[calendar.addingDays(i, to: ws)] ?? 0, goal: h.goal) ? 1 : 0)
            }
            return WeekCount(weekStart: ws, count: count)
        }
    }

    func totalValue(_ h: HabitSnapshot) -> Double {
        h.checkIns.reduce(0) { $0 + $1.value }
    }

    func doneDaysTotal(_ h: HabitSnapshot) -> Int {
        engine.dailyTotals(h).values.filter { engine.isDone($0, goal: h.goal) }.count
    }

    /// Частота триггеров срывов, по убыванию.
    func triggers(_ h: HabitSnapshot) -> [TriggerCount] {
        var map: [String: Int] = [:]
        for r in h.relapses {
            let key = r.trigger.isEmpty ? "Без причины" : r.trigger
            map[key, default: 0] += 1
        }
        return map.map { TriggerCount(trigger: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.trigger < $1.trigger }
    }

    /// Срывы по месяцам за последние `months` месяцев.
    func relapsesByMonth(_ h: HabitSnapshot, months: Int = 6, now: Date = .now) -> [MonthCount] {
        let thisMonth = calendar.dateInterval(of: .month, for: now)!.start
        return (0..<months).reversed().map { back in
            let ms = calendar.date(byAdding: .month, value: -back, to: thisMonth)!
            let me = calendar.date(byAdding: .month, value: 1, to: ms)!
            let inMonth = h.relapses.filter { $0.date >= ms && $0.date < me }
            return MonthCount(monthStart: ms, count: inMonth.count,
                              amount: inMonth.reduce(0) { $0 + $1.amount })
        }
    }

    /// Сколько единиц удалось не употребить: обычная норма × дни − то, что было при срывах.
    func avoidedUnits(_ h: HabitSnapshot, baselinePerDay: Double, now: Date = .now) -> Double {
        guard baselinePerDay > 0 else { return 0 }
        let days = max(0, now.timeIntervalSince(engine.effectiveStart(h)) / 86_400)
        let consumed = h.relapses.filter { $0.date <= now }.reduce(0) { $0 + $1.amount }
        return max(0, baselinePerDay * days - consumed)
    }
}
