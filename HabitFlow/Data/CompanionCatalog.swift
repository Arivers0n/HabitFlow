import Foundation

/// Чем персонаж расправляется с искушением в анимации «Устоял».
enum CompanionPower: String, Sendable {
    case fire, laser, ice, bubble, nature, light, poof, rocket, party

    var verb: String {
        switch self {
        case .fire: "сжигает"
        case .laser: "утилизирует лазером"
        case .ice: "замораживает"
        case .bubble: "уносит в пузыре"
        case .nature: "оплетает листьями"
        case .light: "растворяет светом"
        case .poof: "развеивает"
        case .rocket: "отправляет в космос"
        case .party: "побеждает с конфетти"
        }
    }
}

struct CompanionCharacter: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let species: String
    let trait: String
    let tintHex: String
    let power: CompanionPower
    /// Горизонтальный центр головы (0…1 по ширине картинки) — для парящих аксессуаров.
    let headX: Double
    /// Свой персонаж из этого приложения (нарисован кодом), а не с картинок.
    let original: Bool
    /// Ширина картинки к высоте.
    var aspect: Double { CompanionCatalog.aspects[id] ?? 0.9 }

    var imageName: String { "Companion-\(id)" }
}

enum CompanionCatalog {
    static let all: [CompanionCharacter] = [
        .init(id: "dragon", name: "Искорка", species: "Дракончик",
              trait: "Энергичный и смелый. Разжигает азарт и сжигает искушения огоньком.",
              tintHex: "FF7A2E", power: .fire, headX: 0.58, original: false),
        .init(id: "sloth", name: "Кип", species: "Ленивец",
              trait: "Спокойный и поддерживающий. Поможет двигаться к целям без стресса.",
              tintHex: "C8A26B", power: .nature, headX: 0.5, original: false),
        .init(id: "capybara", name: "Капи", species: "Космо-капибара",
              trait: "Невозмутимая, как космос. Держит курс, что бы ни случилось.",
              tintHex: "8E9BFF", power: .rocket, headX: 0.45, original: false),
        .init(id: "penguin", name: "Пип", species: "Пингвинёнок",
              trait: "Бодрый и свежий. Не даст забыть про воду и замораживает соблазны.",
              tintHex: "64D2FF", power: .ice, headX: 0.48, original: false),
        .init(id: "axolotl", name: "Лоло", species: "Аксолотль",
              trait: "Мечтательная и тёплая. Верит в тебя даже в самые серые дни.",
              tintHex: "FF8FB8", power: .bubble, headX: 0.5, original: false),
        .init(id: "robot", name: "Бип", species: "Робот",
              trait: "Точный и бодрый. Любит цифры, графики и ровные серии.",
              tintHex: "5AD8FF", power: .laser, headX: 0.5, original: false),
        .init(id: "mushroom", name: "Муши", species: "Грибочек",
              trait: "Тихий садовник. Радуется каждой маленькой победе.",
              tintHex: "8FD14F", power: .nature, headX: 0.45, original: false),
        .init(id: "sheep", name: "Вули", species: "Облачко-овечка",
              trait: "Нежная и сонная. Бережёт твой покой и хороший сон.",
              tintHex: "B9A4FF", power: .light, headX: 0.5, original: false),
        .init(id: "redpanda", name: "Руми", species: "Красная панда",
              trait: "Спортивная и шумная. Празднует каждую тренировку.",
              tintHex: "FF6B4A", power: .party, headX: 0.5, original: false),
        .init(id: "ghost", name: "Джолли", species: "Весёлый дух",
              trait: "Добрый призрак. Растворяет плохое настроение без следа.",
              tintHex: "A99BFF", power: .poof, headX: 0.45, original: false),
        .init(id: "muse", name: "Муза", species: "Дух-фонарик",
              trait: "Вдохновляет и освещает путь, когда хочется сдаться.",
              tintHex: "FFD27A", power: .light, headX: 0.4, original: false),
        .init(id: "drop", name: "Бульк", species: "Капелька",
              trait: "Свежая и лёгкая. Лучший друг для привычки пить воду.",
              tintHex: "5AC8FA", power: .bubble, headX: 0.5, original: true),
        .init(id: "flame", name: "Уголёк", species: "Огонёк",
              trait: "Горячий мотиватор. Не даёт серии остыть.",
              tintHex: "FF9F0A", power: .fire, headX: 0.5, original: true),
        .init(id: "sprout", name: "Тим", species: "Росток",
              trait: "Растёт вместе с тобой — по листочку за каждый день.",
              tintHex: "3DDC97", power: .nature, headX: 0.5, original: true),
    ]

    static let aspects: [String: Double] = ["dragon": 0.951, "sloth": 0.782, "capybara": 0.749, "penguin": 0.846, "axolotl": 1.003, "robot": 0.852, "mushroom": 0.98, "sheep": 0.956, "redpanda": 0.886, "ghost": 0.974, "muse": 1.061, "drop": 0.82, "flame": 0.818, "sprout": 0.773]

    static func character(_ id: String?) -> CompanionCharacter? {
        all.first { $0.id == id }
    }
}

// MARK: - Подарки за уровни

enum GiftKind: String, Sendable {
    case headwear, aura, decor
    var title: String {
        switch self {
        case .headwear: "Над головой"
        case .aura: "Аура"
        case .decor: "Островок"
        }
    }
}

struct Gift: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let kind: GiftKind
    let level: Int
}

enum GiftCatalog {
    static let all: [Gift] = [
        .init(id: "sprout", title: "Росток", symbol: "leaf.fill", kind: .decor, level: 3),
        .init(id: "sparks", title: "Искры", symbol: "sparkles", kind: .aura, level: 4),
        .init(id: "campfire", title: "Костёр", symbol: "flame.fill", kind: .decor, level: 5),
        .init(id: "star", title: "Звёздочка", symbol: "star.fill", kind: .headwear, level: 6),
        .init(id: "flowers", title: "Цветы", symbol: "camera.macro", kind: .decor, level: 7),
        .init(id: "fireflies", title: "Светлячки", symbol: "sparkle", kind: .aura, level: 8),
        .init(id: "lantern", title: "Лампа", symbol: "lightbulb.fill", kind: .decor, level: 9),
        .init(id: "crown", title: "Корона", symbol: "crown.fill", kind: .headwear, level: 10),
        .init(id: "tree", title: "Дерево", symbol: "tree.fill", kind: .decor, level: 11),
        .init(id: "house", title: "Домик", symbol: "house.fill", kind: .decor, level: 12),
        .init(id: "halo", title: "Нимб", symbol: "circle.dashed", kind: .headwear, level: 14),
        .init(id: "hearts", title: "Сердечки", symbol: "heart.fill", kind: .aura, level: 16),
        .init(id: "moon", title: "Луна и звёзды", symbol: "moon.stars.fill", kind: .decor, level: 18),
        .init(id: "cap", title: "Шапочка мудреца", symbol: "graduationcap.fill", kind: .headwear, level: 20),
        .init(id: "rainbow", title: "Радуга", symbol: "rainbow", kind: .aura, level: 22),
        .init(id: "tent", title: "Палатка", symbol: "tent.fill", kind: .decor, level: 25),
        .init(id: "comet", title: "Комета", symbol: "sparkles", kind: .headwear, level: 30),
    ]

    static func unlocked(level: Int) -> [Gift] { all.filter { $0.level <= level } }
    static func gifts(at level: Int) -> [Gift] { all.filter { $0.level == level } }
    static func next(after level: Int) -> Gift? { all.first { $0.level > level } }
}
