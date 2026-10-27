import Foundation

// Разбор недели: что получилось, где просадка, какие микро-шаги на следующую неделю.
// Считается по истории без ИИ — поэтому работает и офлайн; ИИ лишь «озвучивает» эти же факты.

struct HabitWeek: Equatable, Sendable, Identifiable {
    var name: String
    var kind: HabitKind
    /// Для полезной: выполненные дни и запланированные дни за 7 дней.
    var done: Int
    var planned: Int
    /// Для полезной: доля прошлых 7 дней (nil, если привычки тогда ещё не было).
    var previousRate: Double?
    /// Для отказа: срывы, «устоял», чистые дни.
    var relapses: Int
    var resisted: Int
    var cleanDays: Int
    var topTrigger: String?

    var id: String { "\(kind.rawValue)|\(name)" }
    var rate: Double { planned > 0 ? min(1, Double(done) / Double(planned)) : 0 }
}

struct WeeklyReview: Equatable, Sendable {
    var from: Date
    var to: Date
    var habits: [HabitWeek]
    var strengths: [String]
    var dips: [String]
    var microSteps: [String]
    var overallRate: Double?
    var previousOverallRate: Double?
    var sleepAverageSeconds: TimeInterval?

    var isEmpty: Bool { habits.isEmpty }

    /// Короткий текст на экран и на случай, если ИИ недоступен.
    func text(strict: Bool = false) -> String {
        guard !habits.isEmpty else {
            return "Пока нечего разбирать: добавь привычку и отмечай её несколько дней."
        }
        var parts: [String] = []
        if let r = overallRate {
            var head = "Неделя: выполнено \(Int((r * 100).rounded()))% целей"
            if let p = previousOverallRate {
                let delta = Int(((r - p) * 100).rounded())
                if delta >= 5 { head += ", это на \(delta)% лучше прошлой" }
                else if delta <= -5 { head += ", это на \(-delta)% ниже прошлой" }
                else { head += ", примерно как на прошлой неделе" }
            }
            parts.append(head + ".")
        }
        if !strengths.isEmpty { parts.append((strict ? "Сильное: " : "Получилось: ") + strengths.joined(separator: " ")) }
        if !dips.isEmpty { parts.append((strict ? "Просадки: " : "Просело: ") + dips.joined(separator: " ")) }
        if !microSteps.isEmpty {
            parts.append((strict ? "План: " : "Микро-шаги на неделю: ") + microSteps.map { "• " + $0 }.joined(separator: " "))
        }
        return parts.joined(separator: "\n\n")
    }

    /// Сводка для ИИ (факты, без выводов).
    var promptFacts: String {
        var lines: [String] = []
        if let r = overallRate { lines.append("Общее выполнение за 7 дней: \(Int((r * 100).rounded()))%.") }
        if let p = previousOverallRate { lines.append("Неделей раньше: \(Int((p * 100).rounded()))%.") }
        if let s = sleepAverageSeconds { lines.append("Средний сон: \(HealthAdvice.hm(s)).") }
        lines += strengths.map { "Сильная сторона: \($0)" }
        lines += dips.map { "Просадка: \($0)" }
        lines += microSteps.map { "Идея микро-шага: \($0)" }
        return lines.joined(separator: "\n")
    }
}

struct WeeklyReviewBuilder: Sendable {
    var calendar: Calendar
    private var engine: StreakEngine

    init(calendar: Calendar = .habitFlow) {
        self.calendar = calendar
        engine = StreakEngine(calendar: calendar)
    }

