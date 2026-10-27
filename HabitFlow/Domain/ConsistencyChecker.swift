import Foundation

// Проверка логики и данных (QA). Ищет нестыковки: привычка выполнена, а опыт не начислен;
// цифры на экранах не совпадают; серия длиннее истории; пустое расписание и т. п.
//
// Главный приём — независимый пересчёт: опыт, серии и счётчики дня считаются здесь
// вторым, отдельным способом (обратным обходом дней, а не прямым) и сверяются с движками.
// Если два способа дали разные числа — одна из реализаций неверна, и это ошибка в логике.

enum QASeverity: Int, Codable, Comparable, Sendable {
    case info = 0, warning = 1, error = 2

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .info: "Заметка"
        case .warning: "Предупреждение"
        case .error: "Ошибка"
        }
    }
}

struct QAIssue: Codable, Equatable, Identifiable, Sendable {
    /// Стабильный код правила: по нему удобно искать место в коде.
    var code: String
    var severity: QASeverity
    var habit: String?
    var message: String
    /// Где искать причину или что сделать.
    var hint: String

    var id: String { "\(code)|\(habit ?? "")|\(message)" }
}

/// Что показывают экраны прямо сейчас — это сверяется с пересчётом по истории.
struct QADisplayed: Equatable, Sendable {
    var xpTotal: Int? = nil
    var level: Int? = nil
    var stage: CompanionStage? = nil
    var mood: CompanionMood? = nil
    /// Числа «X из Y» на экране «Сегодня».
    var todayScheduled: Int? = nil
    var todayDone: Int? = nil
}

struct QAReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var habitsChecked: Int
    var issues: [QAIssue]

    var isClean: Bool { issues.isEmpty }
    var errors: Int { issues.filter { $0.severity == .error }.count }
    var warnings: Int { issues.filter { $0.severity == .warning }.count }
    var infos: Int { issues.filter { $0.severity == .info }.count }

    /// «Нестыковок нет» или «2 ошибки, 1 предупреждение».
    var summary: String {
        if issues.isEmpty { return "Нестыковок нет" }
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) \(plural(errors, "ошибка", "ошибки", "ошибок"))") }
        if warnings > 0 { parts.append("\(warnings) \(plural(warnings, "предупреждение", "предупреждения", "предупреждений"))") }
        if infos > 0 { parts.append("\(infos) \(plural(infos, "заметка", "заметки", "заметок"))") }
        return parts.joined(separator: ", ")
    }

    func json() -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Короткая сводка для ИИ: только ошибки и предупреждения, самое важное.
    func promptText(limit: Int = 6) -> String {
        let important = issues.filter { $0.severity >= .warning }.prefix(limit)
        guard !important.isEmpty else { return "" }
        return important.map { i in
            let who = i.habit.map { "«\($0)»: " } ?? ""
            return "• [\(i.severity.title.lowercased())] \(who)\(i.message)"
        }.joined(separator: "\n")
    }
}

struct ConsistencyChecker: Sendable {
    var calendar: Calendar
    private var engine: StreakEngine
    private var companion: CompanionEngine

    init(calendar: Calendar = .habitFlow) {
        self.calendar = calendar
        engine = StreakEngine(calendar: calendar)
        companion = CompanionEngine(calendar: calendar)
    }

    /// Дальше этого в прошлом дату старта считаем ошибкой данных (и не гоняем по ней циклы).
    private static let oldestSaneYear = 2000

    func check(_ habits: [HabitSnapshot], displayed: QADisplayed? = nil, now: Date = .now) -> QAReport {
        var issues: [QAIssue] = []
        func add(_ code: String, _ severity: QASeverity, _ habit: String?, _ message: String, _ hint: String) {
            issues.append(QAIssue(code: code, severity: severity, habit: habit, message: message, hint: hint))
        }

        var sane: [HabitSnapshot] = []
        for h in habits {
            let name = h.name.isEmpty ? "(без названия)" : h.name
            let ok = checkHabit(h, name: name, now: now, add: add)
            if ok { sane.append(h) }
        }

        checkXP(sane, now: now, add: add)
        if let displayed { checkDisplayed(sane, displayed, now: now, add: add) }

        let sorted = issues.sorted { a, b in
            a.severity != b.severity ? a.severity > b.severity : (a.code != b.code ? a.code < b.code : a.message < b.message)
        }
        return QAReport(generatedAt: now, habitsChecked: habits.count, issues: sorted)
    }

