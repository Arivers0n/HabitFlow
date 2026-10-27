import Foundation
import HealthKit
import Observation

/// Здоровье для советов напарника: сон, шаги, калории, тренировки.
///
/// Важно: приложение ставится неподписанным через ESign. Если при подписи в приложение не попало право
/// HealthKit, вызов запроса доступа к нему роняет приложение исключением, которое нельзя перехватить.
/// Поэтому перед запросом мы проверяем, есть ли право в самом исполняемом файле, и обращаемся к HealthKit
/// только по явному нажатию пользователя. Если права нет, остаётся ручной ввод сна.
@MainActor
@Observable
final class HealthService {
    static let shared = HealthService()

    enum Status: Equatable {
        /// Пользователь ещё не подключал.
        case off
        /// Подключено, данные приходят.
        case on
        /// В этой сборке нет права HealthKit (обычно из-за способа установки).
        case unavailable
    }

    private enum Key {
        static let on = "hf.health.on"
        static let manualHours = "hf.health.manualHours"
        static let manualDate = "hf.health.manualDate"
        static let bedtime = "hf.health.bedtime"
        static let need = "hf.health.need"
    }

    private(set) var status: Status
    private(set) var snapshot: HealthSnapshot?
    private(set) var loading = false

    private let store = HKHealthStore()
    private var calendar: Calendar { .habitFlow }

    private init() {
        status = UserDefaults.standard.bool(forKey: Key.on) ? .on : .off
        rebuildManual()
    }

    // MARK: - Настройки режима сна

    var bedtimeMinutes: Int {
        get { (UserDefaults.standard.object(forKey: Key.bedtime) as? Int) ?? 23 * 60 }
        set { UserDefaults.standard.set(min(max(newValue, 20 * 60), 24 * 60 - 1), forKey: Key.bedtime) }
    }

    var sleepNeedMinutes: Int {
        get { (UserDefaults.standard.object(forKey: Key.need) as? Int) ?? 450 }
        set { UserDefaults.standard.set(min(max(newValue, 360), 600), forKey: Key.need) }
    }

    // MARK: - Ручной ввод (запасной путь)

    /// Сколько человек спал сегодня ночью — если ввёл вручную сегодня.
    var manualSleepHours: Double? {
        let d = UserDefaults.standard
        guard let date = d.object(forKey: Key.manualDate) as? Date, calendar.isDateInToday(date),
              let h = d.object(forKey: Key.manualHours) as? Double, h > 0 else { return nil }
        return h
    }

    func setManualSleep(hours: Double?) {
        let d = UserDefaults.standard
        if let hours, hours > 0 {
            d.set(min(14, hours), forKey: Key.manualHours)
            d.set(Date(), forKey: Key.manualDate)
        } else {
            d.removeObject(forKey: Key.manualHours)
            d.removeObject(forKey: Key.manualDate)
        }
        rebuildManual()
    }

    private func rebuildManual() {
        guard status != .on else { return }
        if let h = manualSleepHours {
            snapshot = HealthSnapshot(sleepSeconds: h * 3_600, asOf: .now)
        } else {
            snapshot = nil
        }
    }

    // MARK: - Подключение

