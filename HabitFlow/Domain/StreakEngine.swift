import Foundation

/// Серия для полезной привычки. Считается в днях выполнения.
struct BuildStreak: Equatable, Sendable {
    var current: Int
    var best: Int
    /// Сумма за сегодня в единицах цели.
    var todayValue: Double
    /// 0…1, доля дневной цели.
    var todayProgress: Double
    var todayDone: Bool
    /// Для «N раз в неделю»: выполнено дней на этой неделе и сколько нужно.
    var weekDone: Int
    var weekTarget: Int
    var isScheduledToday: Bool
}

/// Серия для отказа от вредного. Считается во времени с последнего срыва.
struct QuitStreak: Equatable, Sendable {
    /// Сколько прошло с начала или последнего срыва.
    var current: TimeInterval
    /// Самый длинный промежуток без срыва, включая текущий.
    var best: TimeInterval
    /// Лучший промежуток до текущего — его показываем как «рекорд» после срыва.
    var previousBest: TimeInterval
    var since: Date
    var relapseCount: Int

    var currentDays: Int { Int(current / 86_400) }
    var bestDays: Int { Int(best / 86_400) }
    /// Сейчас идёт рекордная серия (и это не первая попытка).
    var isRecordNow: Bool { relapseCount > 0 && current >= previousBest && current > 0 }
}

struct StreakEngine: Sendable {
    var calendar: Calendar

    init(calendar: Calendar = .habitFlow) {
        self.calendar = calendar
    }

    // MARK: - Общие помощники

    /// Сумма значений по дням (ключ — начало дня).
    func dailyTotals(_ h: HabitSnapshot) -> [Date: Double] {
        var totals: [Date: Double] = [:]
        for c in h.checkIns {
            totals[calendar.startOfDay(for: c.date), default: 0] += c.value
        }
        return totals
    }

    func isScheduled(_ day: Date, _ schedule: Schedule) -> Bool {
        switch schedule {
        case .daily, .timesPerWeek: return true
        case .weekdays(let days): return days.contains(calendar.component(.weekday, from: day))
        }
    }

    func isDone(_ value: Double, goal: Goal) -> Bool {
        value + 1e-9 >= goal.target
    }

    /// Фактическое начало: дата старта или самая ранняя запись, если её внесли задним числом.
    func effectiveStart(_ h: HabitSnapshot) -> Date {
        var start = h.startDate
        switch h.kind {
        case .build:
            if let first = h.checkIns.map(\.date).min(), first < start { start = first }
        case .quit:
            if let first = h.relapses.map(\.date).min(), first < start { start = first }
        }
        return start
    }

    // MARK: - Полезные привычки

    func buildStreak(_ h: HabitSnapshot, now: Date = .now) -> BuildStreak {
        let totals = dailyTotals(h)
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: effectiveStart(h))
        let todayValue = totals[today] ?? 0
        let todayDone = isDone(todayValue, goal: h.goal)
        let progress = h.goal.target > 0 ? min(1, todayValue / h.goal.target) : 0

        var current = 0
        var best = 0
        var weekDone = 0
        var weekTarget = 0

        switch h.schedule {
        case .daily, .weekdays:
            // Один проход вперёд: серия растёт в выполненные дни,
            // обнуляется в пропущенные запланированные. Сегодня серию не рвёт.
            var run = 0
            var day = start
            while day <= today {
                let done = isDone(totals[day] ?? 0, goal: h.goal)
                if done {
                    run += 1
                } else if isScheduled(day, h.schedule) && day < today {
                    run = 0
                }
                best = max(best, run)
                day = calendar.addingDays(1, to: day)
            }
            current = run
            if case .weekdays(let set) = h.schedule {
                weekTarget = set.count
                weekDone = doneDays(inWeekOf: today, totals: totals, goal: h.goal)
            } else {
                weekTarget = 7
                weekDone = doneDays(inWeekOf: today, totals: totals, goal: h.goal)
            }

        case .timesPerWeek(let n):
            // Серия держится, пока каждая прошедшая неделя набрала норму.
            // Первая неделя может быть неполной — для неё норма уменьшается.
            let needed = max(1, n)
            var run = 0
            var weekStart = calendar.startOfWeek(start)
            let thisWeek = calendar.startOfWeek(today)
            while weekStart <= thisWeek {
                let count = doneDays(inWeekOf: weekStart, totals: totals, goal: h.goal)
                let available = availableDays(inWeekOf: weekStart, from: start)
                let norm = min(needed, available)
                if weekStart == thisWeek {
                    run += count
                } else if count >= norm {
                    run += count
                } else {
                    run = 0
                }
                best = max(best, run)
                weekStart = calendar.addingDays(7, to: weekStart)
            }
            current = run
            weekTarget = needed
            weekDone = doneDays(inWeekOf: today, totals: totals, goal: h.goal)
        }

        return BuildStreak(current: current, best: best, todayValue: todayValue,
                           todayProgress: progress, todayDone: todayDone,
                           weekDone: weekDone, weekTarget: weekTarget,
                           isScheduledToday: isScheduled(today, h.schedule))
    }

    private func doneDays(inWeekOf date: Date, totals: [Date: Double], goal: Goal) -> Int {
        let ws = calendar.startOfWeek(date)
        return (0..<7).reduce(0) { acc, i in
            acc + (isDone(totals[calendar.addingDays(i, to: ws)] ?? 0, goal: goal) ? 1 : 0)
        }
    }

    private func availableDays(inWeekOf weekStart: Date, from start: Date) -> Int {
        let ws = calendar.startOfWeek(weekStart)
        let begin = max(ws, start)
        return max(0, min(7, calendar.daysBetween(begin, calendar.addingDays(7, to: ws))))
    }

    // MARK: - Отказ от вредного

    func quitStreak(_ h: HabitSnapshot, now: Date = .now) -> QuitStreak {
        let start = effectiveStart(h)
        let resets = h.relapses.map(\.date).filter { $0 <= now }.sorted()
        var points = [start]
        points.append(contentsOf: resets)

        var previousBest: TimeInterval = 0
        for i in 1..<max(points.count, 1) where i < points.count {
            previousBest = max(previousBest, points[i].timeIntervalSince(points[i - 1]))
        }
        let since = points.last ?? start
        let current = max(0, now.timeIntervalSince(since))
        return QuitStreak(current: current,
                          best: max(previousBest, current),
                          previousBest: previousBest,
                          since: since,
                          relapseCount: resets.count)
    }

    // MARK: - Календарь

    func status(of day: Date, for h: HabitSnapshot, totals: [Date: Double]? = nil, now: Date = .now) -> DayStatus {
        let d = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: effectiveStart(h))
        if d > today { return .future }
        if d < start { return .beforeStart }

        switch h.kind {
        case .quit:
            let hasRelapse = h.relapses.contains { calendar.isDate($0.date, inSameDayAs: d) }
            return hasRelapse ? .relapse : .clean
        case .build:
            let value = (totals ?? dailyTotals(h))[d] ?? 0
            if isDone(value, goal: h.goal) { return .done }
            if value > 0 { return d == today ? .pending : .partial }
            if d == today { return isScheduled(d, h.schedule) ? .pending : .rest }
            if case .timesPerWeek = h.schedule { return .rest }
            return isScheduled(d, h.schedule) ? .missed : .rest
        }
    }
}