    // MARK: - Одна привычка

    typealias Adder = (_ code: String, _ severity: QASeverity, _ habit: String?, _ message: String, _ hint: String) -> Void

    /// Возвращает false, если данные привычки настолько испорчены, что считать по ней серии нельзя.
    private func checkHabit(_ h: HabitSnapshot, name: String, now: Date, add: Adder) -> Bool {
        let today = calendar.startOfDay(for: now)
        let nameOrNil: String? = name

        if h.name.trimmingCharacters(in: .whitespaces).isEmpty {
            add("H01", .warning, nil, "Привычка без названия.", "Редактор должен не давать сохранить пустое имя.")
        }

        // Цель и шаг
        let g = h.goal
        if !g.target.isFinite || g.target <= 0 {
            add("G01", .error, nameOrNil, "Цель дня не больше нуля (\(g.target)).", "Habit.goal / HabitDraft.apply: нужно target > 0.")
        } else if g.target < 0.001 {
            add("G02", .warning, nameOrNil, "Цель дня почти нулевая — любая отметка её выполняет.", "Проверить значение goalTarget.")
        }
        if !g.step.isFinite || g.step <= 0 {
            add("G03", .error, nameOrNil, "Шаг кнопки «+» не больше нуля (\(g.step)).", "Habit.goal: нужно step > 0.")
        } else if !g.isBinary && g.step > g.target {
            add("G04", .warning, nameOrNil, "Шаг «+» больше цели дня: одно нажатие перепрыгивает цель.", "В редакторе ограничить шаг целью.")
        }

        // Расписание
        switch h.schedule {
        case .weekdays(let days):
            if days.isEmpty {
                add("S01", .error, nameOrNil, "В расписании «по дням» не выбрано ни одного дня — привычка никогда не запланирована.", "HabitDraft: не давать сохранять пустой набор дней.")
            } else if days.contains(where: { !(1...7).contains($0) }) {
                add("S02", .error, nameOrNil, "В расписании есть номера дней вне 1…7.", "Habit.days(fromMask:) / weekdaysMask.")
            }
        case .timesPerWeek(let n):
            if n < 1 || n > 7 {
                add("S03", .warning, nameOrNil, "«N раз в неделю»: N = \(n), допустимо 1…7.", "Habit.schedule ограничивает 1…7.")
            }
        case .daily:
            break
        }

        // Даты
        let oldest = calendar.date(from: DateComponents(year: Self.oldestSaneYear, month: 1, day: 1)) ?? .distantPast
        let start = engineStart(h)
        if start < oldest {
            add("D02", .error, nameOrNil, "Дата начала слишком далеко в прошлом.", "Проверить startDate и даты отметок — расчёты по такой привычке пропущены.")
            return false
        }
        if h.startDate > now.addingTimeInterval(86_400) {
            add("D01", .warning, nameOrNil, "Дата старта в будущем — привычка пока ничего не засчитывает.", "Проверить startDate.")
        }

        let farFuture = now.addingTimeInterval(36 * 3_600)

        // Отметки
        let badValues = h.checkIns.filter { !$0.value.isFinite || $0.value <= 0 }.count
        if badValues > 0 {
            add("C01", .error, nameOrNil, "Отметок с нулевым, отрицательным или нечисловым значением: \(badValues).", "HabitStore.add принимает только value > 0.")
        }
        let future = h.checkIns.filter { $0.date > farFuture }.count
        if future > 0 {
            add("C02", .warning, nameOrNil, "Отметок с датой в будущем: \(future).", "Такие отметки не влияют на серию, пока не наступит их день.")
        }

        var sums: [Date: Double] = [:]
        for c in h.checkIns where c.value.isFinite { sums[calendar.startOfDay(for: c.date), default: 0] += c.value }
        if g.isBinary && g.target.isFinite && g.target > 0 {
            let doubled = sums.filter { $0.value > g.target * 1.0001 }.count
            if doubled > 0 {
                add("C03", .warning, nameOrNil, "Дней, где простая отметка записана больше одного раза: \(doubled).", "Обычно след слияния при синхронизации или двойного нажатия: toggle должен добавлять ровно недостающее.")
            }
        }

        // Тип привычки и её записи
        switch h.kind {
        case .build:
            if !h.relapses.isEmpty {
                add("K01", .warning, nameOrNil, "У полезной привычки есть срывы (\(h.relapses.count)).", "Срывы относятся только к привычкам «Отказываюсь».")
            }
            if !h.resisted.isEmpty {
                add("K03", .info, nameOrNil, "У полезной привычки есть «устоял» (\(h.resisted.count)).", "Эти записи не дают опыта.")
            }
        case .quit:
            if !h.checkIns.isEmpty {
                add("K02", .warning, nameOrNil, "У привычки «Отказываюсь» есть отметки выполнения (\(h.checkIns.count)).", "Для отказа считаются только срывы и «устоял».")
            }
        }
        let futureRelapses = h.relapses.filter { $0.date > now.addingTimeInterval(300) }.count
        if futureRelapses > 0 {
            add("R01", .warning, nameOrNil, "Срывов с датой в будущем: \(futureRelapses).", "Срыв нельзя записать на будущее — RelapseSheet должен ограничивать дату.")
        }
        let badAmounts = h.relapses.filter { !$0.amount.isFinite || $0.amount <= 0 }.count
        if badAmounts > 0 {
            add("R02", .warning, nameOrNil, "Срывов с нулевым количеством: \(badAmounts).", "Количество срыва должно быть больше нуля.")
        }

        // Серии
        checkStreaks(h, name: nameOrNil, now: now, today: today, start: start, sums: sums, add: add)
        return true
    }

