import AppIntents
import SwiftData
import Foundation

// MARK: - Привычка как сущность для Siri и «Быстрых команд»

struct HabitEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Привычка")
    static let defaultQuery = HabitQuery()

    let id: String
    let name: String
    let isQuit: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: LocalizedStringResource(stringLiteral: isQuit ? "Отказываюсь" : "Формирую"))
    }
}

struct HabitQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [HabitEntity.ID]) async throws -> [HabitEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        all()
    }

    @MainActor
    private func all() -> [HabitEntity] {
        let ctx = AppData.shared.container.mainContext
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        return habits.filter { !$0.isArchived }.map { HabitEntity(id: $0.id.uuidString, name: $0.name, isQuit: $0.kind == .quit) }
    }
}

@MainActor
private func findHabit(_ e: HabitEntity) -> Habit? {
    guard let id = UUID(uuidString: e.id) else { return nil }
    let ctx = AppData.shared.container.mainContext
    return try? ctx.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first
}

// MARK: - Команды

/// «Отметь воду в HabitFlow».
struct CheckHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить привычку"
    static let description = IntentDescription("Отмечает полезную привычку выполненной на сегодня (для объёмных — добавляет шаг).")
    static let openAppWhenRun = false

    @Parameter(title: "Привычка", requestValueDialog: "Какую привычку отметить?")
    var habit: HabitEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let h = findHabit(habit) else { return .result(dialog: "Не нашёл такую привычку.") }
        let store = AppData.shared.store
        if h.kind == .quit {
            let xp = store.recordResist(h)
            let days = store.engine.quitStreak(h.snapshot).currentDays
            return .result(dialog: "Отметил: устоял перед «\(h.name)». Без срыва \(pluralDays(days))\(xp > 0 ? ", +\(xp) XP" : "").")
        }
        let before = store.value(of: h)
        if h.goal.isBinary {
            if store.engine.isDone(before, goal: h.goal) {
                return .result(dialog: "«\(h.name)» уже отмечена сегодня. Серия \(pluralDays(store.engine.buildStreak(h.snapshot).current)).")
            }
            store.toggle(h)
        } else {
            store.add(h.goal.step, to: h)
        }
        let s = store.engine.buildStreak(h.snapshot)
        if h.goal.isBinary || s.todayDone {
            return .result(dialog: "Готово! «\(h.name)» — серия \(pluralDays(s.current)).")
        }
        return .result(dialog: "Добавил \(NumberText.value(h.goal.step)) \(h.goal.unit). Сегодня \(NumberText.value(s.todayValue)) из \(NumberText.value(h.goal.target)).")
    }
}

/// «Сколько дней без курения в HabitFlow».
struct StreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Узнать серию"
    static let description = IntentDescription("Говорит текущую серию и рекорд привычки.")
    static let openAppWhenRun = false

    @Parameter(title: "Привычка", requestValueDialog: "Про какую привычку рассказать?")
    var habit: HabitEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let h = findHabit(habit) else { return .result(dialog: "Не нашёл такую привычку.") }
        let engine = AppData.shared.store.engine
        if h.kind == .quit {
            let q = engine.quitStreak(h.snapshot)
            return .result(dialog: "Без «\(h.name)» уже \(DurationText.human(q.current)). Рекорд — \(DurationText.human(q.best)).")
        }
        let s = engine.buildStreak(h.snapshot)
        return .result(dialog: "«\(h.name)»: серия \(pluralDays(s.current)), рекорд \(pluralDays(s.best)).\(s.todayDone ? " Сегодня уже сделано." : "")")
    }
}

/// Открыть чат с напарником.
struct OpenChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Поговорить с напарником"
    static let description = IntentDescription("Открывает HabitFlow и чат с напарником.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.chat(about: nil)
        return .result()
    }
}

/// Создать привычки голосом через ИИ.
struct NewHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Новая привычка"
    static let description = IntentDescription("Открывает HabitFlow на создании привычки с ИИ.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.tab = .today
        AppRouter.shared.showAIComposer = true
        return .result()
    }
}

struct HabitFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckHabitIntent(),
                    phrases: ["Отметь \(\.$habit) в \(.applicationName)",
                              "Отметить привычку в \(.applicationName)",
                              "Я сделал \(\.$habit) в \(.applicationName)"],
                    shortTitle: "Отметить",
                    systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: StreakIntent(),
                    phrases: ["Какая серия \(\.$habit) в \(.applicationName)",
                              "Сколько дней в \(.applicationName)"],
                    shortTitle: "Серия",
                    systemImageName: "flame.fill")
        AppShortcut(intent: OpenChatIntent(),
                    phrases: ["Поговорить с напарником в \(.applicationName)",
                              "Открой напарника в \(.applicationName)"],
                    shortTitle: "Напарник",
                    systemImageName: "bubble.left.and.bubble.right.fill")
        AppShortcut(intent: NewHabitIntent(),
                    phrases: ["Новая привычка в \(.applicationName)"],
                    shortTitle: "Новая привычка",
                    systemImageName: "plus.circle.fill")
    }
}
