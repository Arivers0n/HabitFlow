import Foundation

// Доменные типы — чистый Swift без SwiftUI и SwiftData.
// Движки (StreakEngine, RewardEngine, StatsEngine) работают только с ними,
// поэтому логику можно тестировать отдельно от интерфейса и базы.

enum HabitKind: String, Codable, CaseIterable, Sendable {
    /// Формирую полезное: спорт, вода, чтение.
    case build
    /// Отказываюсь от вредного: курение, алкоголь, сладкое.
    case quit
}

enum Schedule: Hashable, Codable, Sendable {
    case daily
    /// N раз в неделю, в любые дни.
    case timesPerWeek(Int)
    /// Конкретные дни недели. Номера как у Calendar: 1 — вс, 2 — пн … 7 — сб.
    case weekdays(Set<Int>)
}

struct Goal: Hashable, Codable, Sendable {
    /// Сколько нужно за день. Для простой отметки — 1.
    var target: Double
    /// Единица измерения («мл», «мин», «стр»). Пусто — простая отметка.
    var unit: String
    /// Шаг быстрой кнопки «+».
    var step: Double

    static let check = Goal(target: 1, unit: "", step: 1)
    var isBinary: Bool { unit.isEmpty }
}

struct CheckInValue: Hashable, Sendable {
    var date: Date
    var value: Double
}

struct RelapseValue: Hashable, Sendable {
    var date: Date
    var amount: Double
    var trigger: String
}

/// Снимок привычки для расчётов. Собирается из модели SwiftData в слое Data.
struct HabitSnapshot: Sendable {
    var kind: HabitKind
    var startDate: Date
    var schedule: Schedule
    var goal: Goal
    var checkIns: [CheckInValue]
    var relapses: [RelapseValue]
    /// Моменты, когда устоял перед искушением (только для отказа).
    var resisted: [Date]
    var name: String

    init(kind: HabitKind, startDate: Date, schedule: Schedule = .daily, goal: Goal = .check,
         checkIns: [CheckInValue] = [], relapses: [RelapseValue] = [], resisted: [Date] = [], name: String = "") {
        self.kind = kind
        self.startDate = startDate
        self.schedule = schedule
        self.goal = goal
        self.checkIns = checkIns
        self.relapses = relapses
        self.resisted = resisted
        self.name = name
    }
}

/// Состояние одного дня в календаре привычки.
enum DayStatus: Equatable, Sendable {
    case done          // цель дня выполнена
    case partial       // начато, но не дотянуто до цели
    case missed        // запланированный день пропущен
    case rest          // день не по расписанию
    case pending       // сегодня, ещё можно успеть
    case future
    case beforeStart
    case clean         // день без срыва
    case relapse       // был срыв
}

extension Calendar {
    /// Русская неделя с понедельника.
    static var habitFlow: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        return c
    }

    func addingDays(_ n: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: n, to: date)!
    }

    func startOfWeek(_ date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)!.start
    }

    func daysBetween(_ a: Date, _ b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
