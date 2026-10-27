import Foundation

// Быстрые карточки: напарник присылает уведомление, а при открытии показывает стопку карточек
// («сделано?», «сколько воды?», «была тяга?», «как настроение?») с ответом одним касанием.
// Здесь только логика: какие карточки показать, в какое время напомнить и что ответит питомец.

/// Ответ на карточку. Слой Data превращает его в запись в базе.
enum QuickAnswer: Equatable, Sendable {
    case done
    case added(Double)
    case filled
    case resisted
    case relapse
    case noUrge
    case mood(Int)
    case skipped
}

struct QuickOption: Equatable, Sendable, Identifiable {
    enum Role: Equatable, Sendable { case primary, secondary, danger }

    var id: String
    var title: String
    var answer: QuickAnswer
    var role: Role = .secondary
}

struct QuickCard: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case done, volume, resist, mood }

    var id: String
    var kind: Kind
    /// Привычка, к которой относится карточка (UUID в виде строки); у карточки настроения её нет.
    var habitID: String?
    var title: String
    var subtitle: String
    var options: [QuickOption]

    /// Ответ на свайп вправо — главный вариант карточки.
    var swipeRightAnswer: QuickAnswer? {
        options.first { $0.role == .primary }?.answer
    }
}

struct QuickHabit: Sendable {
    var id: String
    var snapshot: HabitSnapshot
}

struct NotificationTimeSuggestion: Equatable, Sendable {
    var minutes: Int
    /// Сколько дней с настоящими отметками легло в расчёт.
    var samples: Int
    var personalized: Bool
}

struct QuickCardPlanner: Sendable {
    var calendar: Calendar
    private var engine: StreakEngine

    init(calendar: Calendar = .habitFlow) {
        self.calendar = calendar
        engine = StreakEngine(calendar: calendar)
    }

    static let moodEmoji = ["😞", "😕", "😐", "🙂", "😄"]
    static let defaultMinutes = 20 * 60

    // MARK: - Какие карточки показать

    /// Стопка на сейчас: сначала «тяга», потом объёмы, потом простые отметки, в конце — настроение.
    /// Выполненное и не запланированное на сегодня не спрашиваем.
    func deck(_ habits: [QuickHabit], now: Date = .now, moodAnswered: Bool = false, limit: Int = 5) -> [QuickCard] {
        let today = calendar.startOfDay(for: now)
        var resist: [QuickCard] = []
        var volume: [QuickCard] = []
        var simple: [QuickCard] = []

        for item in habits where !item.snapshot.isArchived {
            let h = item.snapshot
            let name = h.name.isEmpty ? "Привычка" : h.name
            switch h.kind {
            case .quit:
                let count = h.resisted.filter { calendar.isDate($0, inSameDayAs: now) }.count
                guard count < XPRules.resistedPerDay else { continue }
                let q = engine.quitStreak(h, now: now)
                let sub = q.current >= 60 ? "Без срыва: \(DurationText.human(q.current))" : "Только что начали — каждая минута важна"
                resist.append(QuickCard(
                    id: "resist-\(item.id)", kind: .resist, habitID: item.id,
                    title: "«\(name)»: была тяга?", subtitle: sub,
                    options: [
                        QuickOption(id: "resisted", title: "Устоял", answer: .resisted, role: .primary),
                        QuickOption(id: "relapse", title: "Был срыв", answer: .relapse, role: .danger),
                        QuickOption(id: "none", title: "Тяги не было", answer: .noUrge, role: .secondary),
                    ]))

            case .build:
                guard calendar.startOfDay(for: engine.effectiveStart(h)) <= today,
                      engine.isScheduled(today, h.schedule) else { continue }
                let s = engine.buildStreak(h, now: now)
                guard !s.todayDone else { continue }
                if case .timesPerWeek = h.schedule, s.weekDone >= s.weekTarget { continue }

                if h.goal.isBinary {
                    let sub = s.current > 0 ? "Серия: \(pluralDays(s.current))" : "Начнём серию сегодня"
                    simple.append(QuickCard(
                        id: "done-\(item.id)", kind: .done, habitID: item.id,
                        title: "«\(name)» — сделано?", subtitle: sub,
                        options: [QuickOption(id: "done", title: "Да, сделано", answer: .done, role: .primary)]))
                } else {
                    let remaining = max(0, h.goal.target - s.todayValue)
                    guard remaining > 0 else { continue }
                    let unit = h.goal.unit
                    let step = min(h.goal.step, remaining)
                    var options = [QuickOption(id: "step", title: "+\(NumberText.value(step)) \(unit)",
                                               answer: .added(step), role: .primary)]
                    let double = h.goal.step * 2
                    if double < remaining {
                        options.append(QuickOption(id: "double", title: "+\(NumberText.value(double)) \(unit)",
                                                   answer: .added(double), role: .secondary))
                    }
                    options.append(QuickOption(id: "fill", title: "Закрыть норму", answer: .filled, role: .secondary))
                    volume.append(QuickCard(
                        id: "volume-\(item.id)", kind: .volume, habitID: item.id,
                        title: "«\(name)»: сколько уже?",
                        subtitle: "Сейчас \(NumberText.value(s.todayValue)) из \(NumberText.value(h.goal.target)) \(unit)",
                        options: options))
                }
            }
        }

        let bodyLimit = max(0, moodAnswered ? limit : limit - 1)
        var picked: [QuickCard] = Array(resist.prefix(2)) + Array(volume.prefix(2)) + Array(simple.prefix(2))
        let rest = Array(resist.dropFirst(2)) + Array(volume.dropFirst(2)) + Array(simple.dropFirst(2))
        let room = max(0, bodyLimit - picked.count)
        picked += rest.prefix(room)
        picked = Array(picked.prefix(bodyLimit))

        if !moodAnswered && limit > 0 {
            let options = Self.moodEmoji.enumerated().map {
                QuickOption(id: "mood-\($0.offset + 1)", title: $0.element, answer: .mood($0.offset + 1), role: .secondary)
            }
            picked.append(QuickCard(id: "mood", kind: .mood, habitID: nil,
                                    title: "Как настроение?", subtitle: "Одно касание — я запомню", options: options))
        }
        return picked
    }

