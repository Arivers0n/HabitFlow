import SwiftUI
import SwiftData
import Observation

/// Скрытый режим проверки интерфейса на худших данных: длинные названия, огромные числа,
/// сотни отметок и срывов. Отдельная база в памяти — настоящие данные не трогаются и не синхронизируются.
@MainActor
@Observable
final class TestMode {
    static let shared = TestMode()

    struct Session {
        let container: ModelContainer
        let store: HabitStore
    }

    private(set) var data: Session?

    private init() {}

    /// Сценарии: stress — худшие данные; egg — напарник ещё в яйце (для снимков экрана в CI).
    func enter(scenario: String = "stress") {
        let schema = Schema([Habit.self, CheckIn.self, Relapse.self, Resist.self])
        guard let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)) else { return }
        let store = HabitStore(context: c.mainContext, isTest: true)
        if scenario == "egg" { Self.seedEgg(c.mainContext) } else { Self.seed(c.mainContext) }
        // В тестовых данных не показываем поздравления — они закрывают экран.
        for h in (try? c.mainContext.fetch(FetchDescriptor<Habit>())) ?? [] { h.celebratedDays = 100_000 }
        try? c.mainContext.save()
        data = Session(container: c, store: store)
        AppRouter.shared.tab = .today
        Haptics.success()
    }

    func exit() {
        data = nil
        AppRouter.shared.tab = .settings
        Haptics.tap()
    }

    /// Одна привычка, отмеченная сегодня: 40 XP — яйцо уже с первой трещиной.
    private static func seedEgg(_ ctx: ModelContext) {
        let h = Habit(name: "Вода", kind: .build)
        h.symbol = "drop.fill"
        h.colorHex = "5AC8FA"
        h.goalTarget = 2000; h.goalUnit = "мл"; h.goalStep = 250
        ctx.insert(h)
        let c = CheckIn(date: .now, value: 2000)
        ctx.insert(c); c.habit = h
        let q = Habit(name: "Курение", kind: .quit)
        q.symbol = "smoke.fill"; q.colorHex = "FF453A"; q.unitName = "сигарет"
        q.startDate = Date.now.addingTimeInterval(-3 * 3600)
        ctx.insert(q)
        try? ctx.save()
    }

    /// Снимки экрана в CI: `-hfShot egg|stress` при запуске.
    static func applyLaunchScenario() {
        guard let scenario = UserDefaults.standard.string(forKey: "hfShot"), !scenario.isEmpty else { return }
        let mgr = CompanionManager.shared
        let forced = UserDefaults.standard.string(forKey: "hfShotCharacter")
        if mgr.state.characterID == nil || forced != nil {
            mgr.state.characterID = forced ?? "dragon"
            mgr.state.nickname = mgr.character?.name ?? ""
            mgr.state.userName = "Андрей"
            mgr.state.onboardingDone = true
            mgr.state.treats = 3
            mgr.state.lastSeenLevel = 50
        }
        UserDefaults.standard.set(true, forKey: "hf.welcomeDone")
        shared.enter(scenario: scenario)
    }

    private static func seed(_ ctx: ModelContext) {
        let cal = Calendar.habitFlow
        let now = Date.now
        func habit(_ name: String, _ kind: HabitKind, _ symbol: String, _ hex: String, order: Int) -> Habit {
            let h = Habit(name: name, kind: kind)
            h.symbol = symbol
            h.colorHex = hex
            h.sortOrder = order
            h.startDate = cal.date(byAdding: .day, value: -400, to: now) ?? now
            ctx.insert(h)
            return h
        }
        // 1. Очень длинное название и длинная серия
        let a = habit("Медитация осознанности перед сном с дыхательной практикой и дневником благодарности", .build,
                      "brain.head.profile", "9B6BFF", order: 0)
        for d in 0..<380 {
            let c = CheckIn(date: cal.date(byAdding: .day, value: -d, to: now)!, value: 1)
            ctx.insert(c); c.habit = a
        }
        // 2. Огромная объёмная цель
        let b = habit("Вода", .build, "drop.fill", "5AC8FA", order: 1)
        b.goalTarget = 99_999; b.goalUnit = "мл"; b.goalStep = 12_345
        let c1 = CheckIn(date: now, value: 54_321); ctx.insert(c1); c1.habit = b
        // 3. N раз в неделю без отметок
        let c = habit("Спорт", .build, "figure.run", "3DDC97", order: 2)
        c.scheduleType = "perWeek"; c.timesPerWeek = 7
        // 4. Дни недели, пустое расписание сегодня
        let d = habit("Английский", .build, "character.book.closed.fill", "4C8DFF", order: 3)
        d.scheduleType = "weekdays"; d.weekdaysMask = Habit.mask(fromDays: [1])
        // 5. Отказ с сотнями срывов
        let e = habit("Курение очень длинное название чтобы проверить перенос строки", .quit, "smoke.fill", "FF453A", order: 4)
        e.unitName = "сигарет"; e.baselinePerDay = 40; e.costPerUnit = 999
        let triggers = ["Стресс", "Компания", "Скука", "Очень длинная причина срыва, которую ввели вручную", ""]
        for i in 0..<300 {
            let r = Relapse(date: cal.date(byAdding: .hour, value: -i * 30, to: now)!, amount: Double(i % 25 + 1),
                            trigger: triggers[i % triggers.count], note: i % 7 == 0 ? String(repeating: "Заметка ", count: 30) : "")
            ctx.insert(r); r.habit = e
        }
        // 6. Отказ только что начат
        let f = habit("Сладкое", .quit, "birthday.cake.fill", "FF9F0A", order: 5)
        f.startDate = now.addingTimeInterval(-42)
        // 7. Много привычек
        for i in 0..<14 {
            _ = habit("Привычка \(i + 1)", .build, SymbolCatalog.build[i % SymbolCatalog.build.count],
                      Palette.build[i % Palette.build.count], order: 6 + i)
        }
        try? ctx.save()
    }
}

struct TestModeBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flask.fill")
            Text("Тестовые данные — ничего не сохраняется").font(.footnote.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Button("Выйти") { TestMode.shared.exit() }
                .font(.footnote.weight(.bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(Color(hex: "FFD60A"))
    }
}
