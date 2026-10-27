import Foundation
import UserNotifications
import Observation

// MARK: - Настроение

/// Оценки настроения 1…5 из быстрых карточек. Хранятся только на устройстве.
@MainActor
final class MoodLog {
    static let shared = MoodLog()
    private let key = "hf.moodlog.v1"
    private var calendar: Calendar { .habitFlow }

    private init() {}

    private var entries: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func record(_ level: Int, on date: Date = .now) {
        var e = entries
        e[dayKey(date)] = min(5, max(1, level))
        // Храним не больше трёх месяцев.
        if e.count > 100 {
            for k in e.keys.sorted().prefix(e.count - 100) { e.removeValue(forKey: k) }
        }
        entries = e
    }

    func level(on date: Date = .now) -> Int? { entries[dayKey(date)] }

    var answeredToday: Bool { level() != nil }

    /// Среднее за последние `days` дней, если было хотя бы две оценки.
    func average(days: Int = 7, now: Date = .now) -> Double? {
        let values = (0..<days).compactMap { level(on: calendar.addingDays(-$0, to: now)) }
        guard values.count >= 2 else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

// MARK: - Настройки

struct QuickCardSettings: Codable, Equatable {
    var enabled = false
    /// Время уведомления (минуты от полуночи).
    var minutes = 20 * 60
    /// Подбирать время автоматически по режиму дня.
    var auto = true
    var weeklyReviewOn = false
}

// MARK: - Сервис

@MainActor
@Observable
final class QuickCardsService {
    static let shared = QuickCardsService()
    private static let key = "hf.quickcards.v1"

    nonisolated static let categoryID = "hf.quickcards"
    nonisolated static let snoozeAction = "hf.quickcards.snooze"
    nonisolated static let dailyID = "hf-quickcards-daily"
    nonisolated static let snoozeID = "hf-quickcards-snooze"
    nonisolated static let weeklyID = "hf-weekly-review"

    var settings: QuickCardSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
        }
    }

    private let planner = QuickCardPlanner()
    private var calendar: Calendar { .habitFlow }

    private init() {
        settings = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(QuickCardSettings.self, from: $0) } ?? QuickCardSettings()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    // MARK: Планирование

    func suggestion(_ habits: [Habit], now: Date = .now) -> NotificationTimeSuggestion {
        return planner.suggestedMinutes(habits.map(\.snapshot), bedtimeMinutes: HealthService.shared.bedtimeMinutes, now: now)
    }

    /// Время, в которое уведомление придёт на самом деле.
    func effectiveMinutes(_ habits: [Habit]) -> Int {
        settings.auto ? suggestion(habits).minutes : settings.minutes
    }

    func deck(_ habits: [Habit], now: Date = .now) -> [QuickCard] {
        let items = habits.filter { !$0.isArchived }.map { QuickHabit(id: $0.id.uuidString, snapshot: $0.snapshot) }
        return planner.deck(items, now: now, moodAnswered: MoodLog.shared.answeredToday)
    }

    nonisolated static func registerCategories() {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Через 30 минут", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [snooze], intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Пересоздаёт уведомления карточек и недельного разбора по настройкам.
    func reschedule(habits: [Habit]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyID, Self.weeklyID])
        guard settings.enabled || settings.weeklyReviewOn else { return }
        guard await NotificationService.requestAuthorization() else { return }
        let strict = Appearance.shared.s.tone == .strict
        let title = CompanionManager.shared.hasCompanion ? CompanionManager.shared.displayName : "HabitFlow"

        if settings.enabled {
            let minutes = effectiveMinutes(habits)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = QuickReactions.notificationBody(strict: strict, hour: minutes / 60)
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.userInfo = ["link": "habitflow://cards"]
            var comps = DateComponents()
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: Self.dailyID, content: content, trigger: trigger))
        }

        if settings.weeklyReviewOn {
            let content = UNMutableNotificationContent()
            content.title = "Разбор недели"
            content.body = strict ? "Итоги недели готовы." : "Итоги недели готовы — посмотрим, как мы справились?"
            content.sound = .default
            content.userInfo = ["link": "habitflow://review"]
            var comps = DateComponents()
            comps.weekday = 1   // воскресенье
            comps.hour = 19
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: Self.weeklyID, content: content, trigger: trigger))
        }
    }

    /// «Через 30 минут» из уведомления.
    nonisolated static func scheduleSnooze() async {
        let content = UNMutableNotificationContent()
        content.title = "Быстрые карточки"
        content.body = "Напоминаю про карточки — это быстро."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["link": "habitflow://cards"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: snoozeID, content: content, trigger: trigger))
    }

    // MARK: Ответы

    struct Outcome {
        var reaction: String
        var xp: Int
    }

    /// Применяет ответ на карточку и сразу возвращает реакцию питомца и прирост опыта.
    /// Срыв здесь не записывается: для него нужны дата, количество и причина — их собирает экран срыва.
    func apply(_ answer: QuickAnswer, to card: QuickCard, habits: [Habit], store: HabitStore, seed: Int) -> Outcome {
        let engine = CompanionEngine()
        let before = engine.xp(habits.map(\.snapshot)).total
        let habit = card.habitID.flatMap { id in habits.first { $0.id.uuidString == id } }

        switch answer {
        case .done:
            if let h = habit, !store.engine.isDone(store.value(of: h), goal: h.goal) { store.toggle(h) }
        case .added(let v):
            if let h = habit, v > 0 { store.add(v, to: h) }
        case .filled:
            if let h = habit {
                let remaining = h.goal.target - store.value(of: h)
                if remaining > 0 { store.add(remaining, to: h) }
            }
        case .resisted:
            if let h = habit { store.recordResist(h) }
        case .mood(let level):
            MoodLog.shared.record(level)
        case .relapse, .noUrge, .skipped:
            break
        }

        let after = engine.xp(habits.map(\.snapshot)).total
        let userName = CompanionManager.shared.state.userName
        let strict = Appearance.shared.s.tone == .strict
        let line = QuickReactions.line(for: answer, userName: userName, strict: strict, seed: seed)
        // Звуки отметки, срыва и «устоял» играет сам стор; здесь — только нейтральный отклик.
        switch answer {
        case .mood, .skipped, .noUrge: SoundService.shared.play(.tap)
        default: break
        }
        return Outcome(reaction: line, xp: max(0, after - before))
    }
}