    private func engineStart(_ h: HabitSnapshot) -> Date { engine.effectiveStart(h) }

    private func checkStreaks(_ h: HabitSnapshot, name: String?, now: Date, today: Date, start: Date,
                              sums: [Date: Double], add: Adder) {
        let startDay = calendar.startOfDay(for: start)
        let daysSinceStart = max(0, calendar.daysBetween(startDay, today)) + 1

        switch h.kind {
        case .build:
            let s = engine.buildStreak(h, now: now)
            if s.current > daysSinceStart {
                add("T01", .error, name, "Серия \(s.current) дн. длиннее истории привычки (\(daysSinceStart) дн.).", "StreakEngine.buildStreak: счётчик run.")
            }
            if s.best < s.current {
                add("T02", .error, name, "Рекорд (\(s.best)) меньше текущей серии (\(s.current)).", "StreakEngine.buildStreak: best = max(best, run).")
            }
            if !s.todayProgress.isFinite || s.todayProgress < 0 || s.todayProgress > 1.0000001 {
                add("T03", .error, name, "Прогресс сегодня вне 0…100 % (\(s.todayProgress)).", "StreakEngine.buildStreak: min(1, …).")
            }
            let calendarSaysDone = engine.status(of: today, for: h, now: now) == .done
            if calendarSaysDone != s.todayDone {
                add("V07", .error, name, "Календарь и карточка по-разному отвечают, выполнена ли привычка сегодня.", "StreakEngine.status и buildStreak.todayDone должны совпадать.")
            }
            // Независимый пересчёт серии обратным обходом (для «N раз в неделю» серия считается неделями — пропускаем).
            if case .timesPerWeek = h.schedule { break }
            var run = 0
            var day = today
            while day >= startDay {
                if engine.isDone(sums[day] ?? 0, goal: h.goal) {
                    run += 1
                } else if engine.isScheduled(day, h.schedule) && day < today {
                    break
                }
                day = calendar.addingDays(-1, to: day)
            }
            if run != s.current {
                add("T04", .error, name, "Серия по движку — \(s.current), а обратным пересчётом по отметкам — \(run).", "StreakEngine.buildStreak: сравнить прямой и обратный проход.")
            }

        case .quit:
            let q = engine.quitStreak(h, now: now)
            let limit = max(0, now.timeIntervalSince(start)) + 1
            if q.current < 0 || q.current > limit {
                add("T05", .error, name, "Серия без срыва (\(DurationText.compact(q.current))) не помещается в историю привычки.", "StreakEngine.quitStreak: since и current.")
            }
            if q.best + 0.001 < q.current {
                add("T06", .error, name, "Рекорд меньше текущей серии без срыва.", "StreakEngine.quitStreak: best = max(previousBest, current).")
            }
            let past = h.relapses.filter { $0.date <= now }
            if q.relapseCount != past.count {
                add("T07", .error, name, "Срывов по движку \(q.relapseCount), а в истории \(past.count).", "StreakEngine.quitStreak: фильтр date <= now.")
            }
            let expectedSince = past.map(\.date).max() ?? start
            if abs(q.since.timeIntervalSince(expectedSince)) > 0.5 {
                add("T08", .error, name, "Отсчёт серии идёт не от последнего срыва.", "StreakEngine.quitStreak: since.")
            }
        }
    }

