import Foundation

// Данные для виджетов. Приложение собирает снимок из привычек и кладёт его в общий контейнер,
// расширение только читает снимок и показывает блоки через WidgetContent. Числа берутся из тех же
// движков, что и экран «Сегодня», поэтому кольцо виджета не расходится с кольцом в приложении.

/// Состояние одного дня недели в блоке «Неделя».
enum WidgetDot: Int, Codable, Sendable {
    case none = 0      // в этот день нет целей
    case future        // ещё не наступил
    case missed        // прошёл без выполнения
    case partial       // выполнено частично
    case done          // все цели выполнены
    case today         // сегодня, пока ничего не выполнено
}

struct WidgetStat: Codable, Equatable, Sendable {
    var name: String
    var days: Int
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date
    /// Начало суток, для которых посчитаны цели дня.
    var dayStart: Date
    var scheduled: Int
    var scheduledDone: Int
    var level: Int
    var levelFraction: Double
    var xpToday: Int
    var stageTitle: String
    /// Rawvalue CompanionMood.
    var mood: String
    var userName: String
    var petName: String
    var phrase: String
    var nextHabit: String?
    /// Отказы по убыванию серии, не больше трёх.
    var quits: [WidgetStat]
    var topBuild: WidgetStat?
    /// Семь дней текущей недели с понедельника.
    var week: [WidgetDot]
    /// Есть ли в общем контейнере картинка питомца.
    var hasPetImage: Bool

    /// Снимок посчитан для сегодняшних суток.
    func isFresh(now: Date, calendar: Calendar = .habitFlow) -> Bool {
        calendar.startOfDay(for: now) == calendar.startOfDay(for: dayStart)
    }

    /// Пример для галереи виджетов, предпросмотра в конструкторе и случая «данных ещё нет».
    static func sample(now: Date = .now, calendar: Calendar = .habitFlow) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now, dayStart: calendar.startOfDay(for: now),
            scheduled: 5, scheduledDone: 3, level: 7, levelFraction: 0.62, xpToday: 45,
            stageTitle: "Подросток", mood: CompanionMood.happy.rawValue,
            userName: "Андрей", petName: "Бульк",
            phrase: "Ого, сегодня уже 3 из 5 целей! Я сияю!",
            nextHabit: "Прочитать 20 страниц",
            quits: [WidgetStat(name: "Курение", days: 12), WidgetStat(name: "Сладкое", days: 5)],
            topBuild: WidgetStat(name: "Вода", days: 9),
            week: [.done, .done, .partial, .missed, .today, .future, .future],
            hasPetImage: false)
    }
}

// MARK: - Сборка снимка

struct WidgetSnapshotBuilder: Sendable {
    var calendar: Calendar = .habitFlow

    /// `habits` — все привычки, включая архивные (их история даёт опыт).
    /// Показываются только неархивные.
    func make(habits: [HabitSnapshot], userName: String, petName: String, phrase: String,
              mood: CompanionMood, now: Date = .now) -> WidgetSnapshot {
        let companion = CompanionEngine(calendar: calendar)
        let engine = companion.engine
        let active = habits.filter { !$0.isArchived }
        let today = calendar.startOfDay(for: now)

        let summary = companion.summary(active, on: now)
        let xp = companion.xp(habits, now: now)
        let progress = LevelProgress(xp: xp.total)

        let quits = active.filter { $0.kind == .quit }
            .map { WidgetStat(name: $0.name, days: engine.quitStreak($0, now: now).currentDays) }
            .sorted { $0.days > $1.days }
        let builds = active.filter { $0.kind == .build }
            .map { WidgetStat(name: $0.name, days: engine.buildStreak($0, now: now).current) }
            .filter { $0.days > 0 }
            .max { $0.days < $1.days }

        let weekStart = calendar.startOfWeek(now)
        var week: [WidgetDot] = []
        for i in 0..<7 {
            let day = calendar.addingDays(i, to: weekStart)
            week.append(dot(day: day, today: today, active: active, companion: companion))
        }

        return WidgetSnapshot(
            generatedAt: now, dayStart: today,
            scheduled: summary.scheduled, scheduledDone: summary.scheduledDone,
            level: progress.level, levelFraction: progress.fraction, xpToday: xp.today,
            stageTitle: XPRules.stage(for: progress.level).title, mood: mood.rawValue,
            userName: userName, petName: petName, phrase: phrase,
            nextHabit: companion.questHabit(active, now: now)?.name,
            quits: Array(quits.prefix(3)), topBuild: builds, week: week, hasPetImage: false)
    }

    private func dot(day: Date, today: Date, active: [HabitSnapshot], companion: CompanionEngine) -> WidgetDot {
        let s = companion.summary(active, on: day)
        if s.scheduled == 0 { return .none }
        if day > today { return .future }
        if s.scheduledDone == s.scheduled { return .done }
        if s.scheduledDone > 0 { return .partial }
        return day == today ? .today : .missed
    }
}

