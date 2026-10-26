import Foundation

/// Русские формы слов: 1 день, 2 дня, 5 дней.
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let a = abs(n) % 100
    let b = a % 10
    if a > 10 && a < 20 { return many }
    if b == 1 { return one }
    if b >= 2 && b <= 4 { return few }
    return many
}

func pluralDays(_ n: Int) -> String { "\(n) \(plural(n, "день", "дня", "дней"))" }

enum DurationText {
    /// Компактно: «12 д 4 ч», «4 ч 31 м», «31 м 12 с».
    static func compact(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60, sec = s % 60
        if d > 0 { return "\(d) д \(h) ч" }
        if h > 0 { return "\(h) ч \(m) м" }
        return "\(m) м \(sec) с"
    }

    /// Для рекорда: «23 дня», «5 ч», «12 мин».
    static func human(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86_400
        if d > 0 { return pluralDays(d) }
        let h = s / 3_600
        if h > 0 { return "\(h) \(plural(h, "час", "часа", "часов"))" }
        let m = s / 60
        return "\(m) мин"
    }

    /// Части для крупного счётчика: дни, часы, минуты, секунды.
    static func parts(_ seconds: TimeInterval) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let s = max(0, Int(seconds))
        return (s / 86_400, (s % 86_400) / 3_600, (s % 3_600) / 60, s % 60)
    }
}

enum NumberText {
    /// 2000 → «2 000», 1.5 → «1,5».
    static func value(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.rounded() == v ? 0 : 1
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}