    func build(_ habits: [HabitSnapshot], sleepAverage: TimeInterval? = nil, now: Date = .now) -> WeeklyReview {
        let today = calendar.startOfDay(for: now)
        let from = calendar.addingDays(-6, to: today)
        let prevFrom = calendar.addingDays(-13, to: today)
        let prevTo = calendar.addingDays(-7, to: today)

        var weeks: [HabitWeek] = []
        var sumDone = 0, sumPlanned = 0, prevDone = 0, prevPlanned = 0

        for h in habits where !h.isArchived {
            let start = calendar.startOfDay(for: engine.effectiveStart(h))
            guard start <= today else { continue }
            let name = h.name.isEmpty ? "Без названия" : h.name

            switch h.kind {
            case .build:
                let totals = engine.dailyTotals(h)
                let cur = count(h, totals: totals, from: from, to: today, start: start, today: today)
                let prev = count(h, totals: totals, from: prevFrom, to: prevTo, start: start, today: today)
                guard cur.planned > 0 || cur.done > 0 else { continue }
                sumDone += cur.done; sumPlanned += cur.planned
                prevDone += prev.done; prevPlanned += prev.planned
                weeks.append(HabitWeek(name: name, kind: .build, done: cur.done, planned: max(cur.planned, cur.done),
                                       previousRate: prev.planned > 0 ? min(1, Double(prev.done) / Double(prev.planned)) : nil,
                                       relapses: 0, resisted: 0, cleanDays: 0, topTrigger: nil))
            case .quit:
                let rel = h.relapses.filter { inRange($0.date, from, today) }
                let res = h.resisted.filter { inRange($0, from, today) }.count
                let relDays = Set(rel.map { calendar.startOfDay(for: $0.date) })
                let first = max(from, start)
                let span = calendar.daysBetween(first, today) + 1
                let clean = max(0, span - relDays.count)
                var map: [String: Int] = [:]
                for r in rel where !r.trigger.isEmpty { map[r.trigger, default: 0] += 1 }
                let top = map.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
                weeks.append(HabitWeek(name: name, kind: .quit, done: clean, planned: span, previousRate: nil,
                                       relapses: rel.count, resisted: res, cleanDays: clean, topTrigger: top))
                sumDone += clean; sumPlanned += span
            }
        }

        var strengths: [String] = []
        var dips: [String] = []
        var steps: [String] = []

        let builds = weeks.filter { $0.kind == .build }
        let quits = weeks.filter { $0.kind == .quit }

        for w in builds.sorted(by: { $0.rate > $1.rate }) where w.planned >= 3 && w.rate >= 0.85 {
            strengths.append("«\(w.name)» — \(w.done) из \(w.planned).")
            if strengths.count == 2 { break }
        }
        for q in quits where q.relapses == 0 {
            strengths.append("«\(q.name)» — неделя без срывов\(q.resisted > 0 ? ", устояли \(q.resisted) \(plural(q.resisted, "раз", "раза", "раз"))" : "").")
        }
        for q in quits where q.relapses > 0 && q.resisted > 0 {
            strengths.append("«\(q.name)» — устояли \(q.resisted) \(plural(q.resisted, "раз", "раза", "раз")).")
        }

        let weak = builds.filter { $0.planned >= 3 && $0.rate < 0.5 }.sorted { $0.rate < $1.rate }
        for w in weak.prefix(2) {
            var s = "«\(w.name)» — \(w.done) из \(w.planned)."
            if let p = w.previousRate, p - w.rate >= 0.25 { s += " Раньше выходило лучше." }
            dips.append(s)
        }
        for q in quits where q.relapses > 0 {
            var s = "«\(q.name)» — срывов: \(q.relapses)."
            if let t = q.topTrigger { s += " Чаще всего причина: «\(t)»." }
            dips.append(s)
        }

        if let w = weak.first {
            steps.append("«\(w.name)»: на неделю выбрать самый лёгкий вариант — две минуты вместо полной нормы, зато каждый день.")
        }
        if let q = quits.first(where: { $0.relapses > 0 }) {
            if let t = q.topTrigger {
                steps.append("«\(q.name)»: на случай «\(t)» заранее придумать замену — стакан воды или десять минут прогулки.")
            } else {
                steps.append("«\(q.name)»: записывать причину каждого срыва, чтобы через неделю увидеть закономерность.")
            }
        }
        if let s = sleepAverage, s < HealthAdvice.deficitBelow, s >= HealthAdvice.incompleteBelow {
            steps.append("Сон в среднем \(HealthAdvice.hm(s)): сдвинуть отбой на 15 минут раньше.")
        }
        if steps.isEmpty, let best = builds.max(by: { $0.rate < $1.rate }), best.rate >= 0.85 {
            steps.append("Держать темп: добавить к «\(best.name)» совсем маленькую прибавку или закрепить время дня.")
        }
        if steps.isEmpty && !weeks.isEmpty {
            steps.append("Выбрать одну привычку и привязать её к тому, что уже делаете каждый день.")
        }

        return WeeklyReview(
            from: from, to: today, habits: weeks,
            strengths: strengths, dips: dips, microSteps: Array(steps.prefix(3)),
            overallRate: sumPlanned > 0 ? min(1, Double(sumDone) / Double(sumPlanned)) : nil,
            previousOverallRate: prevPlanned > 0 ? min(1, Double(prevDone) / Double(prevPlanned)) : nil,
            sleepAverageSeconds: sleepAverage)
    }

    // MARK: - Подсчёт

    private func inRange(_ d: Date, _ from: Date, _ to: Date) -> Bool {
        let s = calendar.startOfDay(for: d)
        return s >= from && s <= to
    }

    /// Выполненные и запланированные дни в окне. Сегодняшний невыполненный день не считаем пропуском.
    private func count(_ h: HabitSnapshot, totals: [Date: Double], from: Date, to: Date,
                       start: Date, today: Date) -> (done: Int, planned: Int) {
        let lower = max(from, start)
        guard lower <= to else { return (0, 0) }
        var done = 0, scheduled = 0
        var day = lower
        while day <= to {
            let ok = engine.isDone(totals[day] ?? 0, goal: h.goal)
            if ok { done += 1 }
            if engine.isScheduled(day, h.schedule), !(day == today && !ok) { scheduled += 1 }
            day = calendar.addingDays(1, to: day)
        }
        if case .timesPerWeek(let n) = h.schedule {
            let span = Double(calendar.daysBetween(lower, to) + 1)
            let expected = max(1, Int((Double(n) * span / 7).rounded()))
            return (min(done, expected), expected)
        }
        return (done, max(scheduled, done))
    }
}