    // MARK: - Опыт

    private struct Recount {
        var habits = 0
        var perfect = 0
        var clean = 0
        var resisted = 0
        var today = 0
        var doneToday = 0
    }

    private func isStrict(_ s: Schedule) -> Bool {
        if case .timesPerWeek = s { return false }
        return true
    }

    /// Второй, независимый подсчёт опыта: дни перебираются по одному, без формул.
    private func recount(_ all: [HabitSnapshot], now: Date) -> Recount {
        var r = Recount()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.addingDays(-1, to: today)

        struct Build {
            let start: Date
            let schedule: Schedule
            let doneDays: Set<Date>
        }
        var builds: [Build] = []
        for h in all where h.kind == .build {
            var sums: [Date: Double] = [:]
            for c in h.checkIns where c.value.isFinite { sums[calendar.startOfDay(for: c.date), default: 0] += c.value }
            var done = Set<Date>()
            for (day, value) in sums where day <= today && engine.isDone(value, goal: h.goal) { done.insert(day) }
            r.habits += done.count * XPRules.habitDone
            if done.contains(today) {
                r.today += XPRules.habitDone
                r.doneToday += 1
            }
            builds.append(Build(start: calendar.startOfDay(for: engine.effectiveStart(h)), schedule: h.schedule, doneDays: done))
        }

        if let first = builds.map(\.start).min() {
            var day = first
            while day <= today {
                let due = builds.filter { isStrict($0.schedule) && $0.start <= day && engine.isScheduled(day, $0.schedule) }
                if !due.isEmpty && due.allSatisfy({ $0.doneDays.contains(day) }) {
                    r.perfect += XPRules.perfectDay
                    if day == today { r.today += XPRules.perfectDay }
                }
                day = calendar.addingDays(1, to: day)
            }
        }

        for q in all where q.kind == .quit {
            let startDay = calendar.startOfDay(for: engine.effectiveStart(q))
            let relapseDays = Set(q.relapses.map { calendar.startOfDay(for: $0.date) })
            var day = calendar.addingDays(1, to: startDay)
            while day < today {
                if !relapseDays.contains(day) {
                    r.clean += XPRules.cleanDay
                    if day == yesterday { r.today += XPRules.cleanDay }
                }
                day = calendar.addingDays(1, to: day)
            }
            var perDay: [Date: Int] = [:]
            for t in q.resisted where t <= now { perDay[calendar.startOfDay(for: t), default: 0] += 1 }
            for (day, n) in perDay {
                let gained = min(n, XPRules.resistedPerDay) * XPRules.resisted
                r.resisted += gained
                if day == today { r.today += gained }
            }
        }
        return r
    }

