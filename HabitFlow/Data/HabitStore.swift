import Foundation
import SwiftData
import Observation

/// Все изменения данных проходят здесь. Экраны читают привычки через @Query,
/// а пишут только через стор — так логика сохранения и уведомлений в одном месте.
@MainActor
@Observable
final class HabitStore {
    let context: ModelContext
    let engine = StreakEngine()
    private var calendar: Calendar { engine.calendar }

    /// Поздравление, которое нужно показать (наблюдается корневым экраном).
    var celebration: Celebration?

    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let habitName: String
        let milestone: Milestone
        let kind: HabitKind
        let colorHex: String
    }

    init(context: ModelContext) {
        self.context = context
    }

    func save() {
        do { try context.save() } catch { print("Ошибка сохранения: \(error)") }
    }

    // MARK: - Привычки

    @discardableResult
    func create(_ draft: HabitDraft) -> Habit {
        let count = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        let h = Habit(name: draft.name, kind: draft.kind)
        draft.apply(to: h)
        h.sortOrder = count
        context.insert(h)
        save()
        NotificationService.sync(h)
        return h
    }

    func update(_ h: Habit, with draft: HabitDraft) {
        draft.apply(to: h)
        save()
        NotificationService.sync(h)
    }

    func delete(_ h: Habit) {
        NotificationService.cancel(h.id)
        context.delete(h)
        save()
    }

    func setArchived(_ h: Habit, _ archived: Bool) {
        h.isArchived = archived
        save()
        NotificationService.sync(h)
    }

    /// Новый порядок после перетаскивания в списке.
    func reorder(_ habits: [Habit], from source: IndexSet, to destination: Int) {
        var list = habits
        list.move(fromOffsets: source, toOffset: destination)
        for (i, h) in list.enumerated() { h.sortOrder = i }
        save()
    }

    // MARK: - Отметки полезных привычек

    func value(of h: Habit, on day: Date = .now) -> Double {
        h.checkIns.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.value }
    }

    /// Добавить значение (или отметку) за день.
    func add(_ value: Double, to h: Habit, on day: Date = .now) {
        let ci = CheckIn(date: timestamp(for: day), value: value)
        context.insert(ci)
        ci.habit = h
        save()
        checkMilestone(h)
    }

    /// Переключить день: выполнено ↔ пусто. Для объёмных целей «выполнено» = вся норма.
    func toggle(_ h: Habit, on day: Date = .now) {
        let current = value(of: h, on: day)
        if engine.isDone(current, goal: h.goal) {
            clear(h, on: day)
        } else {
            add(h.goal.target - current, to: h, on: day)
        }
    }

    func clear(_ h: Habit, on day: Date) {
        for c in h.checkIns where calendar.isDate(c.date, inSameDayAs: day) {
            context.delete(c)
        }
        save()
    }

    /// Отменить последнюю запись за день.
    func undoLast(_ h: Habit, on day: Date = .now) {
        let last = h.checkIns.filter { calendar.isDate($0.date, inSameDayAs: day) }.max { $0.date < $1.date }
        if let last { context.delete(last); save() }
    }

    // MARK: - Срывы

    /// Записывает срыв и возвращает серию, которая была до него, — для честного «рекорд сохранён».
    @discardableResult
    func recordRelapse(_ h: Habit, date: Date, amount: Double, trigger: String, note: String) -> QuitStreak {
        let before = engine.quitStreak(h.snapshot, now: date)
        let r = Relapse(date: date, amount: amount, trigger: trigger, note: note)
        context.insert(r)
        r.habit = h
        save()
        return before
    }

    func deleteRelapse(_ r: Relapse) {
        context.delete(r)
        save()
    }

    // MARK: - Награды

    /// Проверяет, достигнута ли новая награда, и ставит поздравление в очередь.
    func checkMilestone(_ h: Habit) {
        let best: Int
        switch h.kind {
        case .build: best = engine.buildStreak(h.snapshot).best
        case .quit: best = engine.quitStreak(h.snapshot).bestDays
        }
        guard best > h.celebratedDays else { return }
        let reached = RewardEngine.newlyReached(from: h.celebratedDays, to: best)
        h.celebratedDays = best
        save()
        if let reached {
            celebration = Celebration(habitName: h.name, milestone: reached, kind: h.kind, colorHex: h.colorHex)
            Haptics.celebrate()
        }
    }

    /// Для отказа награды приходят сами со временем — проверяем при открытии экрана.
    func checkAllMilestones(_ habits: [Habit]) {
        for h in habits where !h.isArchived {
            checkMilestone(h)
            if celebration != nil { break }
        }
    }

    // MARK: - Помощники

    /// Сегодня — текущее время, прошлый день — полдень, чтобы запись точно попала в нужную дату.
    private func timestamp(for day: Date) -> Date {
        if calendar.isDateInToday(day) { return .now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    /// Лучшая серия среди всех привычек — открывает «наградные» иконки.
    func bestDaysOverall(_ habits: [Habit]) -> Int {
        habits.map { h in
            switch h.kind {
            case .build: return engine.buildStreak(h.snapshot).best
            case .quit: return engine.quitStreak(h.snapshot).bestDays
            }
        }.max() ?? 0
    }

    func deleteAll() {
        try? context.delete(model: Habit.self)
        try? context.delete(model: CheckIn.self)
        try? context.delete(model: Relapse.self)
        save()
        NotificationService.cancelAll()
    }
}
