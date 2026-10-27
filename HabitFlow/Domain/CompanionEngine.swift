import Foundation

// Логика напарника — чистый Swift, без интерфейса.
// Опыт не хранится, а каждый раз пересчитывается из истории привычек:
// его нельзя «нафармить» отметкой и снятием, он переживает бэкап
// и правильно меняется при отметках задним числом.

enum CompanionStage: Int, Sendable, Comparable {
    case egg, baby, teen, adult
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .egg: "Яйцо"
        case .baby: "Малыш"
        case .teen: "Подросток"
        case .adult: "Взрослый"
        }
    }
}

enum CompanionMood: String, Sendable, CaseIterable {
    /// Цели выполняются.
    case happy
    /// Обычный день.
    case calm
    /// Пропуски или давно не заходил.
    case sad
    /// Недавно был срыв — поддерживает, а не ругает.
    case caring

    var title: String {
        switch self {
        case .happy: "Радостный"
        case .calm: "Спокойный"
        case .sad: "Грустит"
        case .caring: "Рядом с тобой"
        }
    }
}

enum XPRules {
    static let habitDone = 10
    static let perfectDay = 30
    static let cleanDay = 15
    static let resisted = 5
    static let resistedPerDay = 3
    static let maxLevel = 50

    /// Сколько всего опыта нужно, чтобы достичь уровня n: 0, 60, 180, 360, 600…
    static func totalXP(forLevel n: Int) -> Int {
        let n = max(1, n)
        return 60 * n * (n - 1) / 2
    }

    static func level(for xp: Int) -> Int {
        var n = 1
        while n < maxLevel && xp >= totalXP(forLevel: n + 1) { n += 1 }
        return n
    }

    static func stage(for level: Int) -> CompanionStage {
        switch level {
        case ..<2: .egg
        case 2...4: .baby
        case 5...9: .teen
        default: .adult
        }
    }
}

struct LevelProgress: Equatable, Sendable {
    var level: Int
    var xpInLevel: Int
    var xpForNext: Int
    var fraction: Double
    var isMax: Bool

    init(xp: Int) {
        level = XPRules.level(for: xp)
        isMax = level >= XPRules.maxLevel
        let base = XPRules.totalXP(forLevel: level)
        let next = XPRules.totalXP(forLevel: level + 1)
        xpInLevel = xp - base
        xpForNext = next - base
        fraction = isMax ? 1 : min(1, max(0, Double(xpInLevel) / Double(xpForNext)))
    }
}

struct XPBreakdown: Equatable, Sendable {
    var habits = 0
    var perfectDays = 0
    var cleanDays = 0
    var resisted = 0
    /// Сколько опыта пришло сегодня (включая чистые сутки, закрывшиеся в полночь).
    var today = 0

    var total: Int { habits + perfectDays + cleanDays + resisted }
}

/// Сводка дня для настроения и фраз.
struct DaySummary: Equatable, Sendable {
    /// Привычки со строгим расписанием (каждый день / по дням), назначенные на день.
    var due: Int
    var done: Int
    /// Выполнено вообще, включая «N раз в неделю».
    var doneAny: Int
    /// Все цели дня так, как их показывает экран «Сегодня»: строгие привычки и «N раз в неделю».
    /// Кольцо, «X из Y» и фразы напарника берут числа отсюда, чтобы нигде не расходились.
    var scheduled: Int = 0
    var scheduledDone: Int = 0

    var ratio: Double? { due > 0 ? Double(done) / Double(due) : nil }
    var screenRatio: Double? { scheduled > 0 ? Double(scheduledDone) / Double(scheduled) : nil }
}

struct CompanionEngine: Sendable {
    var engine: StreakEngine
    var calendar: Calendar { engine.calendar }

    init(calendar: Calendar = .habitFlow) {
        engine = StreakEngine(calendar: calendar)
    }

    // MARK: - Опыт

