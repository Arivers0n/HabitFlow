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

    /// Тестовый режим: база в памяти, без уведомлений, синхронизации и угощений.
    let isTest: Bool

    init(context: ModelContext, isTest: Bool = false) {
        self.context = context
        self.isTest = isTest
    }

    func save() {
        do { try context.save() } catch { print("Ошибка сохранения: \(error)") }
        if !isTest { SyncEngine.shared.schedulePush() }
    }

    /// Удаление с отметкой для сервера: на других устройствах запись тоже исчезнет.
    private func remove(_ m: some PersistentModel & SyncStamped, kind: String) {
        if !isTest { Tombstones.add(m.id, kind: kind) }
        context.delete(m)
    }

    // MARK: - Привычки

    @discardableResult
    func create(_ draft: HabitDraft) -> Habit {
        let count = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        let h = Habit(name: draft.name, kind: draft.kind)
        draft.apply(to: h)
        h.sortOrder = count
        h.touch()
        context.insert(h)
        save()
        notify(h)
        return h
    }

    func update(_ h: Habit, with draft: HabitDraft) {
        draft.apply(to: h)
        h.touch()
        save()
        notify(h)
    }

    func delete(_ h: Habit) {
        if !isTest { NotificationService.cancel(h.id) }
        if !isTest {
            for c in h.checkIns { Tombstones.add(c.id, kind: "checkin") }
            for r in h.relapses { Tombstones.add(r.id, kind: "relapse") }
            for r in h.resists { Tombstones.add(r.id, kind: "resist") }
        }
        remove(h, kind: "habit")
        save()
    }

    func setArchived(_ h: Habit, _ archived: Bool) {
        h.isArchived = archived
        h.touch()
        save()
        notify(h)
    }

    /// Новый порядок после перетаскивания в списке.
    func reorder(_ habits: [Habit], from source: IndexSet, to destination: Int) {
        var list = habits
        list.move(fromOffsets: source, toOffset: destination)
        for (i, h) in list.enumerated() where h.sortOrder != i {
            h.sortOrder = i
            h.touch()
        }
        save()
    }

    // MARK: - Отмена удаления

    /// Снимок привычки со всей историей — чтобы вернуть её кнопкой «Отменить».
    struct DeletedHabit {
        let dto: BackupService.HabitDTO
        let checkInIDs: [UUID]
        let relapseIDs: [UUID]
        let resistIDs: [UUID]
    }

    private(set) var lastDeleted: DeletedHabit?

    func deleteWithUndo(_ h: Habit) {
        lastDeleted = DeletedHabit(dto: BackupService.dto(h),
                                   checkInIDs: h.checkIns.map(\.id),
                                   relapseIDs: h.relapses.map(\.id),
                                   resistIDs: h.resists.map(\.id))
        delete(h)
    }

    @discardableResult
    func undoDelete() -> Habit? {
        guard let d = lastDeleted else { return nil }
        lastDeleted = nil
        let h = BackupService.restore(d.dto, ids: (d.checkInIDs, d.relapseIDs, d.resistIDs), into: context)
        Tombstones.remove([h.id.uuidString] + (d.checkInIDs + d.relapseIDs + d.resistIDs).map(\.uuidString))
        save()
        notify(h)
        return h
    }

    func forgetUndo() { lastDeleted = nil }

    // MARK: - Отметки полезных привычек

    func value(of h: Habit, on day: Date = .now) -> Double {
        h.checkIns.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.value }
    }

    /// Добавить значение (или отметку) за день.
    func add(_ value: Double, to h: Habit, on day: Date = .now) {
        let before = self.value(of: h, on: day)
        let ci = CheckIn(date: timestamp(for: day), value: value)
        context.insert(ci)
        ci.habit = h
        // Угощение для напарника — за выполненную сегодня цель, а не за каждое касание.
        if calendar.isDateInToday(day), !engine.isDone(before, goal: h.goal), engine.isDone(before + value, goal: h.goal) {
            if !isTest {
                CompanionManager.shared.earnTreat()
                SoundService.shared.play(.done)
                RelaxOfferCenter.shared.consider(habitName: h.name)
            }
        }
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
            remove(c, kind: "checkin")
        }
        save()
    }

    /// Отменить последнюю запись за день.
    func undoLast(_ h: Habit, on day: Date = .now) {
        let last = h.checkIns.filter { calendar.isDate($0.date, inSameDayAs: day) }.max { $0.date < $1.date }
        if let last { remove(last, kind: "checkin"); save() }
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
        if !isTest { SoundService.shared.play(.relapse) }
        return before
    }

    /// «Устоял перед искушением». Возвращает, сколько опыта это дало (0 после трёх раз за день).
    @discardableResult
    func recordResist(_ h: Habit) -> Int {
        let reward = CompanionEngine().resistReward(h.snapshot)
        let r = Resist(date: .now)
        context.insert(r)
        r.habit = h
        if reward > 0 { if !isTest { CompanionManager.shared.earnTreat() } }
        save()
        if !isTest { SoundService.shared.play(.petHappy) }
        return reward
    }

    func deleteRelapse(_ r: Relapse) {
        remove(r, kind: "relapse")
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
        h.touch()
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

    private func notify(_ h: Habit) {
        if !isTest { NotificationService.sync(h) }
    }

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
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for h in habits where !isTest {
            for c in h.checkIns { Tombstones.add(c.id, kind: "checkin") }
            for r in h.relapses { Tombstones.add(r.id, kind: "relapse") }
            for r in h.resists { Tombstones.add(r.id, kind: "resist") }
            Tombstones.add(h.id, kind: "habit")
        }
        try? context.delete(model: Habit.self)
        try? context.delete(model: CheckIn.self)
        try? context.delete(model: Relapse.self)
        try? context.delete(model: Resist.self)
        save()
        if !isTest { NotificationService.cancelAll() }
    }
}
