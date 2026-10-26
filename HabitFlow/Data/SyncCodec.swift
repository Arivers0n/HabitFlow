import Foundation
import SwiftData

/// Перевод записей в документы сервера и обратно.
@MainActor
enum SyncCodec {

    // MARK: - В документ

    static func habit(_ h: Habit) -> [String: Any] {
        [
            "name": h.name, "kind": h.kindRaw, "symbol": h.symbol, "colorHex": h.colorHex, "note": h.note,
            "createdAt": h.createdAt.timeIntervalSince1970, "startDate": h.startDate.timeIntervalSince1970,
            "sortOrder": h.sortOrder, "isArchived": h.isArchived,
            "scheduleType": h.scheduleType, "timesPerWeek": h.timesPerWeek, "weekdaysMask": h.weekdaysMask,
            "goalTarget": h.goalTarget, "goalUnit": h.goalUnit, "goalStep": h.goalStep,
            "unitName": h.unitName, "baselinePerDay": h.baselinePerDay, "costPerUnit": h.costPerUnit,
            "reminderOn": h.reminderOn, "reminderMinutes": h.reminderMinutes,
            "celebratedDays": h.celebratedDays, "shareMode": h.shareMode,
        ]
    }

    static func checkIn(_ c: CheckIn) -> [String: Any]? {
        guard let h = c.habit else { return nil }
        return ["habit": h.id.uuidString, "date": c.date.timeIntervalSince1970, "value": c.value]
    }

    static func relapse(_ r: Relapse) -> [String: Any]? {
        guard let h = r.habit else { return nil }
        return ["habit": h.id.uuidString, "date": r.date.timeIntervalSince1970, "amount": r.amount,
                "trigger": r.trigger, "note": r.note]
    }

    static func resist(_ r: Resist) -> [String: Any]? {
        guard let h = r.habit else { return nil }
        return ["habit": h.id.uuidString, "date": r.date.timeIntervalSince1970]
    }

    // MARK: - Из документов

