import Foundation

// Конструктор виджетов — чистый Swift без SwiftUI, WidgetKit и SwiftData.
// Дизайн виджета — это обычные данные (Codable): их хранит приложение, читает расширение
// и рисует один и тот же рендерер. Здесь же границы значений и пресеты, поэтому любой
// конфиг (даже из старого бэкапа или с другого устройства) приводится к безопасному виду.

// MARK: - Размеры

enum WidgetFamilyKind: String, Codable, CaseIterable, Sendable {
    // Рабочий стол
    case small, medium, large
    // Экран блокировки
    case lockCircular, lockRectangular, lockInline

    var title: String {
        switch self {
        case .small: "Малый"
        case .medium: "Средний"
        case .large: "Большой"
        case .lockCircular: "Круг"
        case .lockRectangular: "Прямоугольник"
        case .lockInline: "Строка"
        }
    }

    var isLockScreen: Bool {
        switch self {
        case .lockCircular, .lockRectangular, .lockInline: true
        default: false
        }
    }

    /// Сколько блоков помещается.
    var maxBlocks: Int {
        switch self {
        case .small: 4
        case .medium: 6
        case .large: 9
        case .lockCircular: 1
        case .lockRectangular: 3
        case .lockInline: 1
        }
    }

    /// Примерный размер в пунктах (iPhone Pro Max) — для предпросмотра в конструкторе.
    var previewSize: (width: Double, height: Double) {
        switch self {
        case .small: (170, 170)
        case .medium: (364, 170)
        case .large: (364, 382)
        case .lockCircular: (76, 76)
        case .lockRectangular: (172, 76)
        case .lockInline: (234, 26)
        }
    }

    static let desktop: [WidgetFamilyKind] = [.small, .medium, .large]
    static let lock: [WidgetFamilyKind] = [.lockCircular, .lockRectangular, .lockInline]
}

// MARK: - Блоки

enum WidgetBlockKind: String, Codable, CaseIterable, Sendable {
    /// Кольцо дня: выполнено целей из запланированных.
    case dayRing
    /// «3 из 5».
    case doneText
    /// «60%».
    case percentText
    /// Самая долгая серия без срыва.
    case bestQuit
    /// Список отказов с днями.
    case quitList
    /// Самая долгая текущая серия полезной привычки.
    case buildStreak
    /// Уровень и полоска опыта.
    case level
    /// Фраза напарника.
    case phrase
    /// Первая невыполненная привычка.
    case nextHabit
    /// Семь точек недели.
    case weekDots
    /// Дата.
    case date
    /// Приветствие по времени суток.
    case greeting
    /// Питомец (картинка).
    case petImage
    /// Свой текст.
    case customText

    var title: String {
        switch self {
        case .dayRing: "Кольцо дня"
        case .doneText: "Сделано «3 из 5»"
        case .percentText: "Процент дня"
        case .bestQuit: "Серия без срыва"
        case .quitList: "Список отказов"
        case .buildStreak: "Серия привычки"
        case .level: "Уровень"
        case .phrase: "Фраза напарника"
        case .nextHabit: "Следующая привычка"
        case .weekDots: "Неделя"
        case .date: "Дата"
        case .greeting: "Приветствие"
        case .petImage: "Питомец"
        case .customText: "Свой текст"
        }
    }

    /// Блоки, которые не имеют смысла на экране блокировки (там только текст и значки).
    var allowedOnLockScreen: Bool { self != .petImage }

    /// Блок рисует форму (кольцо, полоску, точки) — ему нужны цвета акцента.
    var usesAccent: Bool {
        switch self {
        case .dayRing, .level, .weekDots: true
        default: false
        }
    }
}

enum WidgetFontDesign: String, Codable, CaseIterable, Sendable {
    case standard, rounded, serif, monospaced

    var title: String {
        switch self {
        case .standard: "Обычный"
        case .rounded: "Округлый"
        case .serif: "С засечками"
        case .monospaced: "Моноширинный"
        }
    }
}

enum WidgetAlign: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing

    var title: String {
        switch self {
        case .leading: "Слева"
        case .center: "По центру"
        case .trailing: "Справа"
        }
    }
}

