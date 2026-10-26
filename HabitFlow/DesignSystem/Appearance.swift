import SwiftUI
import Observation

// MARK: - Варианты настроек

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case deep, midnight, aurora, graphite, oled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .deep: "Глубина"
        case .midnight: "Полночь"
        case .aurora: "Аврора"
        case .graphite: "Графит"
        case .oled: "OLED"
        }
    }
}

enum CardStyle: String, Codable, CaseIterable, Identifiable {
    case glass, solid, outline
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: "Стекло"
        case .solid: "Сплошные"
        case .outline: "Контур"
        }
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Системный"
        case .rounded: "Скруглённый"
        case .serif: "С засечками"
        case .mono: "Моно"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

enum SchemeChoice: String, Codable, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "Тёмная"
        case .light: "Светлая"
        case .system: "Как в системе"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

enum Tone: String, Codable, CaseIterable, Identifiable {
    case gentle, strict
    var id: String { rawValue }
    var title: String { self == .gentle ? "Мягкий" : "Строгий" }
}

enum Density: String, Codable, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var title: String { self == .comfortable ? "Просторно" : "Компактно" }
}

// MARK: - Настройки

struct AppSettings: Codable, Equatable {
    var accentHex = "4C8DFF"
    var background: BackgroundStyle = .deep
    var cardStyle: CardStyle = .glass
    var font: FontChoice = .rounded
    var scheme: SchemeChoice = .dark
    var tone: Tone = .gentle
    var density: Density = .comfortable
    var animationsOn = true
    var hapticsOn = true
    var quitFirst = false
    var showSummary = true
    var showWeekStrip = true
    var liveSeconds = true
    var showSavings = true

    init() {}

    // Новые поля могут отсутствовать в старых сохранениях — берём значения по умолчанию.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        accentHex = (try? c.decodeIfPresent(String.self, forKey: .accentHex)) ?? d.accentHex
        background = (try? c.decodeIfPresent(BackgroundStyle.self, forKey: .background)) ?? d.background
        cardStyle = (try? c.decodeIfPresent(CardStyle.self, forKey: .cardStyle)) ?? d.cardStyle
        font = (try? c.decodeIfPresent(FontChoice.self, forKey: .font)) ?? d.font
        scheme = (try? c.decodeIfPresent(SchemeChoice.self, forKey: .scheme)) ?? d.scheme
        tone = (try? c.decodeIfPresent(Tone.self, forKey: .tone)) ?? d.tone
        density = (try? c.decodeIfPresent(Density.self, forKey: .density)) ?? d.density
        animationsOn = (try? c.decodeIfPresent(Bool.self, forKey: .animationsOn)) ?? d.animationsOn
        hapticsOn = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsOn)) ?? d.hapticsOn
        quitFirst = (try? c.decodeIfPresent(Bool.self, forKey: .quitFirst)) ?? d.quitFirst
        showSummary = (try? c.decodeIfPresent(Bool.self, forKey: .showSummary)) ?? d.showSummary
        showWeekStrip = (try? c.decodeIfPresent(Bool.self, forKey: .showWeekStrip)) ?? d.showWeekStrip
        liveSeconds = (try? c.decodeIfPresent(Bool.self, forKey: .liveSeconds)) ?? d.liveSeconds
        showSavings = (try? c.decodeIfPresent(Bool.self, forKey: .showSavings)) ?? d.showSavings
    }
}

/// Сохранённая тема целиком: применяется одним касанием.
struct ThemePreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var settings: AppSettings
    var builtIn = false

    static let builtIns: [ThemePreset] = {
        func p(_ name: String, _ edit: (inout AppSettings) -> Void) -> ThemePreset {
            var s = AppSettings()
            edit(&s)
            return ThemePreset(name: name, settings: s, builtIn: true)
        }
        return [
            p("Глубина") { _ in },
            p("Полночь") { $0.background = .midnight; $0.accentHex = "6E6BFF" },
            p("Аврора") { $0.background = .aurora; $0.accentHex = "9B6BFF" },
            p("Лес") { $0.background = .graphite; $0.accentHex = "3DDC97"; $0.cardStyle = .solid },
            p("OLED") { $0.background = .oled; $0.cardStyle = .outline; $0.accentHex = "5AC8FA"; $0.font = .system },
            p("Бумага") { $0.scheme = .light; $0.font = .serif; $0.cardStyle = .solid; $0.accentHex = "2B6CF0" },
        ]
    }()
}

/// Внешний вид и поведение. Все экраны читают отсюда, поэтому новая опция
/// добавляется в одном месте и не требует переписывать экраны.
@MainActor
@Observable
final class Appearance {
    static let shared = Appearance()

    var s: AppSettings {
        didSet { persist() }
    }

    var customPresets: [ThemePreset] {
        didSet { persistPresets() }
    }

    private static let key = "appearance.v1"
    private static let presetsKey = "appearance.presets.v1"

