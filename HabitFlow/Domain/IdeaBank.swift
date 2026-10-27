import Foundation

// Банк идей для проактивного мозгового штурма. Каждая идея оценена по трём осям:
// красота, понятность, «визуальный шум». Идеи с шумом не предлагаем.

struct AppIdea: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var pitch: String
    /// 1…5. Предлагаются только идеи, где визуальный шум не выше 2.
    var visualNoise: Int
    var needsDevice: Bool = false
}

enum IdeaBank {
    static let all: [AppIdea] = [
        AppIdea(id: "craving", title: "Режим «тяга»",
                pitch: "Кнопка на карточке отказа: 60 секунд дыхания с кругом, который плавно растёт и сжимается, затем таймер на 10 минут.",
                visualNoise: 1),
        AppIdea(id: "widget", title: "Виджет с Искоркой",
                pitch: "Маленький виджет: питомец и одна цифра — серия без срыва. Ничего лишнего на экране блокировки.",
                visualNoise: 1, needsDevice: true),
        AppIdea(id: "liveactivity", title: "Live Activity для счётчика",
                pitch: "Живой счётчик «без срыва» на экране блокировки — одна строка и тонкий прогресс до рекорда.",
                visualNoise: 1, needsDevice: true),
        AppIdea(id: "evening", title: "Вечерний ритуал",
                pitch: "Одна карточка в конце дня: что получилось сегодня, — и Искорка засыпает под тихий звук.",
                visualNoise: 1),
        AppIdea(id: "treats", title: "Угощения за серии",
                pitch: "За серии питомец получает угощение; кормление — единственное место, где расходуются награды, без магазина и счётчиков.",
                visualNoise: 2),
        AppIdea(id: "pairs", title: "Привязка к действию",
                pitch: "К привычке можно прикрепить «после чего»: после чистки зубов — вода. В карточке это одна строка мелким шрифтом.",
                visualNoise: 1),
        AppIdea(id: "mood", title: "Календарь настроения",
                pitch: "Цветные точки настроения из быстрых карточек на общем календаре — видно, как день связан с привычками.",
                visualNoise: 2),
        AppIdea(id: "minimal", title: "Режим «минимум»",
                pitch: "В тяжёлый день одним касанием оставить на экране только две главные привычки и спрятать остальное.",
                visualNoise: 1),
    ]

    /// Следующая идея, которую ещё не показывали. Когда все показаны — по кругу, начиная с самой давней.
    static func next(shown: [String], hasDeviceFeatures: Bool = true) -> AppIdea? {
        let pool = all.filter { $0.visualNoise <= 2 && (hasDeviceFeatures || !$0.needsDevice) }
        guard !pool.isEmpty else { return nil }
        if let fresh = pool.first(where: { !shown.contains($0.id) }) { return fresh }
        let order = shown.filter { id in pool.contains { $0.id == id } }
        let oldest = order.first
        return pool.first { $0.id == oldest } ?? pool.first
    }

    /// Готовое сообщение от напарника: заканчивается вопросом «Что скажешь?».
    static func message(_ idea: AppIdea, strict: Bool) -> String {
        let intro = strict ? "Идея:" : "Есть идея:"
        return ReplyPolish.ensureBrainstormEnding("\(intro) \(idea.title). \(idea.pitch)")
    }
}
