import Foundation

// Здоровье: сон, шаги, тренировки → короткие советы напарника.
// Чистый Swift: данные из HealthKit приносит слой Data, а правила проверяются тестами.
// Напарник не ставит диагнозов — только мягкие подсказки про режим и воду.

/// Промежуток, когда человек спал (без «лежал в кровати»).
struct SleepInterval: Equatable, Sendable {
    var start: Date
    var end: Date
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Одна ночь: от засыпания до пробуждения. `asleep` — только время сна, без ночных пробуждений.
struct SleepNight: Equatable, Sendable {
    var start: Date
    var end: Date
    var asleep: TimeInterval
}

/// Что известно о здоровье. Любое поле может быть пустым: данных нет или доступ не дан.
struct HealthSnapshot: Equatable, Sendable {
    var sleepStart: Date? = nil
    var sleepEnd: Date? = nil
    var sleepSeconds: TimeInterval? = nil
    var deepSeconds: TimeInterval? = nil
    var remSeconds: TimeInterval? = nil
    var steps: Int? = nil
    var activeCalories: Double? = nil
    var workoutMinutes: Double? = nil
    /// Средний сон за последние ночи (для разбора недели).
    var sleepAverageSeconds: TimeInterval? = nil
    var sleepNights: Int = 0
    var asOf: Date = .now

    var hasAnything: Bool {
        sleepSeconds != nil || steps != nil || activeCalories != nil || workoutMinutes != nil
    }
}

enum SleepMath {

    /// Склеивает пересекающиеся и соприкасающиеся промежутки. Часы и телефон часто пишут один и тот же
    /// сон дважды — без склейки он посчитался бы вдвое.
    static func merge(_ items: [SleepInterval]) -> [SleepInterval] {
        let valid = items.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var out: [SleepInterval] = []
        for item in valid {
            if let last = out.last, item.start <= last.end {
                out[out.count - 1].end = max(last.end, item.end)
            } else {
                out.append(item)
            }
        }
        return out
    }

    /// Сколько секунд из `items` попало в окно `window` (после склейки, без двойного счёта).
    static func overlap(_ items: [SleepInterval], with window: SleepInterval) -> TimeInterval {
        merge(items).reduce(0) { acc, i in
            let s = max(i.start, window.start)
            let e = min(i.end, window.end)
            return acc + max(0, e.timeIntervalSince(s))
        }
    }

    /// Ночи: промежутки с паузой меньше `maxGap` считаются одним сном — ночное пробуждение не делит ночь.
    /// Дневной сон (середина не ночью) в ночи не попадает.
    static func nights(_ items: [SleepInterval], maxGap: TimeInterval = 90 * 60,
                       minAsleep: TimeInterval = 3_600, calendar: Calendar = .habitFlow) -> [SleepNight] {
        let merged = merge(items)
        var groups: [[SleepInterval]] = []
        for i in merged {
            if let last = groups.last?.last, i.start.timeIntervalSince(last.end) <= maxGap {
                groups[groups.count - 1].append(i)
            } else {
                groups.append([i])
            }
        }
        var out: [SleepNight] = []
        for g in groups {
            guard let first = g.first, let last = g.last else { continue }
            let asleep = g.reduce(0) { $0 + $1.duration }
            guard asleep >= minAsleep else { continue }
            let mid = first.start.addingTimeInterval(last.end.timeIntervalSince(first.start) / 2)
            let minutes = calendar.component(.hour, from: mid) * 60 + calendar.component(.minute, from: mid)
            // Ночь — если середина сна между 21:00 и 11:00.
            guard minutes >= 21 * 60 || minutes < 11 * 60 else { continue }
            out.append(SleepNight(start: first.start, end: last.end, asleep: asleep))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Последняя закончившаяся ночь: пробуждение не раньше 18:00 вчерашнего дня и не позже «сейчас».
    static func lastNight(_ nights: [SleepNight], now: Date, calendar: Calendar = .habitFlow) -> SleepNight? {
        let windowStart = calendar.startOfDay(for: now).addingTimeInterval(-6 * 3_600)
        return nights
            .filter { $0.end >= windowStart && $0.end <= now.addingTimeInterval(3_600) }
            .max { $0.end < $1.end }
    }

    /// Средний сон по последним `count` ночам.
    static func average(_ nights: [SleepNight], last count: Int = 7) -> TimeInterval? {
        let recent = nights.suffix(count)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.asleep } / Double(recent.count)
    }
}

/// Один совет напарника по данным здоровья.
struct HealthTip: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case sleepDeficit, lateBedtime, hydrate, lowActivity, goodSleep
    }

    var kind: Kind
    var text: String
    /// На сколько мл поднять норму воды сегодня.
    var waterBoostML: Int = 0
    /// Во сколько лечь сегодня (минуты от полуночи).
    var suggestedBedtimeMinutes: Int? = nil

    var id: String { kind.rawValue }

    var symbol: String {
        switch kind {
        case .sleepDeficit, .lateBedtime: "moon.zzz.fill"
        case .hydrate: "drop.fill"
        case .lowActivity: "figure.walk"
        case .goodSleep: "sparkles"
        }
    }
}

