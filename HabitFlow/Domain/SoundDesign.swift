import Foundation

// Звуки: всё синтезируется в коде — нет файлов, лицензий и «щелчков» на стыках.
// Здесь чистая математика и правила; воспроизведение (AVAudioEngine) — в слое Data.

// MARK: - События и настройки

enum SoundCategory: String, CaseIterable, Codable, Sendable {
    case interface, pet, rewards

    var title: String {
        switch self {
        case .interface: "Интерфейс"
        case .pet: "Питомец"
        case .rewards: "Награды"
        }
    }
}

enum SoundEvent: String, CaseIterable, Sendable {
    case tap, done, undo, relapse
    case petTap, petHappy, petSad
    case levelUp, hatch, record

    var category: SoundCategory {
        switch self {
        case .tap, .done, .undo, .relapse: .interface
        case .petTap, .petHappy, .petSad: .pet
        case .levelUp, .hatch, .record: .rewards
        }
    }
}

struct SoundSettings: Codable, Equatable, Sendable {
    var master = true
    var interface = true
    var pet = true
    var rewards = true
    /// 0…1
    var volume = 0.6
    /// Тихий режим: звуки отключены в выбранные часы.
    var quietMode = false
    var quietFromMinutes = 22 * 60
    var quietToMinutes = 8 * 60

    func isOn(_ c: SoundCategory) -> Bool {
        switch c {
        case .interface: interface
        case .pet: pet
        case .rewards: rewards
        }
    }
}

enum SoundRules {

    /// Можно ли сейчас играть событие.
    static func allows(_ event: SoundEvent, _ s: SoundSettings, now: Date = .now, calendar: Calendar = .habitFlow) -> Bool {
        guard s.master, s.isOn(event.category), s.volume > 0.001 else { return false }
        if s.quietMode && isQuiet(s, now: now, calendar: calendar) { return false }
        return true
    }

    /// Попадает ли время в тихие часы; поддерживает переход через полночь (22:00 → 08:00).
    static func isQuiet(_ s: SoundSettings, now: Date, calendar: Calendar = .habitFlow) -> Bool {
        let m = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let a = s.quietFromMinutes, b = s.quietToMinutes
        if a == b { return false }
        return a < b ? (m >= a && m < b) : (m >= a || m < b)
    }

    /// Громкость в безопасных пределах: пользовательская 0…1 → множитель 0…0.8 (квадратичная кривая, на малых значениях тише).
    static func gain(_ volume: Double) -> Float {
        let v = Float(min(1, max(0, volume)))
        return v * v * 0.8
    }
}

// MARK: - Синтез коротких звуков

struct SoundNote: Equatable, Sendable {
    /// Частота в Гц; 0 — пауза.
    var frequency: Double
    var duration: Double
    var gain: Double = 1
}

enum ToneSynth {
    static let sampleRate = 44_100.0

    /// Мелодия для события.
    static func notes(for event: SoundEvent) -> [SoundNote] {
        switch event {
        case .tap: [SoundNote(frequency: 880, duration: 0.05, gain: 0.5)]
        case .done: [SoundNote(frequency: 659.25, duration: 0.09), SoundNote(frequency: 880, duration: 0.14)]
        case .undo: [SoundNote(frequency: 523.25, duration: 0.07, gain: 0.7), SoundNote(frequency: 392, duration: 0.1, gain: 0.7)]
        case .relapse: [SoundNote(frequency: 392, duration: 0.18, gain: 0.6), SoundNote(frequency: 329.63, duration: 0.26, gain: 0.6)]
        case .petTap: [SoundNote(frequency: 987.77, duration: 0.05, gain: 0.55), SoundNote(frequency: 1174.66, duration: 0.07, gain: 0.5)]
        case .petHappy: [SoundNote(frequency: 523.25, duration: 0.08), SoundNote(frequency: 659.25, duration: 0.08), SoundNote(frequency: 783.99, duration: 0.14)]
        case .petSad: [SoundNote(frequency: 440, duration: 0.14, gain: 0.6), SoundNote(frequency: 349.23, duration: 0.24, gain: 0.6)]
        case .levelUp: [SoundNote(frequency: 523.25, duration: 0.1), SoundNote(frequency: 659.25, duration: 0.1),
                        SoundNote(frequency: 783.99, duration: 0.1), SoundNote(frequency: 1046.5, duration: 0.28)]
        case .hatch: [SoundNote(frequency: 392, duration: 0.1), SoundNote(frequency: 523.25, duration: 0.1),
                      SoundNote(frequency: 659.25, duration: 0.1), SoundNote(frequency: 783.99, duration: 0.1),
                      SoundNote(frequency: 1046.5, duration: 0.34)]
        case .record: [SoundNote(frequency: 698.46, duration: 0.09), SoundNote(frequency: 880, duration: 0.09),
                       SoundNote(frequency: 1046.5, duration: 0.22)]
        }
    }