    private init() {
        let ud = UserDefaults.standard
        s = (ud.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        customPresets = (ud.data(forKey: Self.presetsKey)).flatMap { try? JSONDecoder().decode([ThemePreset].self, from: $0) } ?? []
        PrefSync.register("appearance", export: { [weak self] in
            guard let self else { return nil }
            return try? JSONEncoder().encode(SyncedLook(settings: self.s, presets: self.customPresets))
        }, apply: { [weak self] data in
            guard let self, let look = try? JSONDecoder().decode(SyncedLook.self, from: data) else { return }
            self.s = look.settings
            self.customPresets = look.presets
        })
    }

    private struct SyncedLook: Codable {
        var settings: AppSettings
        var presets: [ThemePreset]
    }

    var accent: Color { Color(hex: s.accentHex) }
    var hapticsOn: Bool { s.hapticsOn }

    func apply(_ preset: ThemePreset) {
        var next = preset.settings
        // Пресет меняет только вид — поведение (вибрация, анимации, порядок) оставляем как было.
        next.animationsOn = s.animationsOn
        next.hapticsOn = s.hapticsOn
        next.quitFirst = s.quitFirst
        next.showSummary = s.showSummary
        next.showWeekStrip = s.showWeekStrip
        next.liveSeconds = s.liveSeconds
        next.showSavings = s.showSavings
        next.tone = s.tone
        s = next
    }

    func saveCurrent(as name: String) {
        customPresets.append(ThemePreset(name: name, settings: s))
    }

    func isCurrent(_ preset: ThemePreset) -> Bool {
        let p = preset.settings
        return p.accentHex == s.accentHex && p.background == s.background && p.cardStyle == s.cardStyle
            && p.font == s.font && p.scheme == s.scheme && p.density == s.density
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
        PrefSync.markChanged("appearance")
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(customPresets) { UserDefaults.standard.set(data, forKey: Self.presetsKey) }
        PrefSync.markChanged("appearance")
    }
}

// MARK: - Палитры

enum Palette {
    /// Акцент приложения.
    static let accents = ["4C8DFF", "6E6BFF", "9B6BFF", "B65CFF", "5AC8FA", "2ECFC4",
                          "3DDC97", "34C759", "FF5FA2", "FF9F0A", "FFD60A", "8E8E93"]

    /// Полезные привычки — мягкие, вдохновляющие оттенки.
    static let build = ["4C8DFF", "5AC8FA", "2ECFC4", "3DDC97", "34C759", "8FD14F",
                        "6E6BFF", "9B6BFF", "B65CFF", "B9A4FF", "64D2FF", "7ADCB4"]

    /// Вредные привычки — строгие красно-оранжевые.
    static let quit = ["FF453A", "E5384F", "FF6B4A", "FF9F0A", "FFB340", "D9542A"]

    static func colors(for kind: HabitKind) -> [String] { kind == .build ? build : quit }

    /// Цвет привычки всегда остаётся в гамме своего типа.
    static func sanitized(_ hex: String, kind: HabitKind) -> String {
        colors(for: kind).contains(hex.uppercased()) ? hex.uppercased() : colors(for: kind)[0]
    }

    static let danger = Color(hex: "FF453A")
    static let warning = Color(hex: "FF9F0A")
    static let success = Color(hex: "34C759")
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

extension Habit {
    var color: Color { Color(hex: Palette.sanitized(colorHex, kind: kind)) }
}

// MARK: - Движение

/// Единые параметры анимаций. Учитывают переключатель и «Уменьшение движения».
@MainActor
enum Motion {
    static var enabled: Bool {
        Appearance.shared.s.animationsOn && !UIAccessibility.isReduceMotionEnabled
    }
    static var press: Animation? { enabled ? .spring(response: 0.28, dampingFraction: 0.62) : nil }
    static var smooth: Animation? { enabled ? .smooth(duration: 0.35) : nil }
    static var bouncy: Animation? { enabled ? .bouncy(duration: 0.5, extraBounce: 0.12) : nil }
    static var slow: Animation? { enabled ? .easeInOut(duration: 0.8) : nil }
}

// MARK: - Тексты в выбранном тоне

@MainActor
enum Copy {
    private static var strict: Bool { Appearance.shared.s.tone == .strict }

    static var relapseButton: String { strict ? "Срыв" : "Был срыв" }
    static var relapseTitle: String { strict ? "Фиксация срыва" : "Бывает. Запишем и продолжим" }
    static var relapseSave: String { strict ? "Зафиксировать" : "Записать и начать заново" }

    static func relapseSaved(previous: String) -> String {
        strict ? "Серия обнулена. Рекорд — \(previous)."
               : "Рекорд сохранён: \(previous). Новая серия уже началась."
    }

    static func cleanFor(_ text: String) -> String { strict ? "Без срывов: \(text)" : "Ты держишься \(text)" }

    static var allDone: String { strict ? "План на сегодня выполнен" : "Всё на сегодня сделано — так держать!" }

    static func remaining(_ n: Int) -> String {
        strict ? "Осталось: \(n)" : "Ещё \(n) \(plural(n, "привычка", "привычки", "привычек")) — ты справишься"
    }

    static var newRecord: String { strict ? "Новый рекорд" : "Это твой рекорд!" }

    static var greeting: String {
        let h = Calendar.habitFlow.component(.hour, from: .now)
        switch h {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }
}