    static var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Есть ли в этой сборке право HealthKit. Ищем строку права в самом файле программы.
    nonisolated static func hasEntitlement() async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        await Task.detached(priority: .utility) { () -> Bool in
            guard let url = Bundle.main.executableURL,
                  let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return false }
            // Строка собирается из частей, чтобы сама программа не содержала её целиком.
            let needle = ["com.apple.developer", "healthkit"].joined(separator: ".")
            return data.range(of: Data(needle.utf8)) != nil
        }.value
        #endif
    }

    /// Подключить Здоровье. Вызывается только по нажатию пользователя.
    func connect() async {
        guard Self.isHealthDataAvailable else { status = .unavailable; return }
        guard await Self.hasEntitlement() else {
            status = .unavailable
            rebuildManual()
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: Key.on)
            status = .on
            await refresh()
        } catch {
            status = .off
        }
    }

    func disconnect() {
        UserDefaults.standard.set(false, forKey: Key.on)
        status = .off
        snapshot = nil
        rebuildManual()
    }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { set.insert(t) }
        set.insert(HKObjectType.workoutType())
        return set
    }

    // MARK: - Чтение

    func refresh(now: Date = .now) async {
        guard status == .on, !loading else { rebuildManual(); return }
        loading = true
        defer { loading = false }

        let dayStart = calendar.startOfDay(for: now)
        let weekAgo = calendar.addingDays(-8, to: dayStart)

        async let sleepRaw = readSleep(from: weekAgo, to: now)
        async let steps = readSum(.stepCount, unit: .count(), from: dayStart, to: now)
        async let energy = readSum(.activeEnergyBurned, unit: .kilocalorie(), from: dayStart, to: now)
        async let workout = readWorkoutMinutes(from: dayStart, to: now)

        let raw = await sleepRaw
        let asleepValues: Set<Int> = Set(Self.asleepValues)
        let intervals = raw.filter { asleepValues.contains($0.value) }
            .map { SleepInterval(start: $0.start, end: $0.end) }
        let nights = SleepMath.nights(intervals, calendar: calendar)
        let last = SleepMath.lastNight(nights, now: now, calendar: calendar)

        var snap = HealthSnapshot(asOf: now)
        if let last {
            snap.sleepStart = last.start
            snap.sleepEnd = last.end
            snap.sleepSeconds = last.asleep
            let window = SleepInterval(start: last.start, end: last.end)
            let deep = raw.filter { $0.value == Self.deepValue }.map { SleepInterval(start: $0.start, end: $0.end) }
            let rem = raw.filter { $0.value == Self.remValue }.map { SleepInterval(start: $0.start, end: $0.end) }
            let d = SleepMath.overlap(deep, with: window)
            let r = SleepMath.overlap(rem, with: window)
            snap.deepSeconds = d > 0 ? d : nil
            snap.remSeconds = r > 0 ? r : nil
        } else if let h = manualSleepHours {
            snap.sleepSeconds = h * 3_600
        }
        snap.sleepAverageSeconds = SleepMath.average(nights)
        snap.sleepNights = min(7, nights.count)
        let s = await steps
        snap.steps = s.map { Int($0.rounded()) }
        snap.activeCalories = await energy
        let w = await workout
        snap.workoutMinutes = (w ?? 0) > 0 ? w : nil
        snapshot = snap
    }

    /// Советы на сейчас.
    func tips(now: Date = .now) -> [HealthTip] {
        guard let snap = snapshot, snap.hasAnything else { return [] }
        let advice = HealthAdvice(calendar: calendar, targetBedtimeMinutes: bedtimeMinutes,
                                  sleepNeedMinutes: sleepNeedMinutes, strict: Appearance.shared.s.tone == .strict)
        return advice.tips(for: snap, now: now)
    }

    /// Строка о здоровье для ИИ (пусто, если данных нет).
    func promptText(now: Date = .now) -> String {
        guard let s = snapshot, s.hasAnything else { return "" }
        var parts: [String] = []
        if let sleep = s.sleepSeconds { parts.append("сон прошлой ночью \(HealthAdvice.hm(sleep))") }
        if let avg = s.sleepAverageSeconds, s.sleepNights >= 3 { parts.append("в среднем за неделю \(HealthAdvice.hm(avg))") }
        if let st = s.steps { parts.append("шагов сегодня \(HealthAdvice.grouped(st))") }
        if let w = s.workoutMinutes { parts.append("тренировка сегодня \(Int(w.rounded())) мин") }
        else if let c = s.activeCalories, c > 0 { parts.append("активных калорий сегодня \(Int(c.rounded()))") }
        return parts.isEmpty ? "" : "Здоровье: " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Запросы HealthKit

    private struct RawSleep: Sendable {
        var start: Date
        var end: Date
        var value: Int
    }

    private static var asleepValues: [Int] {
        [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
         HKCategoryValueSleepAnalysis.asleepREM.rawValue]
    }
    private static var deepValue: Int { HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
    private static var remValue: Int { HKCategoryValueSleepAnalysis.asleepREM.rawValue }

    private func readSleep(from: Date, to: Date) async -> [RawSleep] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let items = (samples as? [HKCategorySample] ?? []).map {
                    RawSleep(start: $0.startDate, end: $0.endDate, value: $0.value)
                }
                cont.resume(returning: items)
            }
            store.execute(q)
        }
    }

    private func readSum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func readWorkoutMinutes(from: Date, to: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                let seconds = (samples as? [HKWorkout] ?? []).reduce(0) { $0 + $1.duration }
                cont.resume(returning: seconds > 0 ? seconds / 60 : nil)
            }
            store.execute(q)
        }
    }
}