    /// Рендер мелодии в моно-буфер. Каждая нота имеет плавное нарастание и затухание — без щелчков.
    static func render(_ notes: [SoundNote], sampleRate: Double = sampleRate) -> [Float] {
        var out: [Float] = []
        for n in notes {
            let count = max(1, Int(n.duration * sampleRate))
            let attack = min(Double(count) / 4, 0.006 * sampleRate)
            let release = min(Double(count) / 2, 0.04 * sampleRate)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                var env = 1.0
                if Double(i) < attack { env = Double(i) / attack }
                let fromEnd = Double(count - 1 - i)
                if fromEnd < release { env = min(env, fromEnd / release) }
                // Мягкая «колокольная» природа: основной тон + тихая октава, плавный спад
                let decay = exp(-3 * Double(i) / Double(count))
                let w = n.frequency > 0
                    ? sin(2 * .pi * n.frequency * t) + 0.25 * sin(4 * .pi * n.frequency * t)
                    : 0
                out.append(Float(w / 1.25 * env * (0.4 + 0.6 * decay) * n.gain * 0.5))
            }
        }
        if let first = out.first, abs(first) > 0.0001 { out[0] = 0 }
        if let last = out.last, abs(last) > 0.0001 { out[out.count - 1] = 0 }
        return out
    }
}

enum WAVEncoder {
    /// 16-бит PCM, моно.
    static func encode(_ samples: [Float], sampleRate: Int = 44_100) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(byteCount)
        for s in samples {
            let clipped = max(-1, min(1, s))
            u16(UInt16(bitPattern: Int16((clipped * 32_767).rounded())))
        }
        return data
    }
}

// MARK: - Релакс-сцены

enum AmbientScene: String, CaseIterable, Codable, Sendable, Identifiable {
    case rain, ocean, night, ember

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rain: "Дождь"
        case .ocean: "Море"
        case .night: "Ночной лес"
        case .ember: "Тёплый огонь"
        }
    }
    var symbol: String {
        switch self {
        case .rain: "cloud.rain.fill"
        case .ocean: "water.waves"
        case .night: "moon.stars.fill"
        case .ember: "flame.fill"
        }
    }
}

/// Бесконечный генератор фоновых звуков. Детерминирован (xorshift), пригоден для вызова из аудио-потока:
/// не выделяет память и не использует блокировок.
struct AmbientGenerator: Sendable {
    let scene: AmbientScene
    let sampleRate: Double
    private var rng: UInt64
    private var low1: Float = 0
    private var low2: Float = 0
    private var phase: Double = 0
    private var cricket: Double = 0
    private var crackle: Float = 0

    init(scene: AmbientScene, sampleRate: Double = 44_100, seed: UInt64 = 0x9E3779B97F4A7C15) {
        self.scene = scene
        self.sampleRate = sampleRate
        rng = seed == 0 ? 1 : seed
    }