// MARK: - Что показывает блок

/// Готовое к показу содержимое блока. Рендерер только рисует его — выбирать числа и тексты ему не нужно.
enum WidgetValue: Equatable, Sendable {
    case text(String)
    case stat(value: String, caption: String)
    case ring(fraction: Double, center: String, caption: String)
    case bar(fraction: Double, label: String)
    case dots([WidgetDot])
    case lines([String])
    case pet(stage: String, mood: String, name: String)
}

enum WidgetContent {
    static func value(for block: WidgetBlock, snapshot s: WidgetSnapshot, now: Date = .now,
                      calendar: Calendar = .habitFlow) -> WidgetValue {
        let fresh = s.isFresh(now: now, calendar: calendar)
        let extra = fresh ? 0 : max(0, calendar.daysBetween(s.generatedAt, now))

        switch block.kind {
        case .dayRing:
            guard fresh else { return .ring(fraction: 0, center: "—", caption: "Откройте приложение") }
            if s.scheduled == 0 { return .ring(fraction: 0, center: "—", caption: "Нет целей") }
            let f = Double(s.scheduledDone) / Double(s.scheduled)
            return .ring(fraction: f, center: "\(s.scheduledDone)/\(s.scheduled)", caption: "целей")

        case .doneText:
            guard fresh else { return .text("—") }
            if s.scheduled == 0 { return .text("Нет целей") }
            return .text("\(s.scheduledDone) из \(s.scheduled)")

        case .percentText:
            guard fresh, s.scheduled > 0 else { return .text("—") }
            return .text("\(Int((Double(s.scheduledDone) / Double(s.scheduled) * 100).rounded()))%")

        case .bestQuit:
            guard let q = s.quits.first else { return .stat(value: "—", caption: "Нет отказов") }
            return .stat(value: "\(q.days + extra) дн.", caption: "без срыва: \(q.name)")

        case .quitList:
            if s.quits.isEmpty { return .lines(["Нет отказов"]) }
            return .lines(s.quits.map { "\($0.name) · \($0.days + extra) дн." })

        case .buildStreak:
            guard let b = s.topBuild else { return .stat(value: "—", caption: "Нет серий") }
            return .stat(value: "\(b.days) дн.", caption: "серия: \(b.name)")

        case .level:
            return .bar(fraction: s.levelFraction, label: "Ур. \(s.level) · \(s.stageTitle)")

        case .phrase:
            return .text(s.phrase.isEmpty ? "Я рядом" : s.phrase)

        case .nextHabit:
            guard fresh else { return .stat(value: "—", caption: "Откройте приложение") }
            if let n = s.nextHabit { return .stat(value: n, caption: "Дальше") }
            if s.scheduled > 0 && s.scheduledDone == s.scheduled { return .stat(value: "Всё сделано", caption: "Сегодня") }
            return .stat(value: "Свободный день", caption: "Сегодня")

        case .weekDots:
            return .dots(s.week.count == 7 ? s.week : Array(repeating: .none, count: 7))

        case .date:
            return .text(russianDate(now, calendar: calendar))

        case .greeting:
            let hour = calendar.component(.hour, from: now)
            let base: String
            switch hour {
            case 5..<12: base = "Доброе утро"
            case 12..<18: base = "Добрый день"
            case 18..<23: base = "Добрый вечер"
            default: base = "Доброй ночи"
            }
            let name = s.userName.trimmingCharacters(in: .whitespaces)
            return .text(name.isEmpty ? base : "\(base), \(name)")

        case .petImage:
            return .pet(stage: s.stageTitle, mood: s.mood, name: s.petName)

        case .customText:
            return .text(block.text.isEmpty ? "Мой текст" : block.text)
        }
    }

    /// «пн, 26 октября». Названия заданы явно, чтобы результат не зависел от платформы и локали.
    static func russianDate(_ date: Date, calendar: Calendar) -> String {
        let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                      "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        let w = weekdays[((c.weekday ?? 1) - 1 + 7) % 7]
        let m = months[((c.month ?? 1) - 1 + 12) % 12]
        return "\(w), \(c.day ?? 1) \(m)"
    }

    /// Краткая строка для мест, где форме нет места (строка на экране блокировки, круг без кольца).
    static func plainText(_ v: WidgetValue) -> String {
        switch v {
        case .text(let t): t
        case .stat(let value, _): value
        case .ring(_, let center, _): center
        case .bar(_, let label): label
        case .dots(let d): d.map { $0 == .done ? "●" : "○" }.joined()
        case .lines(let l): l.first ?? ""
        case .pet(_, _, let name): name
        }
    }
}
