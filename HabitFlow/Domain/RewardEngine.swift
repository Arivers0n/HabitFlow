import Foundation

struct Milestone: Identifiable, Hashable, Sendable {
    let days: Int
    let title: String
    let symbol: String
    var id: Int { days }
}

/// Награды за непрерывность. Для полезных привычек считается лучшая серия
/// в днях, для отказа — лучший промежуток без срыва.
enum RewardEngine {
    static let milestones: [Milestone] = [
        .init(days: 1, title: "Первый шаг", symbol: "leaf.fill"),
        .init(days: 3, title: "Три дня", symbol: "flame.fill"),
        .init(days: 7, title: "Неделя", symbol: "star.fill"),
        .init(days: 14, title: "Две недели", symbol: "star.circle.fill"),
        .init(days: 21, title: "Привычка формируется", symbol: "sparkles"),
        .init(days: 30, title: "Месяц", symbol: "medal.fill"),
        .init(days: 60, title: "Два месяца", symbol: "rosette"),
        .init(days: 90, title: "Квартал", symbol: "trophy.fill"),
        .init(days: 180, title: "Полгода", symbol: "crown.fill"),
        .init(days: 365, title: "Год", symbol: "sun.max.fill"),
    ]

    static func achieved(bestDays: Int) -> [Milestone] {
        milestones.filter { $0.days <= bestDays }
    }

    static func next(after days: Int) -> Milestone? {
        milestones.first { $0.days > days }
    }

    /// Прогресс к следующей награде, 0…1. Если все награды получены — 1.
    static func progressToNext(days: Double) -> (next: Milestone?, progress: Double) {
        let whole = Int(days)
        guard let next = next(after: whole) else { return (nil, 1) }
        let prev = milestones.last { $0.days <= whole }?.days ?? 0
        let span = Double(next.days - prev)
        return (next, min(1, max(0, (days - Double(prev)) / span)))
    }

    /// Награда, которую только что получили: серия была меньше порога, стала не меньше.
    static func newlyReached(from old: Int, to new: Int) -> Milestone? {
        milestones.last { $0.days > old && $0.days <= new }
    }
}