struct HealthAdvice: Sendable {
    var calendar: Calendar = .habitFlow
    /// Во сколько обычно хочется ложиться (минуты от полуночи).
    var targetBedtimeMinutes = 23 * 60
    /// Сколько сна нужно (минуты).
    var sleepNeedMinutes = 450
    var strict = false

    init(calendar: Calendar = .habitFlow, targetBedtimeMinutes: Int = 23 * 60,
         sleepNeedMinutes: Int = 450, strict: Bool = false) {
        self.calendar = calendar
        self.targetBedtimeMinutes = min(max(targetBedtimeMinutes, 20 * 60), 24 * 60 - 1)
        self.sleepNeedMinutes = min(max(sleepNeedMinutes, 360), 600)
        self.strict = strict
    }

    // Пороги
    static let deficitBelow: TimeInterval = 6.5 * 3_600
    /// Меньше этого — скорее всего часы не записали ночь целиком; советовать по такому сну нельзя.
    static let incompleteBelow: TimeInterval = 2 * 3_600
    static let goodSleepFrom: TimeInterval = 7 * 3_600

    /// Интенсивная ли была тренировка.
    static func isIntense(minutes: Double?, calories: Double?) -> Bool {
        let m = minutes ?? 0
        let c = calories ?? 0
        return m >= 40 || (m >= 20 && c >= 450) || c >= 700
    }

    func tips(for h: HealthSnapshot, now: Date = .now) -> [HealthTip] {
        var out: [HealthTip] = []
        var sleepHandled = false

        if let sleep = h.sleepSeconds, sleep >= Self.incompleteBelow {
            if sleep < Self.deficitBelow {
                sleepHandled = true
                let deficitMin = max(0, sleepNeedMinutes - Int(sleep / 60))
                let shift = min(90, max(30, (deficitMin / 2 / 15) * 15))
                let bed = max(21 * 60 + 30, targetBedtimeMinutes - shift)
                let slept = Self.hm(sleep)
                let time = Self.clock(bed)
                var text = strict
                    ? "Сон — \(slept), это меньше нормы. Отбой сегодня около \(time)."
                    : "Сон — \(slept), это меньше нормы. Давай сегодня ляжем пораньше, около \(time)."
                if sleep < 4 * 3_600 {
                    text += strict ? " Если так повторяется, обсуди сон с врачом."
                                   : " Если так бывает часто, стоит обсудить сон с врачом."
                }
                out.append(HealthTip(kind: .sleepDeficit, text: text, suggestedBedtimeMinutes: bed))
            }
        }

        if Self.isIntense(minutes: h.workoutMinutes, calories: h.activeCalories) {
            let workout = h.workoutMinutes ?? 0
            let big = workout >= 75 || (h.activeCalories ?? 0) >= 900
            let boost = big ? 750 : 500
            let hasWorkout = workout >= 10
            let detail = hasWorkout ? " (\(Int(workout.rounded())) мин)" : ""
            let what = hasWorkout ? "Тренировка" : "Много движения"
            let text: String
            if strict {
                text = "\(what)\(detail). Норма воды сегодня +\(boost) мл."
            } else if hasWorkout {
                text = "Была тренировка\(detail) — добавим к норме воды ещё \(boost) мл."
            } else {
                text = "Сегодня много движения — добавим к норме воды ещё \(boost) мл."
            }
            out.append(HealthTip(kind: .hydrate, text: text, waterBoostML: boost))
        }

        let sleepIsComplete = (h.sleepSeconds ?? 0) >= Self.incompleteBelow
        if !sleepHandled, sleepIsComplete, let start = h.sleepStart {
            let minutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
            if minutes >= 60 && minutes < 5 * 60 {
                let was = Self.clock(minutes)
                let target = Self.clock(targetBedtimeMinutes)
                let text = strict
                    ? "Засыпание в \(was). Сегодня цель — \(target)."
                    : "Вчера мы уснули в \(was). Сегодня попробуем ближе к \(target)?"
                out.append(HealthTip(kind: .lateBedtime, text: text, suggestedBedtimeMinutes: targetBedtimeMinutes))
            }
        }

        if let steps = h.steps, steps < 3_000, calendar.component(.hour, from: now) >= 17 {
            let text = strict
                ? "Шагов сегодня \(Self.grouped(steps)). Нужна короткая прогулка."
                : "Сегодня всего \(Self.grouped(steps)) шагов. Может, прогуляемся минут десять?"
            out.append(HealthTip(kind: .lowActivity, text: text))
        }

        if out.isEmpty, let sleep = h.sleepSeconds, sleep >= Self.goodSleepFrom {
            let text = strict
                ? "Сон \(Self.hm(sleep)). Хороший старт."
                : "Выспались: \(Self.hm(sleep)). Отличный старт для привычек!"
            out.append(HealthTip(kind: .goodSleep, text: text))
        }
        return out
    }

    /// На сколько мл поднять норму воды (сумма по советам).
    func waterBoost(_ tips: [HealthTip]) -> Int { tips.reduce(0) { $0 + $1.waterBoostML } }

    // MARK: - Форматирование

    /// «6 ч 20 мин», «45 мин».
    static func hm(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds / 60).rounded()))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) мин" }
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }

    /// 1425 → «23:45».
    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// 12345 → «12 345» (с неразрывным пробелом).
    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