struct WidgetTextStyle: Codable, Hashable, Sendable {
    /// 8…90 пунктов.
    var size: Double = 16
    /// 0…8: от ultraLight до black.
    var weight: Int = 5
    var design: WidgetFontDesign = .rounded
    var colorHex: String = "FFFFFF"
    /// 0.1…1.
    var opacity: Double = 1
    var alignment: WidgetAlign = .leading
    var uppercase: Bool = false
    /// Межбуквенный интервал, −2…10.
    var tracking: Double = 0
    /// 1…6 строк.
    var lineLimit: Int = 2

    static let sizeRange = 8.0...90.0
    static let trackingRange = -2.0...10.0

    func clamped() -> WidgetTextStyle {
        var s = self
        s.size = size.clamped(to: Self.sizeRange)
        s.weight = min(8, max(0, weight))
        s.colorHex = HexColor.normalize(colorHex, fallback: "FFFFFF")
        s.opacity = opacity.clamped(to: 0.1...1)
        s.tracking = tracking.clamped(to: Self.trackingRange)
        s.lineLimit = min(6, max(1, lineLimit))
        return s
    }
}

struct WidgetBlock: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: WidgetBlockKind
    /// Свой текст для «Свой текст»; для остальных — необязательный префикс/подпись, если не пусто.
    var text: String = ""
    var style: WidgetTextStyle = WidgetTextStyle()
    /// Цвет формы (дуга кольца, заливка полоски, выполненные точки).
    var accentHex: String = "34D399"
    /// Цвет подложки формы.
    var trackHex: String = "FFFFFF"
    var trackOpacity: Double = 0.18
    /// Толщина кольца и полоски, 2…30.
    var thickness: Double = 10
    /// Подпись под значением («дней без срыва: Курение»).
    var showCaption: Bool = true
    /// Размер подписи относительно основного текста, 0.4…1.
    var captionScale: Double = 0.6
    /// Отступ после блока, 0…40.
    var spaceAfter: Double = 4

    static let thicknessRange = 2.0...30.0

    func clamped() -> WidgetBlock {
        var b = self
        b.text = String(text.prefix(80))
        b.style = style.clamped()
        b.accentHex = HexColor.normalize(accentHex, fallback: "34D399")
        b.trackHex = HexColor.normalize(trackHex, fallback: "FFFFFF")
        b.trackOpacity = trackOpacity.clamped(to: 0...1)
        b.thickness = thickness.clamped(to: Self.thicknessRange)
        b.captionScale = captionScale.clamped(to: 0.4...1)
        b.spaceAfter = spaceAfter.clamped(to: 0...40)
        return b
    }
}

// MARK: - Фон и раскладка

enum WidgetBackgroundKind: String, Codable, CaseIterable, Sendable {
    case solid, gradient

    var title: String { self == .solid ? "Однотонный" : "Градиент" }
}

struct WidgetBackground: Codable, Hashable, Sendable {
    var kind: WidgetBackgroundKind = .gradient
    var colorA: String = "0F172A"
    var colorB: String = "1E3A5F"
    /// Угол градиента в градусах, 0…360 (0 — слева направо, 90 — сверху вниз).
    var angle: Double = 90
    var opacity: Double = 1

    func clamped() -> WidgetBackground {
        var b = self
        b.colorA = HexColor.normalize(colorA, fallback: "0F172A")
        b.colorB = HexColor.normalize(colorB, fallback: "1E3A5F")
        b.angle = angle.truncatingRemainder(dividingBy: 360)
        if b.angle < 0 { b.angle += 360 }
        b.opacity = opacity.clamped(to: 0...1)
        return b
    }
}

enum WidgetLayoutKind: String, Codable, CaseIterable, Sendable {
    /// Все блоки друг под другом.
    case stack
    /// Первый блок слева, остальные справа друг под другом.
    case leadingFeature
    /// Первый блок сверху, остальные в ряд под ним.
    case topFeature

    var title: String {
        switch self {
        case .stack: "Столбиком"
        case .leadingFeature: "Главный слева"
        case .topFeature: "Главный сверху"
        }
    }
}

