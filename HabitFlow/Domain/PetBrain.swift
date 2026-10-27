import Foundation

// «Мозг» питомца: что чувствует, куда смотрит и когда моргает.
// Чистый Swift без UI — рисует это 3D-слой (Features/Companion/Pet3D), а здесь только решения.
// Всё считается от времени и входных чисел, без скрытого состояния: одно и то же в тот же момент
// даёт одно и то же лицо, поэтому при перерисовке ничего не «дёргается».

/// События приложения, на которые напарник отвечает мимикой и движением.
enum PetAppEvent: String, Sendable, CaseIterable {
    /// Привычка выполнена.
    case habitDone
    /// Все цели дня закрыты.
    case allDone
    /// Срыв — напарник поддерживает, а не ругает.
    case relapse
    /// «Устоял перед искушением».
    case resist
    /// Новый уровень.
    case levelUp

    /// Сколько секунд держится реакция.
    var duration: Double {
        switch self {
        case .habitDone: 1.6
        case .allDone: 3.2
        case .relapse: 5.0
        case .resist: 2.4
        case .levelUp: 3.4
        }
    }
}

enum PetExpression: String, Sendable, CaseIterable {
    case calm, happy, joy, proud, sad, worried, sleepy, surprised, love, eating, ticklish
}

/// Лицо питомца числами 0…1 (где не сказано иное). 3D-слой плавно подводит к ним черты.
struct PetFace: Equatable, Sendable {
    /// 0 — глаза закрыты, 1 — открыты, >1 — широко раскрыты.
    var eyeOpen = 1.0
    /// Глаза-дуги «^ ^» (радость, щекотка).
    var joyEyes = 0.0
    /// Глаза-сердечки (гладят).
    var heartEyes = 0.0
    /// −1 грусть … 0 ровно … 1 широкая улыбка.
    var smile = 0.35
    /// Рот раскрыт: 0 закрыт … 1 широко.
    var mouthOpen = 0.0
    /// −1 брови «домиком» (тревога, грусть) … 1 бодрые, приподняты.
    var brow = 0.0
    var blush = 0.15
    /// Взгляд −1…1 (вправо и вниз положительные, как в координатах экрана).
    var gazeX = 0.0
    var gazeY = 0.0

    /// Плавный переход к другому лицу: k = 0 — это лицо, k = 1 — другое.
    func mixed(to o: PetFace, _ k: Double) -> PetFace {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return PetFace(eyeOpen: m(eyeOpen, o.eyeOpen), joyEyes: m(joyEyes, o.joyEyes),
                       heartEyes: m(heartEyes, o.heartEyes), smile: m(smile, o.smile),
                       mouthOpen: m(mouthOpen, o.mouthOpen), brow: m(brow, o.brow),
                       blush: m(blush, o.blush), gazeX: m(gazeX, o.gazeX), gazeY: m(gazeY, o.gazeY))
    }
}

/// Что сейчас происходит с питомцем — из этого выбирается выражение.
struct PetSituation: Sendable {
    var mood: CompanionMood = .calm
    var asleep = false
    /// Взяли в руку или летит после броска.
    var held = false
    var tickling = false
    /// 0…1, пока идёт кормление.
    var feedPhase: Double? = nil
    /// Гладят прямо сейчас.
    var petting = false
    var sinceJump = 99.0
    var sinceWake = 99.0
    var reaction: PetAppEvent? = nil
    var sinceReaction = 99.0
}

enum PetBrain {
    // MARK: - Выражение

    /// Какое выражение и насколько сильно. Порядок — по важности: сон, рука, щекотка, еда, поглаживание,
    /// реакция на событие приложения, пробуждение, прыжок, затем общее настроение.
    static func expression(_ s: PetSituation) -> (expression: PetExpression, intensity: Double) {
        if s.asleep { return (.sleepy, 1) }
        if s.held { return (.surprised, 0.85) }
        if s.tickling { return (.ticklish, 1) }
        if s.feedPhase != nil { return (.eating, 1) }
        if s.petting { return (.love, 1) }
        if let e = s.reaction, s.sinceReaction < e.duration {
            let k = fade(s.sinceReaction, e.duration)
            switch e {
            case .habitDone: return (.joy, k)
            case .allDone: return (.proud, k)
            case .resist: return (.proud, k)
            case .levelUp: return (.joy, k)
            case .relapse: return (.worried, k)
            }
        }
        if s.sinceWake < 1.1 { return (.surprised, fade(s.sinceWake, 1.1)) }
        if s.sinceJump < 0.75 { return (.happy, fade(s.sinceJump, 0.75)) }
        switch s.mood {
        case .happy: return (.happy, 1)
        case .calm: return (.calm, 1)
        case .sad: return (.sad, 1)
        case .caring: return (.worried, 0.55)
        }
    }

    /// 1 первые 70 % времени, потом плавно к 0.
    static func fade(_ since: Double, _ duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let hold = duration * 0.7
        if since <= hold { return 1 }
        return max(0, min(1, (duration - since) / (duration - hold)))
    }