    func xp(_ habits: [HabitSnapshot], now: Date = .now) -> XPBreakdown {
        var b = XPBreakdown()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.addingDays(-1, to: today)

        let builds = habits.filter { $0.kind == .build }
        let prepared = builds.map { (snap: $0, totals: engine.dailyTotals($0), start: calendar.startOfDay(for: engine.effectiveStart($0))) }

        // +10 за каждый день выполнения
        var doneDays: [Date: Int] = [:]
        for p in prepared {
            for (day, value) in p.totals where day <= today && engine.isDone(value, goal: p.snap.goal) {
                b.habits += XPRules.habitDone
                doneDays[day, default: 0] += 1
                if day == today { b.today += XPRules.habitDone }
            }
        }

        // +30 за день, когда закрыто всё строгое расписание
        if let first = prepared.map(\.start).min() {
            var day = first
            while day <= today {
                let due = prepared.filter { $0.start <= day && isStrict($0.snap.schedule) && engine.isScheduled(day, $0.snap.schedule) }
                if !due.isEmpty && due.allSatisfy({ engine.isDone($0.totals[day] ?? 0, goal: $0.snap.goal) }) {
                    b.perfectDays += XPRules.perfectDay
                    if day == today { b.today += XPRules.perfectDay }
                }
                day = calendar.addingDays(1, to: day)
            }
        }

        // +15 за каждые полные сутки без срыва и +5 за «устоял»
        for q in habits where q.kind == .quit {
            let startDay = calendar.startOfDay(for: engine.effectiveStart(q))
            let fullDays = max(0, calendar.daysBetween(startDay, today) - 1)
            if fullDays > 0 {
                let firstFull = calendar.addingDays(1, to: startDay)
                let relapseDays = Set(q.relapses.map { calendar.startOfDay(for: $0.date) }
                    .filter { $0 >= firstFull && $0 < today })
                b.cleanDays += (fullDays - relapseDays.count) * XPRules.cleanDay
                if yesterday >= firstFull && !relapseDays.contains(yesterday) {
                    b.today += XPRules.cleanDay
                }
            }

            var perDay: [Date: Int] = [:]
            for r in q.resisted where r <= now { perDay[calendar.startOfDay(for: r), default: 0] += 1 }
            for (day, n) in perDay {
                let gained = min(n, XPRules.resistedPerDay) * XPRules.resisted
                b.resisted += gained
                if day == today { b.today += gained }
            }
        }
        return b
    }

    /// Сколько опыта даст ещё одно «устоял» сегодня (0, если лимит исчерпан).
    func resistReward(_ q: HabitSnapshot, now: Date = .now) -> Int {
        let n = q.resisted.filter { calendar.isDate($0, inSameDayAs: now) }.count
        return n < XPRules.resistedPerDay ? XPRules.resisted : 0
    }

    private func isStrict(_ s: Schedule) -> Bool {
        if case .timesPerWeek = s { return false }
        return true
    }

    // MARK: - День и настроение

    func summary(_ habits: [HabitSnapshot], on day: Date) -> DaySummary {
        let d = calendar.startOfDay(for: day)
        var s = DaySummary(due: 0, done: 0, doneAny: 0)
        for h in habits where h.kind == .build {
            let start = calendar.startOfDay(for: engine.effectiveStart(h))
            guard start <= d else { continue }
            let done = engine.isDone(engine.dailyTotals(h)[d] ?? 0, goal: h.goal)
            let scheduled = engine.isScheduled(d, h.schedule)
            if done { s.doneAny += 1 }
            if scheduled {
                s.scheduled += 1
                if done { s.scheduledDone += 1 }
            }
            if isStrict(h.schedule) && scheduled {
                s.due += 1
                if done { s.done += 1 }
            }
        }
        return s
    }

    /// Настроение по последним суткам-двум. `gapSinceLastOpen` — сколько не заходил до этого раза.
    func mood(_ habits: [HabitSnapshot], gapSinceLastOpen: TimeInterval?, now: Date = .now) -> CompanionMood {
        let recentRelapse = habits.contains { h in
            h.kind == .quit && h.relapses.contains { $0.date <= now && now.timeIntervalSince($0.date) < 86_400 }
        }
        if recentRelapse { return .caring }

        let today = summary(habits, on: now)
        let yesterday = summary(habits, on: calendar.addingDays(-1, to: now))
        let hour = calendar.component(.hour, from: now)

        if let r = today.ratio, r >= 0.5 { return .happy }
        if today.ratio == nil && today.doneAny > 0 { return .happy }
        if today.doneAny > 0, yesterday.ratio == 1 { return .happy }

        // Долго не заходил — грустит, пока не сделаем хоть что-то сегодня
        if let gap = gapSinceLastOpen, gap >= 2 * 86_400, today.doneAny == 0 { return .sad }
        if let y = yesterday.ratio, y < 0.34, today.doneAny == 0, hour >= 12 { return .sad }

        let builds = habits.filter { $0.kind == .build }
        let quits = habits.filter { $0.kind == .quit }
        if builds.isEmpty && !quits.isEmpty &&
            quits.allSatisfy({ engine.quitStreak($0, now: now).current >= 86_400 }) {
            return .happy
        }
        return .calm
    }

    /// Первая невыполненная на сегодня привычка — для просьбы напарника.
    func questHabit(_ habits: [HabitSnapshot], now: Date = .now) -> HabitSnapshot? {
        let d = calendar.startOfDay(for: now)
        return habits.first { h in
            h.kind == .build && isStrict(h.schedule) && engine.isScheduled(d, h.schedule)
                && calendar.startOfDay(for: engine.effectiveStart(h)) <= d
                && !engine.isDone(engine.dailyTotals(h)[d] ?? 0, goal: h.goal)
        }
    }

    /// Самая длинная текущая серия без срыва — для похвалы.
    func bestQuit(_ habits: [HabitSnapshot], now: Date = .now) -> (name: String, days: Int)? {
        habits.filter { $0.kind == .quit }
            .map { ($0.name, engine.quitStreak($0, now: now).currentDays) }
            .filter { $0.1 >= 3 }
            .max { $0.1 < $1.1 }
            .map { (name: $0.0, days: $0.1) }
    }
}