struct WidgetDesign: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var family: WidgetFamilyKind
    var background: WidgetBackground = WidgetBackground()
    var layout: WidgetLayoutKind = .stack
    var align: WidgetAlign = .leading
    /// Внутренний отступ, 0…32.
    var padding: Double = 14
    /// Расстояние между колонками и блоками в раскладках, 0…32.
    var spacing: Double = 8
    var blocks: [WidgetBlock] = []

    /// Приводит значения к допустимым границам; лишние и неподходящие блоки убирает.
    func validated() -> WidgetDesign {
        var d = self
        d.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        d.background = background.clamped()
        d.padding = padding.clamped(to: 0...32)
        d.spacing = spacing.clamped(to: 0...32)
        var list = blocks.map { $0.clamped() }
        if family.isLockScreen { list = list.filter { $0.kind.allowedOnLockScreen } }
        d.blocks = Array(list.prefix(family.maxBlocks))
        return d
    }
}

// MARK: - Слоты

/// Слот — «Виджет 1…6». В системе при добавлении виджета выбирается слот,
/// а дизайн для каждого размера хранится внутри слота.
struct WidgetSlot: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var designs: [String: WidgetDesign] = [:]

    func design(for family: WidgetFamilyKind) -> WidgetDesign? { designs[family.rawValue] }

    mutating func set(_ design: WidgetDesign) {
        designs[design.family.rawValue] = design.validated()
    }
}

struct WidgetConfigSet: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let slotCount = 6

    var version: Int = WidgetConfigSet.currentVersion
    var slots: [WidgetSlot]

    static func == (a: WidgetConfigSet, b: WidgetConfigSet) -> Bool {
        a.version == b.version && a.slots == b.slots
    }

    /// Шесть слотов; в каждом — первый пресет для всех размеров, чтобы виджет сразу выглядел прилично.
    static func makeDefault() -> WidgetConfigSet {
        let presets = WidgetPreset.allCases
        var slots: [WidgetSlot] = []
        for i in 1...slotCount {
            var slot = WidgetSlot(id: i, name: "Виджет \(i)")
            let preset = presets[(i - 1) % presets.count]
            for f in WidgetFamilyKind.allCases { slot.set(WidgetPresets.make(preset, for: f)) }
            slots.append(slot)
        }
        return WidgetConfigSet(slots: slots)
    }

    /// Чинит набор: ровно шесть слотов с номерами 1…6, все дизайны в допустимых границах.
    /// Недостающие слоты и размеры заполняются пресетами. Неизвестная более новая версия не ломает чтение.
    func validated() -> WidgetConfigSet {
        var out: [WidgetSlot] = []
        let fallback = WidgetConfigSet.makeDefault()
        for i in 1...Self.slotCount {
            var slot = slots.first { $0.id == i } ?? fallback.slots[i - 1]
            slot.name = String(slot.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            if slot.name.isEmpty { slot.name = "Виджет \(i)" }
            var fixed: [String: WidgetDesign] = [:]
            for f in WidgetFamilyKind.allCases {
                if var d = slot.designs[f.rawValue] {
                    d.family = f
                    fixed[f.rawValue] = d.validated()
                } else {
                    fixed[f.rawValue] = fallback.slots[i - 1].designs[f.rawValue]
                }
            }
            slot.designs = fixed
            out.append(slot)
        }
        return WidgetConfigSet(version: Self.currentVersion, slots: out)
    }

    func slot(_ id: Int) -> WidgetSlot? { slots.first { $0.id == id } }

    mutating func update(_ design: WidgetDesign, inSlot id: Int) {
        guard let i = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[i].set(design)
    }
}

// MARK: - Цвета

enum HexColor {
    /// «#34d399», «34D399» или «fff» → «34D399». Некорректное → fallback.
    static func normalize(_ hex: String, fallback: String) -> String {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let ok = s.count == 6 && s.allSatisfy { $0.isHexDigit }
        return ok ? s : fallback
    }

    /// Составляющие 0…1. Некорректная строка даёт белый.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let s = normalize(hex, fallback: "FFFFFF")
        let v = UInt32(s, radix: 16) ?? 0xFFFFFF
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, self))
    }
}

// MARK: - Пресеты

enum WidgetPreset: String, CaseIterable, Sendable {
    case night, glass, neon, warm, paper