    /// Целевое лицо для выражения при заданной силе (0 — спокойное лицо, 1 — выражение целиком).
    static func target(_ e: PetExpression, intensity i: Double) -> PetFace {
        let base = PetFace()
        let full: PetFace
        switch e {
        case .calm:
            full = PetFace()
        case .happy:
            full = PetFace(eyeOpen: 1, smile: 0.8, mouthOpen: 0.15, brow: 0.3, blush: 0.35)
        case .joy:
            full = PetFace(eyeOpen: 0, joyEyes: 1, smile: 1, mouthOpen: 0.55, brow: 0.5, blush: 0.5)
        case .proud:
            full = PetFace(eyeOpen: 0.9, joyEyes: 0.45, smile: 0.9, mouthOpen: 0.2, brow: 0.6, blush: 0.4)
        case .sad:
            full = PetFace(eyeOpen: 0.78, smile: -0.65, brow: -0.8, blush: 0.04)
        case .worried:
            full = PetFace(eyeOpen: 0.95, smile: 0.02, brow: -0.9, blush: 0.1)
        case .sleepy:
            full = PetFace(eyeOpen: 0, smile: 0.15, blush: 0.25)
        case .surprised:
            full = PetFace(eyeOpen: 1.25, smile: 0, mouthOpen: 0.7, brow: 0.9, blush: 0.08)
        case .love:
            full = PetFace(eyeOpen: 0, heartEyes: 1, smile: 0.9, mouthOpen: 0.2, brow: 0.3, blush: 0.75)
        case .eating:
            full = PetFace(eyeOpen: 0.85, smile: 0.5, mouthOpen: 0.4, brow: 0.2, blush: 0.35)
        case .ticklish:
            full = PetFace(eyeOpen: 0, joyEyes: 1, smile: 1, mouthOpen: 0.9, brow: 0.4, blush: 0.6)
        }
        return base.mixed(to: full, max(0, min(1, i)))
    }

    /// Готовое лицо на момент `t`: выражение + моргание + рот при еде + взгляд.
    static func face(_ s: PetSituation, blink: Double, gaze: (x: Double, y: Double)) -> PetFace {
        let (e, i) = expression(s)
        var f = target(e, intensity: i)
        if e == .eating, let phase = s.feedPhase { f.mouthOpen = eatingMouth(phase) }
        // Моргают только открытыми глазами: дуги, сердечки и закрытые глаза остаются как есть.
        let openness = max(0, 1 - f.joyEyes - f.heartEyes)
        f.eyeOpen *= 1 - max(0, min(1, blink)) * openness
        f.gazeX = max(-1, min(1, gaze.x))
        f.gazeY = max(-1, min(1, gaze.y))
        return f
    }

    /// Рот при кормлении: ждёт угощение, раскрывается навстречу, потом жуёт.
    static func eatingMouth(_ phase: Double) -> Double {
        if phase < 0.12 { return 0.25 }
        if phase < 0.32 { return 0.25 + 0.75 * (phase - 0.12) / 0.2 }
        if phase < 0.86 {
            // жуём: рот открывается и закрывается примерно три раза
            return 0.12 + 0.5 * (0.5 + 0.5 * cos(2 * Double.pi * (phase - 0.32) / 0.18))
        }
        return 0.2
    }

    // MARK: - Моргание и взгляд

    /// Устойчивый «случайный» хэш в 0…1: один и тот же при одних и тех же входных числах.
    static func hash01(_ a: Int, _ b: Int) -> Double {
        var x = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(b)) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 30
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }

    /// Моргание: 0 — глаза открыты, 1 — закрыты. Раз в несколько секунд, иногда дважды подряд.
    static func blink(t: Double, seed: Int) -> Double {
        let period = 3.6
        let slot = Int((t / period).rounded(.down))
        let local = t - Double(slot) * period
        let start = 0.4 + hash01(slot, seed) * (period - 1.4)
        let twice = hash01(slot, seed &+ 7) < 0.22
        func pulse(_ x: Double) -> Double {
            guard x >= 0, x < 0.17 else { return 0 }
            return sin(Double.pi * x / 0.17)
        }
        return max(pulse(local - start), twice ? pulse(local - start - 0.26) : 0)
    }

    /// Блуждающий взгляд, когда никто не трогает: каждые ~2.4 с новая точка, чаще — прямо перед собой.
    static func idleGaze(t: Double, seed: Int) -> (x: Double, y: Double) {
        let period = 2.4
        let slot = Int((t / period).rounded(.down))
        if hash01(slot, seed &+ 3) < 0.38 { return (0, 0) }
        return ((hash01(slot, seed &+ 1) - 0.5) * 1.3, (hash01(slot, seed &+ 2) - 0.5) * 0.7)
    }

    /// Куда смотреть: палец (если недавно касались) важнее наклона телефона, наклон — важнее блуждания.
    static func gaze(finger: (x: Double, y: Double)?, tilt: (x: Double, y: Double), t: Double, seed: Int) -> (x: Double, y: Double) {
        if let f = finger { return f }
        let idle = idleGaze(t: t, seed: seed)
        return (idle.x * 0.6 + tilt.x * 0.7, idle.y * 0.6 + tilt.y * 0.5)
    }
}