    // MARK: - Когда напомнить

    /// Время вечернего уведомления по режиму дня: когда человек обычно заканчивает отмечать — минус полчаса,
    /// чтобы напоминание пришло до последних дел. Нужно минимум 5 дней с настоящими отметками.
    /// Отметки задним числом хранятся со временем ровно 12:00 — их не считаем, иначе все «приходились» бы на полдень.
    func suggestedMinutes(_ habits: [HabitSnapshot], bedtimeMinutes: Int? = nil, now: Date = .now) -> NotificationTimeSuggestion {
        let from = now.addingTimeInterval(-30 * 86_400)
        var lastPerDay: [Date: Int] = [:]

        func note(_ date: Date) {
            guard date >= from, date <= now, !isSynthetic(date) else { return }
            let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            let day = calendar.startOfDay(for: date)
            lastPerDay[day] = max(lastPerDay[day] ?? 0, minutes)
        }
        for h in habits {
            for c in h.checkIns { note(c.date) }
            for r in h.relapses { note(r.date) }
            for r in h.resisted { note(r) }
        }

        let lower = 17 * 60 + 30
        var upper = 21 * 60 + 30
        if let b = bedtimeMinutes {
            let bed = b < 12 * 60 ? b + 24 * 60 : b
            upper = min(upper, bed - 90)
        }
        upper = max(lower, upper)

        let samples = lastPerDay.count
        guard samples >= 5 else {
            return NotificationTimeSuggestion(minutes: min(max(Self.defaultMinutes, lower), upper),
                                              samples: samples, personalized: false)
        }
        let sorted = lastPerDay.values.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let raw = min(max(median - 30, lower), upper)
        let rounded = (raw + 2) / 5 * 5
        return NotificationTimeSuggestion(minutes: min(max(rounded, lower), upper), samples: samples, personalized: true)
    }

    private func isSynthetic(_ date: Date) -> Bool {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return c.hour == 12 && c.minute == 0 && c.second == 0
    }
}

// MARK: - Мгновенные реакции питомца

enum QuickReactions {

    static func line(for answer: QuickAnswer, userName: String, strict: Bool, seed: Int) -> String {
        let pool: [String]
        switch answer {
        case .done:
            pool = strict ? ["Принято%N.", "Отмечено. Следующая цель.", "Хорошо%N."]
                          : ["Ура%N! Ещё одна галочка!", "Так держать%N!", "Класс! Я чувствую, как расту."]
        case .added:
            pool = strict ? ["Записано%N.", "Добавлено. Идём дальше."]
                          : ["Плюс! Отлично идём%N.", "Каждый шаг считается!", "Вот это темп%N!"]
        case .filled:
            pool = strict ? ["Норма закрыта%N.", "Цель выполнена."]
                          : ["Норма закрыта%N! Я горжусь нами.", "Цель дня закрыта — искры летят!"]
        case .resisted:
            return CompanionPhrases.resistedLine(name: userName, strict: strict, seed: seed)
        case .relapse:
            return CompanionPhrases.caringLine(name: userName, strict: strict, seed: seed)
        case .noUrge:
            pool = strict ? ["Принято%N. Без тяги."]
                          : ["Отлично%N! Спокойный день — тоже победа.", "Тяги нет — значит, всё хорошо."]
        case .mood(let level):
            switch level {
            case ...2:
                pool = strict ? ["Принято%N. Сегодня снижаем планку до минимума."]
                              : ["Спасибо за честность%N. Давай сегодня без героизма: одна маленькая цель — и хватит.",
                                 "Бывают тяжёлые дни%N. Я рядом."]
            case 3:
                pool = strict ? ["Принято%N. Ровный день."]
                              : ["Ровный день — тоже хорошо%N.", "Спокойно и по делу%N. Так и держим."]
            default:
                pool = strict ? ["Принято%N. Используем этот настрой."]
                              : ["Как здорово%N! Подарим этот настрой привычкам.", "Вот это настроение%N! Я заряжаюсь."]
            }
        case .skipped:
            pool = strict ? ["Отложено%N."]
                          : ["Хорошо%N, вернёмся позже.", "Ничего страшного — карточки подождут."]
        }
        return CompanionPhrases.fill(CompanionPhrases.choose(pool, seed), name: userName)
    }

    /// Итог после последней карточки.
    static func finished(userName: String, strict: Bool, gainedXP: Int, seed: Int) -> String {
        let base = strict ? ["Готово%N.", "Карточки закрыты%N."]
                          : ["Готово%N! Это заняло меньше минуты.", "Всё! Спасибо, что заглянули%N."]
        var s = CompanionPhrases.fill(CompanionPhrases.choose(base, seed), name: userName)
        if gainedXP > 0 { s += " +\(gainedXP) XP." }
        return s
    }

    /// Текст уведомления. Одинаковый на каждый день — уведомление повторяется по расписанию.
    static func notificationBody(strict: Bool, hour: Int) -> String {
        if strict { return "Время отметить день: несколько карточек." }
        if hour < 12 { return "Утро! Пара быстрых вопросов — загляни?" }
        if hour < 18 { return "Пара вопросов на 20 секунд — загляни?" }
        return "Давай отметим, что успели за день."
    }
}
