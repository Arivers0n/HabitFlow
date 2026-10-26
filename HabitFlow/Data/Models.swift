import Foundation
import SwiftData

// Хранилище SwiftData. Все поля с значениями по умолчанию, чтобы схема
// могла расширяться без ручных миграций.

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = HabitKind.build.rawValue
    var symbol: String = "star.fill"
    var colorHex: String = "4C8DFF"
    var note: String = ""
    var createdAt: Date = Date()
    /// Для полезной — с какого дня отслеживаем, для отказа — с какого момента не употребляю.
    var startDate: Date = Date()
    var sortOrder: Int = 0
    var isArchived: Bool = false

    // Расписание
    var scheduleType: String = "daily"     // daily | perWeek | weekdays
    var timesPerWeek: Int = 3
    var weekdaysMask: Int = 0b111_1111     // бит (weekday − 1)

    // Цель на день
    var goalTarget: Double = 1
    var goalUnit: String = ""
    var goalStep: Double = 1

    // Отказ: единица, обычная норма в день и цена — для «не выкурено / сэкономлено»
    var unitName: String = ""
    var baselinePerDay: Double = 0
    var costPerUnit: Double = 0

    // Напоминание
    var reminderOn: Bool = false
    var reminderMinutes: Int = 20 * 60

    /// До какого числа дней уже показали поздравление — чтобы не повторять.
    var celebratedDays: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.habit)
    var checkIns: [CheckIn] = []

    @Relationship(deleteRule: .cascade, inverse: \Relapse.habit)
    var relapses: [Relapse] = []

    init(name: String = "", kind: HabitKind = .build) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.createdAt = .now
        self.startDate = .now
    }
}

@Model
final class CheckIn {
    var id: UUID = UUID()
    var date: Date = Date()
    var value: Double = 1
    var habit: Habit?

    init(date: Date, value: Double) {
        self.id = UUID()
        self.date = date
        self.value = value
    }
}

@Model
final class Relapse {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Double = 1
    var trigger: String = ""
    var note: String = ""
    var habit: Habit?

    init(date: Date, amount: Double, trigger: String, note: String) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.trigger = trigger
        self.note = note
    }
}

// MARK: - Мост к доменным типам

extension Habit {
    var kind: HabitKind {
        get { HabitKind(rawValue: kindRaw) ?? .build }
        set { kindRaw = newValue.rawValue }
    }

    var schedule: Schedule {
        get {
            switch scheduleType {
            case "perWeek": return .timesPerWeek(max(1, min(7, timesPerWeek)))
            case "weekdays": return .weekdays(Habit.days(fromMask: weekdaysMask))
            default: return .daily
            }
        }
        set {
            switch newValue {
            case .daily: scheduleType = "daily"
            case .timesPerWeek(let n): scheduleType = "perWeek"; timesPerWeek = n
            case .weekdays(let set): scheduleType = "weekdays"; weekdaysMask = Habit.mask(fromDays: set)
            }
        }
    }

    var goal: Goal {
        get { Goal(target: max(goalTarget, 0.0001), unit: goalUnit, step: max(goalStep, 0.0001)) }
        set { goalTarget = newValue.target; goalUnit = newValue.unit; goalStep = newValue.step }
    }

    var snapshot: HabitSnapshot {
        HabitSnapshot(kind: kind, startDate: startDate, schedule: schedule, goal: goal,
                      checkIns: checkIns.map { CheckInValue(date: $0.date, value: $0.value) },
                      relapses: relapses.map { RelapseValue(date: $0.date, amount: $0.amount, trigger: $0.trigger) })
    }

    var sortedRelapses: [Relapse] { relapses.sorted { $0.date > $1.date } }

    static func days(fromMask mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    static func mask(fromDays days: Set<Int>) -> Int {
        days.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    /// Человеческое описание расписания и цели: «Каждый день · 2 000 мл».
    var scheduleText: String {
        let sched: String
        switch schedule {
        case .daily: sched = "Каждый день"
        case .timesPerWeek(let n): sched = "\(n) \(plural(n, "раз", "раза", "раз")) в неделю"
        case .weekdays(let set):
            let names = [2, 3, 4, 5, 6, 7, 1].filter(set.contains).map { WeekdayNames.short[$0] }
            sched = set.count == 7 ? "Каждый день" : names.joined(separator: ", ")
        }
        if goal.isBinary { return sched }
        return "\(sched) · \(NumberText.value(goal.target)) \(goal.unit)"
    }
}

enum WeekdayNames {
    /// Индекс — номер Calendar.weekday (1 — вс).
    static let short = ["", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    /// Порядок отображения с понедельника.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
}
