import Foundation

/// Черновик привычки для редактора. Отделён от модели, чтобы отмена
/// редактирования ничего не меняла в базе.
struct HabitDraft: Equatable {
    var name: String = ""
    var kind: HabitKind = .build
    var symbol: String = "star.fill"
    var colorHex: String = Palette.build[0]
    var note: String = ""
    var startDate: Date = .now

    var scheduleType: String = "daily"
    var timesPerWeek: Int = 3
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    var isVolume: Bool = false
    var goalTarget: Double = 1
    var goalUnit: String = ""
    var goalStep: Double = 1

    var unitName: String = ""
    var baselinePerDay: Double = 0
    var costPerUnit: Double = 0

    var reminderOn: Bool = false
    var reminderTime: Date = Calendar.habitFlow.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (!isVolume || (goalTarget > 0 && !goalUnit.trimmingCharacters(in: .whitespaces).isEmpty))
            && (scheduleType != "weekdays" || !weekdays.isEmpty)
    }

    init() {}

    init(habit h: Habit) {
        name = h.name
        kind = h.kind
        symbol = h.symbol
        colorHex = h.colorHex
        note = h.note
        startDate = h.startDate
        scheduleType = h.scheduleType
        timesPerWeek = h.timesPerWeek
        weekdays = Habit.days(fromMask: h.weekdaysMask)
        isVolume = !h.goalUnit.isEmpty
        goalTarget = h.goalTarget
        goalUnit = h.goalUnit
        goalStep = h.goalStep
        unitName = h.unitName
        baselinePerDay = h.baselinePerDay
        costPerUnit = h.costPerUnit
        reminderOn = h.reminderOn
        let cal = Calendar.habitFlow
        reminderTime = cal.date(bySettingHour: h.reminderMinutes / 60, minute: h.reminderMinutes % 60, second: 0, of: .now) ?? .now
    }

    func apply(to h: Habit) {
        h.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        h.kind = kind
        h.symbol = symbol
        h.colorHex = colorHex
        h.note = note
        h.startDate = startDate
        h.scheduleType = kind == .quit ? "daily" : scheduleType
        h.timesPerWeek = timesPerWeek
        h.weekdaysMask = Habit.mask(fromDays: weekdays.isEmpty ? [2] : weekdays)
        if kind == .build && isVolume {
            h.goalTarget = goalTarget
            h.goalUnit = goalUnit.trimmingCharacters(in: .whitespaces)
            h.goalStep = goalStep > 0 ? goalStep : max(1, goalTarget / 4)
        } else {
            h.goalTarget = 1
            h.goalUnit = ""
            h.goalStep = 1
        }
        h.unitName = unitName.trimmingCharacters(in: .whitespaces)
        h.baselinePerDay = max(0, baselinePerDay)
        h.costPerUnit = max(0, costPerUnit)
        h.reminderOn = reminderOn
        let comps = Calendar.habitFlow.dateComponents([.hour, .minute], from: reminderTime)
        h.reminderMinutes = (comps.hour ?? 20) * 60 + (comps.minute ?? 0)
    }
}

/// Готовые шаблоны, чтобы создать привычку в два касания.
struct HabitTemplate: Identifiable {
    let id: String
    let draft: HabitDraft

    static let build: [HabitTemplate] = [
        make("water", "Вода", .build, "drop.fill", "5AC8FA") { $0.isVolume = true; $0.goalTarget = 2000; $0.goalUnit = "мл"; $0.goalStep = 250 },
        make("sport", "Спорт", .build, "figure.run", "3DDC97") { $0.scheduleType = "perWeek"; $0.timesPerWeek = 3 },
        make("meditate", "Медитация", .build, "brain.head.profile", "9B6BFF") { $0.isVolume = true; $0.goalTarget = 10; $0.goalUnit = "мин"; $0.goalStep = 5 },
        make("read", "Чтение", .build, "book.fill", "6E6BFF") { $0.isVolume = true; $0.goalTarget = 20; $0.goalUnit = "стр"; $0.goalStep = 5 },
        make("steps", "Шаги", .build, "shoeprints.fill", "34C759") { $0.isVolume = true; $0.goalTarget = 8000; $0.goalUnit = "шагов"; $0.goalStep = 1000 },
        make("sleep", "Сон до 23:00", .build, "moon.stars.fill", "B9A4FF") { _ in },
        make("english", "Английский", .build, "character.book.closed.fill", "4C8DFF") { $0.scheduleType = "weekdays"; $0.weekdays = [2, 3, 4, 5, 6] },
        make("stretch", "Растяжка", .build, "figure.flexibility", "2ECFC4") { _ in },
    ]

    static let quit: [HabitTemplate] = [
        make("smoke", "Курение", .quit, "smoke.fill", "FF453A") { $0.unitName = "сигарет"; $0.baselinePerDay = 10 },
        make("alcohol", "Алкоголь", .quit, "wineglass.fill", "FF9F0A") { $0.unitName = "порций" },
        make("sugar", "Сладкое", .quit, "birthday.cake.fill", "FF6B4A") { $0.unitName = "порций" },
        make("social", "Соцсети", .quit, "iphone", "E5384F") { $0.unitName = "мин" },
        make("fastfood", "Фастфуд", .quit, "takeoutbag.and.cup.and.straw.fill", "FFB340") { $0.unitName = "раз" },
        make("vape", "Вейп", .quit, "cloud.fill", "D9542A") { $0.unitName = "затяжек" },
    ]

    private static func make(_ id: String, _ name: String, _ kind: HabitKind, _ symbol: String, _ hex: String,
                             _ edit: (inout HabitDraft) -> Void) -> HabitTemplate {
        var d = HabitDraft()
        d.name = name
        d.kind = kind
        d.symbol = symbol
        d.colorHex = hex
        edit(&d)
        return HabitTemplate(id: id, draft: d)
    }
}
