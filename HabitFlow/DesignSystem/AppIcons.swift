import SwiftUI
import UIKit

struct AppIconOption: Identifiable, Hashable {
    /// Имя альтернативной иконки; пусто — основная.
    let id: String
    let title: String
    let preview: String
    /// Сколько дней лучшей серии нужно, чтобы открыть иконку. 0 — доступна сразу.
    let requiredDays: Int
}

enum AppIcons {
    static let all: [AppIconOption] = [
        .init(id: "", title: "Поток", preview: "Preview-Default", requiredDays: 0),
        .init(id: "AppIcon-Emerald", title: "Изумруд", preview: "Preview-Emerald", requiredDays: 0),
        .init(id: "AppIcon-Amethyst", title: "Аметист", preview: "Preview-Amethyst", requiredDays: 0),
        .init(id: "AppIcon-Ocean", title: "Океан", preview: "Preview-Ocean", requiredDays: 0),
        .init(id: "AppIcon-Sunset", title: "Закат", preview: "Preview-Sunset", requiredDays: 0),
        .init(id: "AppIcon-Neon", title: "Неон", preview: "Preview-Neon", requiredDays: 0),
        .init(id: "AppIcon-Autumn", title: "Осень", preview: "Preview-Autumn", requiredDays: 0),
        .init(id: "AppIcon-Winter", title: "Зима", preview: "Preview-Winter", requiredDays: 0),
        .init(id: "AppIcon-Mono", title: "Монохром", preview: "Preview-Mono", requiredDays: 0),
        .init(id: "AppIcon-Light", title: "Светлая", preview: "Preview-Light", requiredDays: 0),
        .init(id: "AppIcon-Bronze", title: "Бронза", preview: "Preview-Bronze", requiredDays: 7),
        .init(id: "AppIcon-Silver", title: "Серебро", preview: "Preview-Silver", requiredDays: 30),
        .init(id: "AppIcon-Gold", title: "Золото", preview: "Preview-Gold", requiredDays: 100),
        .init(id: "AppIcon-Diamond", title: "Алмаз", preview: "Preview-Diamond", requiredDays: 365),
    ]

    @MainActor
    static var currentID: String { UIApplication.shared.alternateIconName ?? "" }

    @MainActor
    static func set(_ option: AppIconOption, completion: @escaping (String?) -> Void) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion("Это устройство не поддерживает смену иконки.")
            return
        }
        UIApplication.shared.setAlternateIconName(option.id.isEmpty ? nil : option.id) { error in
            DispatchQueue.main.async { completion(error?.localizedDescription) }
        }
    }
}
