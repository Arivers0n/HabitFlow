import Foundation
import UIKit
import UserNotifications
import Observation

// MARK: - Тактильный отклик

/// Вибрация с учётом переключателя в настройках.
@MainActor
enum Haptics {
    private static var on: Bool { Appearance.shared.hapticsOn }

    static func tap() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    static func selection() {
        guard on else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Щекотка: серия мелких лёгких толчков.
    static func tickle() {
        guard on else { return }
        let g = UIImpactFeedbackGenerator(style: .light)
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) { g.impactOccurred(intensity: 0.6) }
        }
    }

    /// Поглаживание: мягкое «мурчание».
    static func purr() {
        guard on else { return }
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.impactOccurred(intensity: 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { g.impactOccurred(intensity: 0.3) }
    }

    /// Приземление после броска — сила зависит от скорости.
    static func land(strength: Double) {
        guard on else { return }
        UIImpactFeedbackGenerator(style: strength > 0.6 ? .heavy : .medium)
            .impactOccurred(intensity: CGFloat(max(0.3, min(1, strength))))
    }

    /// «Ням» при кормлении.
    static func chomp() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
    }

    /// Двойной «тук-тук» для награды.
    static func celebrate() {
        guard on else { return }
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { g.impactOccurred(intensity: 0.8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Напоминания

@MainActor
enum NotificationService {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Пересоздаёт напоминания привычки по её текущим настройкам.
    static func sync(_ h: Habit) {
        cancel(h.id)
        guard h.reminderOn, !h.isArchived else { return }
        let id = h.id
        let name = h.name
        let kind = h.kind
        let minutes = h.reminderMinutes
        let days: [Int]
        if case .weekdays(let set) = h.schedule { days = Array(set) } else { days = [] }

        Task {
            guard await requestAuthorization() else { return }
            let content = UNMutableNotificationContent()
            content.title = name
            content.body = kind == .quit
                ? "Ты держишься. Загляни, как идёт серия."
                : "Время для привычки. Отметь, когда сделаешь."
            content.sound = .default

            let center = UNUserNotificationCenter.current()
            let targets: [Int?] = days.isEmpty ? [nil] : days.map { Optional($0) }
            for wd in targets {
                var comps = DateComponents()
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                comps.weekday = wd
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let req = UNNotificationRequest(identifier: "habit-\(id.uuidString)-\(wd ?? 0)",
                                                content: content, trigger: trigger)
                try? await center.add(req)
            }
        }
    }

    static func cancel(_ id: UUID) {
        let ids = (0...7).map { "habit-\(id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Снимает только напоминания привычек. Быстрые карточки и недельный разбор — отдельные настройки,
    /// их удаление данных не касается.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("habit-") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

// MARK: - Библиотека триггеров

struct TriggerItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
}

/// Свои причины срывов: можно добавлять, переименовывать и менять иконки.
@MainActor
@Observable
final class TriggerLibrary {
    static let shared = TriggerLibrary()
    private static let key = "triggers.v1"

    var items: [TriggerItem] {
        didSet { persist() }
    }

    static let defaults: [TriggerItem] = [
        .init(name: "Стресс", symbol: "bolt.heart.fill"),
        .init(name: "Скука", symbol: "hourglass"),
        .init(name: "Компания", symbol: "person.3.fill"),
        .init(name: "Усталость", symbol: "zzz"),
        .init(name: "Праздник", symbol: "party.popper.fill"),
        .init(name: "Грусть", symbol: "cloud.rain.fill"),
        .init(name: "После еды", symbol: "fork.knife"),
        .init(name: "Сильная тяга", symbol: "flame.fill"),
        .init(name: "На автомате", symbol: "arrow.triangle.2.circlepath"),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([TriggerItem].self, from: data), !saved.isEmpty {
            items = saved
        } else {
            items = Self.defaults
        }
        PrefSync.register("triggers", export: { [weak self] in
            guard let self else { return nil }
            return try? JSONEncoder().encode(self.items)
        }, apply: { [weak self] data in
            guard let self, let list = try? JSONDecoder().decode([TriggerItem].self, from: data), !list.isEmpty else { return }
            self.items = list
        })
    }

    func symbol(for name: String) -> String {
        items.first { $0.name == name }?.symbol ?? "questionmark.circle"
    }

    func resetToDefaults() { items = Self.defaults }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        PrefSync.markChanged("triggers")
    }
}