    private mutating func noise() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(Double(rng >> 11) / Double(1 << 53)) * 2 - 1
    }

    mutating func next() -> Float {
        let n = noise()
        phase += 1 / sampleRate
        switch scene {
        case .rain:
            // Белый шум, срезанный сверху и снизу, + редкие «капли».
            low1 += 0.35 * (n - low1)
            let drop = noise() > 0.9993 ? Float(0.5) : 0
            crackle = crackle * 0.985 + drop
            return clamp((low1 * 0.35 + crackle * 0.3))
        case .ocean:
            // Коричневатый шум, огибающая-«волна» с периодом ~9 с.
            low1 += 0.02 * (n - low1)
            low2 += 0.2 * (low1 - low2)
            let swell = Float(0.55 + 0.45 * sin(2 * .pi * phase / 9))
            return clamp(low2 * 2.2 * swell)
        case .night:
            // Тихий ветер + стрекот сверчков (амплитудная модуляция высокого тона).
            low1 += 0.01 * (n - low1)
            cricket += 4_300 / sampleRate
            if cricket > 1 { cricket -= 1 }
            let gate = sin(2 * .pi * phase * 5.2) > 0.4 && sin(2 * .pi * phase / 3.1) > -0.2
            let c = gate ? Float(sin(2 * .pi * cricket)) * 0.05 : 0
            return clamp(low1 * 1.6 + c)
        case .ember:
            // Тёплый низкий шум и редкие потрескивания.
            low1 += 0.03 * (n - low1)
            let pop = noise() > 0.9995 ? Float(0.6) : 0
            crackle = crackle * 0.97 + pop
            return clamp(low1 * 1.3 + crackle * 0.35)
        }
    }

    private func clamp(_ x: Float) -> Float { max(-0.9, min(0.9, x)) }

    /// Заполнить буфер. Плавное появление первые ~0.5 с делает слой Data (fade), здесь — чистый поток.
    mutating func fill(_ buffer: inout [Float]) {
        for i in buffer.indices { buffer[i] = next() }
    }
}

/// Плавное нарастание/затухание для релакс-музыки и таймера сна.
struct FadeEnvelope: Sendable {
    var current: Float = 0
    var target: Float = 0
    /// Секунд на полный ход 0…1.
    var seconds: Float = 1.5

    mutating func fadeIn(seconds s: Float = 1.5) { target = 1; seconds = max(0.05, s) }
    mutating func fadeOut(seconds s: Float = 1.5) { target = 0; seconds = max(0.05, s) }
    var isSilent: Bool { current <= 0.0001 && target == 0 }

    mutating func step(sampleRate: Double) -> Float {
        let delta = 1 / (seconds * Float(sampleRate))
        if current < target { current = min(target, current + delta) }
        else if current > target { current = max(target, current - delta) }
        return current
    }
}

// MARK: - Тема привычки и предложение релакса

enum HabitTheme: String, Sendable {
    case focus, sleep, other

    /// Определяет тему по названию — по началу слов, а не по подстроке («персонал» — не «сон»).
    static func classify(_ name: String) -> HabitTheme {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let sleep = ["сон", "сна", "сну", "сном", "спать", "засып", "отбой", "выспат", "ложить", "лечь"]
        let focus = ["концентр", "фокус", "медит", "дыхан", "учёб", "учеб", "чтени", "читат", "читать", "работ", "занят", "изучен", "помодор", "глубок", "созерц", "йог"]
        if words.contains(where: { w in sleep.contains { w == $0 || (w.hasPrefix($0) && $0.count >= 4) } }) { return .sleep }
        if words.contains(where: { w in focus.contains { w.hasPrefix($0) } }) { return .focus }
        return .other
    }
}

struct RelaxOffer: Equatable, Sendable {
    var habitName: String
    var theme: HabitTheme
    var scene: AmbientScene
    var text: String
}

enum RelaxPlanner {
    /// Предложение включить релакс-музыку сразу после отметки привычки на концентрацию или сон.
    static func offer(afterCompleting name: String, strict: Bool) -> RelaxOffer? {
        let theme = HabitTheme.classify(name)
        switch theme {
        case .sleep:
            return RelaxOffer(habitName: name, theme: theme, scene: .rain,
                              text: strict ? "Готовимся ко сну. Включить фон?" : "Пора ко сну. Включить тихий дождь?")
        case .focus:
            return RelaxOffer(habitName: name, theme: theme, scene: .ocean,
                              text: strict ? "Включить фон для концентрации?" : "Хочешь, включу спокойный шум моря для концентрации?")
        case .other:
            return nil
        }
    }
}
