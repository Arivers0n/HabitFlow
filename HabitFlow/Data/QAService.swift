import Foundation
import SwiftData

/// Проверка согласованности данных: логика (ConsistencyChecker) плюс то, что видно только в базе.
@MainActor
enum QAService {

    static func run(habits: [Habit], context: ModelContext, now: Date = .now) -> QAReport {
        let checker = ConsistencyChecker()
        let snaps = habits.map(\.snapshot)

        var displayed = QADisplayed()
        if let s = CompanionManager.shared.status(habits, now: now) {
            displayed.xpTotal = s.xp.total
            displayed.level = s.level
            displayed.stage = s.stage
            displayed.mood = s.mood
            displayed.todayScheduled = s.today.scheduled
            displayed.todayDone = s.today.scheduledDone
        }
        var report = checker.check(snaps, displayed: displayed, now: now)
        var extra: [QAIssue] = []

        // Повторяющиеся идентификаторы привычек: синхронизация склеит их в одну.
        let ids = habits.map(\.id)
        if Set(ids).count != ids.count {
            extra.append(QAIssue(code: "DB01", severity: .error, habit: nil,
                                 message: "Есть привычки с одинаковым идентификатором.",
                                 hint: "SyncEngine / BackupService.restore: при восстановлении сверять id."))
        }

        // Записи без привычки: не попадают ни в один расчёт.
        let orphanCheckIns = ((try? context.fetch(FetchDescriptor<CheckIn>())) ?? []).filter { $0.habit == nil }.count
        let orphanRelapses = ((try? context.fetch(FetchDescriptor<Relapse>())) ?? []).filter { $0.habit == nil }.count
        let orphanResists = ((try? context.fetch(FetchDescriptor<Resist>())) ?? []).filter { $0.habit == nil }.count
        let orphans = orphanCheckIns + orphanRelapses + orphanResists
        if orphans > 0 {
            extra.append(QAIssue(code: "DB02", severity: .warning, habit: nil,
                                 message: "Записей без привычки: \(orphans).",
                                 hint: "Обычно остаются после неполного удаления или синхронизации. Расчёты их не учитывают."))
        }

        // Круг резервной копии: то, что записали, должно прочитаться без потерь.
        let file = BackupService.File(exportedAt: now, habits: habits.map { BackupService.dto($0) })
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? enc.encode(file), let back = try? dec.decode(BackupService.File.self, from: data) {
            let a = file.habits.reduce(0) { $0 + $1.checkIns.count + $1.relapses.count + ($1.resists?.count ?? 0) }
            let b = back.habits.reduce(0) { $0 + $1.checkIns.count + $1.relapses.count + ($1.resists?.count ?? 0) }
            if back.habits.count != file.habits.count || a != b {
                extra.append(QAIssue(code: "DB03", severity: .error, habit: nil,
                                     message: "Резервная копия читается не полностью.",
                                     hint: "BackupService: проверить Codable-модели и формат дат."))
            }
        } else {
            extra.append(QAIssue(code: "DB03", severity: .error, habit: nil,
                                 message: "Резервную копию не удалось записать и прочитать.",
                                 hint: "BackupService: проверить Codable-модели."))
        }

        if !extra.isEmpty {
            report.issues = (report.issues + extra).sorted { a, b in
                a.severity != b.severity ? a.severity > b.severity : (a.code != b.code ? a.code < b.code : a.message < b.message)
            }
        }
        return report
    }
}