    private func checkXP(_ habits: [HabitSnapshot], now: Date, add: Adder) {
        let r = recount(habits, now: now)
        let x = companion.xp(habits, now: now)

        func compare(_ code: String, _ what: String, _ engineValue: Int, _ mine: Int) {
            if engineValue != mine {
                add(code, .error, nil, "Опыт «\(what)»: напарник начислил \(engineValue), а по истории выходит \(mine).", "CompanionEngine.xp: блок «\(what)».")
            }
        }
        compare("X01", "за привычки", x.habits, r.habits)
        compare("X02", "за идеальные дни", x.perfectDays, r.perfect)
        compare("X03", "за дни без срыва", x.cleanDays, r.clean)
        compare("X04", "за «Устоял»", x.resisted, r.resisted)
        compare("X05", "сегодня", x.today, r.today)

        if r.doneToday > 0 && x.today < r.doneToday * XPRules.habitDone {
            add("X06", .error, nil, "Сегодня выполнено привычек: \(r.doneToday), а опыта за сегодня только \(x.today).", "Привычка выполнена, но опыт не начислен: CompanionEngine.xp, ветка b.today.")
        }

        let p = LevelProgress(xp: x.total)
        if p.level != XPRules.level(for: x.total) || p.xpInLevel + XPRules.totalXP(forLevel: p.level) != x.total
            || p.fraction < 0 || p.fraction > 1 {
            add("L01", .error, nil, "Уровень и опыт внутри уровня не сходятся с общим опытом \(x.total).", "LevelProgress.init(xp:).")
        }
    }

    // MARK: - Что на экране

    private func checkDisplayed(_ all: [HabitSnapshot], _ d: QADisplayed, now: Date, add: Adder) {
        // Опыт считается по всем привычкам (архивные тоже), а настроение и «X из Y» — только по активным.
        let habits = all.filter { !$0.isArchived }
        let total = companion.xp(all, now: now).total
        if let shown = d.xpTotal, shown != total {
            add("V01", .error, nil, "На экране \(shown) XP, а по истории \(total).", "CompanionManager.status: xp считается из актуальных привычек.")
        }
        let level = XPRules.level(for: total)
        if let shown = d.level, shown != level {
            add("V02", .error, nil, "На экране уровень \(shown), а по опыту должен быть \(level).", "CompanionStatus.level.")
        }
        if let shown = d.stage, shown != XPRules.stage(for: level) {
            add("V03", .error, nil, "Стадия питомца «\(shown.title)» не соответствует уровню \(level).", "XPRules.stage(for:).")
        }

        let recentRelapse = habits.contains { h in
            h.kind == .quit && h.relapses.contains { $0.date <= now && now.timeIntervalSince($0.date) < 86_400 }
        }
        if let mood = d.mood {
            if recentRelapse && mood != .caring {
                add("V04", .error, nil, "Был срыв меньше суток назад, а настроение питомца «\(mood.title)» — должно быть «\(CompanionMood.caring.title)».", "CompanionEngine.mood: срыв важнее успехов.")
            }
            if !recentRelapse && mood == .caring {
                add("V05", .warning, nil, "Питомец «рядом с тобой», хотя срывов за последние сутки нет.", "CompanionEngine.mood / adjustedMood.")
            }
        }

        let s = companion.summary(habits, on: now)
        if let shown = d.todayScheduled, shown != s.scheduled {
            add("V06", .error, nil, "На «Сегодня» целей дня \(shown), а по расписанию \(s.scheduled).", "SummaryHeader / TodayView должны брать числа из CompanionEngine.summary.")
        }
        if let shown = d.todayDone, shown != s.scheduledDone {
            add("V06", .error, nil, "На «Сегодня» выполнено \(shown), а по отметкам \(s.scheduledDone).", "SummaryHeader / TodayView должны брать числа из CompanionEngine.summary.")
        }
    }
}
