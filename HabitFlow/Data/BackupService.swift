import Foundation
import SwiftData

/// Резервная копия всех привычек в JSON. Импорт добавляет то, чего ещё нет (сверка по id),
/// поэтому повторный импорт того же файла ничего не дублирует.
@MainActor
enum BackupService {
    struct File: Codable {
        var app = "HabitFlow"
        var version = 1
        var exportedAt: Date
        var habits: [HabitDTO]
        /// Дизайны виджетов. Необязательное поле: копии без него читаются как раньше.
        var widgets: WidgetConfigSet?
    }

    struct HabitDTO: Codable {
        var id: UUID
        var name: String
        var kind: String
        var symbol: String
        var colorHex: String
        var note: String
        var createdAt: Date
        var startDate: Date
        var sortOrder: Int
        var isArchived: Bool
        var scheduleType: String
        var timesPerWeek: Int
        var weekdaysMask: Int
        var goalTarget: Double
        var goalUnit: String
        var goalStep: Double
        var unitName: String
        var baselinePerDay: Double
        var costPerUnit: Double
        var reminderOn: Bool
        var reminderMinutes: Int
        var celebratedDays: Int
        var checkIns: [CheckInDTO]
        var relapses: [RelapseDTO]
        var resists: [Date]?
        var shareMode: Int?
    }

    struct CheckInDTO: Codable { var date: Date; var value: Double }
    struct RelapseDTO: Codable { var date: Date; var amount: Double; var trigger: String; var note: String }

    static func dto(_ h: Habit) -> HabitDTO {
        HabitDTO(id: h.id, name: h.name, kind: h.kindRaw, symbol: h.symbol, colorHex: h.colorHex,
                 note: h.note, createdAt: h.createdAt, startDate: h.startDate, sortOrder: h.sortOrder,
                 isArchived: h.isArchived, scheduleType: h.scheduleType, timesPerWeek: h.timesPerWeek,
                 weekdaysMask: h.weekdaysMask, goalTarget: h.goalTarget, goalUnit: h.goalUnit,
                 goalStep: h.goalStep, unitName: h.unitName, baselinePerDay: h.baselinePerDay,
                 costPerUnit: h.costPerUnit, reminderOn: h.reminderOn, reminderMinutes: h.reminderMinutes,
                 celebratedDays: h.celebratedDays,
                 checkIns: h.checkIns.map { CheckInDTO(date: $0.date, value: $0.value) },
                 relapses: h.relapses.map { RelapseDTO(date: $0.date, amount: $0.amount, trigger: $0.trigger, note: $0.note) },
                 resists: h.resists.map(\.date),
                 shareMode: h.shareMode)
    }

    static func export(_ habits: [Habit]) throws -> URL {
        var file = File(exportedAt: .now, habits: habits.map { dto($0) })
        if WidgetStore.shared.isCustomized { file.widgets = WidgetStore.shared.configs }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(file)

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HabitFlow-\(f.string(from: .now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Создаёт привычку со всей историей. `ids` — исходные id записей (для отмены удаления),
    /// без них записи получают новые id.
    @discardableResult
    static func restore(_ d: HabitDTO, ids: ([UUID], [UUID], [UUID])? = nil, into context: ModelContext) -> Habit {
        let h = Habit(name: d.name, kind: HabitKind(rawValue: d.kind) ?? .build)
        h.id = d.id
        h.symbol = d.symbol
        h.colorHex = d.colorHex
        h.note = d.note
        h.createdAt = d.createdAt
        h.startDate = d.startDate
        h.sortOrder = d.sortOrder
        h.isArchived = d.isArchived
        h.scheduleType = d.scheduleType
        h.timesPerWeek = d.timesPerWeek
        h.weekdaysMask = d.weekdaysMask
        h.goalTarget = d.goalTarget
        h.goalUnit = d.goalUnit
        h.goalStep = d.goalStep
        h.unitName = d.unitName
        h.baselinePerDay = d.baselinePerDay
        h.costPerUnit = d.costPerUnit
        h.reminderOn = d.reminderOn
        h.reminderMinutes = d.reminderMinutes
        h.celebratedDays = d.celebratedDays
        h.shareMode = d.shareMode ?? 0
        h.touch()
        context.insert(h)
        for (i, c) in d.checkIns.enumerated() {
            let ci = CheckIn(date: c.date, value: c.value)
            if let ids, i < ids.0.count { ci.id = ids.0[i] }
            context.insert(ci)
            ci.habit = h
        }
        for (i, r) in d.relapses.enumerated() {
            let rel = Relapse(date: r.date, amount: r.amount, trigger: r.trigger, note: r.note)
            if let ids, i < ids.1.count { rel.id = ids.1[i] }
            context.insert(rel)
            rel.habit = h
        }
        for (i, date) in (d.resists ?? []).enumerated() {
            let rs = Resist(date: date)
            if let ids, i < ids.2.count { rs.id = ids.2[i] }
            context.insert(rs)
            rs.habit = h
        }
        return h
    }

    /// Возвращает число добавленных привычек.
    static func importFile(_ url: URL, into context: ModelContext) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let file = try dec.decode(File.self, from: data)

        let existing = Set(((try? context.fetch(FetchDescriptor<Habit>())) ?? []).map(\.id))
        var added = 0
        for d in file.habits where !existing.contains(d.id) {
            let h = restore(d, into: context)
            NotificationService.sync(h)
            added += 1
        }
        // Дизайны виджетов из копии ставим, только если на этом устройстве их ещё не меняли.
        if let w = file.widgets, !WidgetStore.shared.isCustomized { WidgetStore.shared.replaceAll(w) }
        try context.save()
        SyncEngine.shared.schedulePush()
        return added
    }
}