    static func apply(_ docs: [[String: Any]], ctx: ModelContext) {
        // Привычки и настройки раньше отметок: отметке нужна её привычка.
        let order = ["habit": 0, "prefs": 0]
        let sorted = docs.sorted { (order[jStr($0["kind"])] ?? 1) < (order[jStr($1["kind"])] ?? 1) }
        var habitsByID = Dictionary(((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).map { ($0.id, $0) },
                                    uniquingKeysWith: { a, _ in a })
        var orphans: [[String: Any]] = []
        var touchedHabits = Set<UUID>()

        for d in sorted {
            let kind = jStr(d["kind"])
            let cid = jStr(d["cid"])
            let cts = jNum(d["cts"])
            let deleted = jBool(d["deleted"])
            let data = d["data"] as? [String: Any] ?? [:]

            if kind == "prefs" {
                if !deleted { PrefSync.applyRemote(cid: cid, data: data, cts: cts) }
                continue
            }
            guard let id = UUID(uuidString: cid) else { continue }
            // Удалили здесь, но ещё не отправили — не воскрешаем.
            if Tombstones.contains(cid) && !deleted { continue }

            switch kind {
            case "habit":
                let local = habitsByID[id]
                if let local, shouldSkip(local, cts: cts) { continue }
                if deleted {
                    if let local {
                        NotificationService.cancel(local.id)
                        ctx.delete(local)
                        habitsByID[id] = nil
                    }
                    continue
                }
                let h = local ?? {
                    let n = Habit()
                    n.id = id
                    ctx.insert(n)
                    habitsByID[id] = n
                    return n
                }()
                fill(h, data)
                stamp(h, cts)
                touchedHabits.insert(id)

            case "checkin", "relapse", "resist":
                if deleted {
                    deleteChild(kind: kind, id: id, cts: cts, ctx: ctx)
                    continue
                }
                guard let hid = UUID(uuidString: jStr(data["habit"])) else { continue }
                guard let habit = habitsByID[hid] else {
                    if !Tombstones.contains(hid.uuidString) { orphans.append(d) }
                    continue
                }
                upsertChild(kind: kind, id: id, data: data, cts: cts, habit: habit, ctx: ctx)

            default:
                continue
            }
        }
        for id in touchedHabits {
            if let h = habitsByID[id] { NotificationService.sync(h) }
        }
        if !orphans.isEmpty { Orphans.add(orphans) }
    }

    static func retryOrphans(ctx: ModelContext) {
        let list = Orphans.take()
        guard !list.isEmpty else { return }
        let habits = Set(((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).map { $0.id.uuidString })
        // Те, чья привычка так и не пришла, ждут дальше (но не вечно — до 2000 штук).
        let ready = list.filter { habits.contains(jStr(($0["data"] as? [String: Any])?["habit"])) }
        let waiting = list.filter { !habits.contains(jStr(($0["data"] as? [String: Any])?["habit"])) }
        apply(ready, ctx: ctx)
        Orphans.add(Array(waiting.suffix(2000)))
    }

    // MARK: - Помощники

    /// Локальная правка свежее серверной или это эхо нашей же отправки.
    private static func shouldSkip(_ m: any SyncStamped, cts: Double) -> Bool {
        let local = m.updatedAt.timeIntervalSince1970 * 1000
        if m.dirty && local > cts { return true }
        if !m.dirty && abs(local - cts) < 1 { return true }
        return false
    }

    private static func stamp(_ m: any SyncStamped, _ cts: Double) {
        m.updatedAt = Date(timeIntervalSince1970: cts / 1000)
        m.dirty = false
    }

    private static func fill(_ h: Habit, _ d: [String: Any]) {
        h.name = jStr(d["name"])
        h.kindRaw = jStr(d["kind"]).isEmpty ? HabitKind.build.rawValue : jStr(d["kind"])
        if !jStr(d["symbol"]).isEmpty { h.symbol = jStr(d["symbol"]) }
        if !jStr(d["colorHex"]).isEmpty { h.colorHex = jStr(d["colorHex"]) }
        h.note = jStr(d["note"])
        if let v = jDate(d["createdAt"]) { h.createdAt = v }
        if let v = jDate(d["startDate"]) { h.startDate = v }
        h.sortOrder = jInt(d["sortOrder"])
        h.isArchived = jBool(d["isArchived"])
        h.scheduleType = jStr(d["scheduleType"]).isEmpty ? "daily" : jStr(d["scheduleType"])
        h.timesPerWeek = max(1, min(7, jInt(d["timesPerWeek"])))
        h.weekdaysMask = jInt(d["weekdaysMask"]) == 0 ? 0b111_1111 : jInt(d["weekdaysMask"])
        h.goalTarget = max(0.0001, jNum(d["goalTarget"]))
        h.goalUnit = jStr(d["goalUnit"])
        h.goalStep = max(0.0001, jNum(d["goalStep"]))
        h.unitName = jStr(d["unitName"])
        h.baselinePerDay = max(0, jNum(d["baselinePerDay"]))
        h.costPerUnit = max(0, jNum(d["costPerUnit"]))
        h.reminderOn = jBool(d["reminderOn"])
        h.reminderMinutes = jInt(d["reminderMinutes"])
        h.celebratedDays = max(h.celebratedDays, jInt(d["celebratedDays"]))
        h.shareMode = jInt(d["shareMode"])
    }

    private static func upsertChild(kind: String, id: UUID, data: [String: Any], cts: Double, habit: Habit, ctx: ModelContext) {
        let date = jDate(data["date"]) ?? .now
        switch kind {
        case "checkin":
            let found = try? ctx.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == id })).first
            if let found, shouldSkip(found, cts: cts) { return }
            let c = found ?? { let n = CheckIn(date: date, value: 1); n.id = id; ctx.insert(n); return n }()
            c.date = date
            c.value = jNum(data["value"])
            if c.habit?.id != habit.id { c.habit = habit }
            stamp(c, cts)
        case "relapse":
            let found = try? ctx.fetch(FetchDescriptor<Relapse>(predicate: #Predicate { $0.id == id })).first
            if let found, shouldSkip(found, cts: cts) { return }
            let r = found ?? { let n = Relapse(date: date, amount: 1, trigger: "", note: ""); n.id = id; ctx.insert(n); return n }()
            r.date = date
            r.amount = jNum(data["amount"])
            r.trigger = jStr(data["trigger"])
            r.note = jStr(data["note"])
            if r.habit?.id != habit.id { r.habit = habit }
            stamp(r, cts)
        default:
            let found = try? ctx.fetch(FetchDescriptor<Resist>(predicate: #Predicate { $0.id == id })).first
            if let found, shouldSkip(found, cts: cts) { return }
            let r = found ?? { let n = Resist(date: date); n.id = id; ctx.insert(n); return n }()
            r.date = date
            if r.habit?.id != habit.id { r.habit = habit }
            stamp(r, cts)
        }
    }

    private static func deleteChild(kind: String, id: UUID, cts: Double, ctx: ModelContext) {
        switch kind {
        case "checkin":
            if let m = try? ctx.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == id })).first,
               !shouldSkip(m, cts: cts) { ctx.delete(m) }
        case "relapse":
            if let m = try? ctx.fetch(FetchDescriptor<Relapse>(predicate: #Predicate { $0.id == id })).first,
               !shouldSkip(m, cts: cts) { ctx.delete(m) }
        default:
            if let m = try? ctx.fetch(FetchDescriptor<Resist>(predicate: #Predicate { $0.id == id })).first,
               !shouldSkip(m, cts: cts) { ctx.delete(m) }
        }
    }
}

/// Отметки, пришедшие раньше своей привычки.
@MainActor
enum Orphans {
    private static let key = "hf.orphans"

    static func add(_ docs: [[String: Any]]) {
        guard !docs.isEmpty else { return }
        var list = load()
        list.append(contentsOf: docs)
        save(Array(list.suffix(2000)))
    }

    static func take() -> [[String: Any]] {
        let list = load()
        UserDefaults.standard.removeObject(forKey: key)
        return list
    }

    private static func load() -> [[String: Any]] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return arr
    }

    private static func save(_ list: [[String: Any]]) {
        if let d = try? JSONSerialization.data(withJSONObject: list) { UserDefaults.standard.set(d, forKey: key) }
    }
}