    var title: String {
        switch self {
        case .night: "Ночь"
        case .glass: "Стекло"
        case .neon: "Неон"
        case .warm: "Тёплый"
        case .paper: "Бумага"
        }
    }

    struct Palette: Sendable {
        var bgA: String
        var bgB: String
        var text: String
        var accent: String
        var track: String
        var trackOpacity: Double
    }

    var palette: Palette {
        switch self {
        case .night: Palette(bgA: "0F172A", bgB: "1E3A5F", text: "FFFFFF", accent: "34D399", track: "FFFFFF", trackOpacity: 0.16)
        case .glass: Palette(bgA: "2A2F45", bgB: "4B3F72", text: "F5F3FF", accent: "A78BFA", track: "FFFFFF", trackOpacity: 0.22)
        case .neon: Palette(bgA: "05050A", bgB: "11061F", text: "F0FDFF", accent: "22F5C8", track: "22F5C8", trackOpacity: 0.14)
        case .warm: Palette(bgA: "7C2D12", bgB: "F59E0B", text: "FFF7ED", accent: "FFF1C2", track: "FFFFFF", trackOpacity: 0.25)
        case .paper: Palette(bgA: "F8F5EE", bgB: "EDE6D6", text: "2B2A28", accent: "2F855A", track: "2B2A28", trackOpacity: 0.1)
        }
    }
}

enum WidgetPresets {
    /// Готовый дизайн для размера: ровно то, что видно сразу после добавления виджета.
    static func make(_ preset: WidgetPreset, for family: WidgetFamilyKind) -> WidgetDesign {
        let p = preset.palette
        func style(_ size: Double, _ weight: Int = 6, opacity: Double = 1, align: WidgetAlign = .leading, lines: Int = 2) -> WidgetTextStyle {
            WidgetTextStyle(size: size, weight: weight, design: .rounded, colorHex: p.text, opacity: opacity,
                            alignment: align, uppercase: false, tracking: 0, lineLimit: lines)
        }
        func block(_ kind: WidgetBlockKind, _ s: WidgetTextStyle, thickness: Double = 10, after: Double = 4) -> WidgetBlock {
            WidgetBlock(kind: kind, style: s, accentHex: p.accent, trackHex: p.track, trackOpacity: p.trackOpacity,
                        thickness: thickness, spaceAfter: after)
        }

        var d = WidgetDesign(name: preset.title, family: family)
        d.background = WidgetBackground(kind: .gradient, colorA: p.bgA, colorB: p.bgB, angle: 120, opacity: 1)

        switch family {
        case .small:
            d.align = .center
            d.blocks = [
                block(.dayRing, style(24, 7, align: .center), thickness: 11, after: 6),
                block(.nextHabit, style(14, 5, opacity: 0.9, align: .center, lines: 2)),
            ]
        case .medium:
            d.layout = .leadingFeature
            d.spacing = 14
            d.blocks = [
                block(.dayRing, style(28, 7, align: .center), thickness: 12),
                block(.greeting, style(17, 7)),
                block(.phrase, style(13, 5, opacity: 0.85, lines: 3), after: 6),
                block(.bestQuit, style(22, 7)),
            ]
        case .large:
            d.layout = .topFeature
            d.spacing = 10
            d.blocks = [
                block(.greeting, style(22, 7), after: 6),
                block(.dayRing, style(34, 7, align: .center), thickness: 14, after: 8),
                block(.weekDots, style(12, 5), thickness: 10),
                block(.phrase, style(14, 5, opacity: 0.85, lines: 3)),
                block(.level, style(14, 6)),
                block(.quitList, style(15, 6, lines: 3)),
            ]
        case .lockCircular:
            d.align = .center
            d.padding = 4
            d.blocks = [block(.dayRing, style(16, 7, align: .center), thickness: 6)]
        case .lockRectangular:
            d.padding = 6
            d.spacing = 2
            d.blocks = [
                block(.doneText, style(15, 7, lines: 1), after: 0),
                block(.nextHabit, style(12, 5, opacity: 0.85, lines: 1), after: 0),
            ]
        case .lockInline:
            d.padding = 0
            d.blocks = [block(.doneText, style(14, 6, lines: 1), after: 0)]
        }
        return d.validated()
    }
}
