import Foundation

// Тесты доменного слоя. Запуск без Xcode:
//   swiftc HabitFlow/Domain/*.swift Tests/DomainTests/main.swift -o domain-tests && ./domain-tests

var failures = 0
var passed = 0
func check(_ cond: @autoclosure () -> Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
    if cond() { passed += 1 } else { failures += 1; print("✗ \(name) (строка \(line))") }
}

var cal = Calendar.habitFlow
cal.timeZone = TimeZone(identifier: "UTC")!
let engine = StreakEngine(calendar: cal)
let stats = StatsEngine(calendar: cal)

func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}
func checks(_ days: [Date], value: Double = 1) -> [CheckInValue] {
    days.map { CheckInValue(date: $0, value: value) }
}

// 26.10.2026 — понедельник
let now = day(2026, 10, 26, 18)

// MARK: Ежедневная привычка

do {
    // Выполнено 20–25 и сегодня ещё нет → серия 6, сегодня не рвёт
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 15),
                          checkIns: checks((20...25).map { day(2026, 10, $0) }))
    let s = engine.buildStreak(h, now: now)
    check(s.current == 6, "ежедневно: текущая серия 6, получили \(s.current)")
    check(s.best == 6, "ежедневно: лучшая 6")
    check(!s.todayDone, "ежедневно: сегодня не выполнено")
}

do {
    // Пропуск 22-го → серия с 23 по 26 = 4, лучшая 5 (16–20)
    let ds = [16, 17, 18, 19, 20, 21, 23, 24, 25, 26].map { day(2026, 10, $0) }
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 16), checkIns: checks(ds))
    let s = engine.buildStreak(h, now: now)
    check(s.current == 4, "пропуск: текущая 4, получили \(s.current)")
    check(s.best == 6, "пропуск: лучшая 6, получили \(s.best)")
    check(s.todayDone, "пропуск: сегодня выполнено")
}

do {
    // Вчера пропущено, сегодня пусто → серия 0
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 20),
                          checkIns: checks([20, 21, 22, 23, 24].map { day(2026, 10, $0) }))
    check(engine.buildStreak(h, now: now).current == 0, "вчерашний пропуск обнуляет серию")
}

// MARK: Объём (вода)

do {
    let goal = Goal(target: 2000, unit: "мл", step: 250)
    var ins = checks([day(2026, 10, 25, 9), day(2026, 10, 25, 14)], value: 1000)
    ins += checks([day(2026, 10, 26, 9)], value: 750)
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 25), goal: goal, checkIns: ins)
    let s = engine.buildStreak(h, now: now)
    check(s.current == 1, "вода: вчера 2000 мл засчитано")
    check(abs(s.todayProgress - 0.375) < 0.001, "вода: прогресс сегодня 37,5%")
    check(engine.status(of: day(2026, 10, 26), for: h, now: now) == .pending, "вода: сегодня в процессе")
}

// MARK: Дни недели

do {
    // Пн(2), Ср(4), Пт(6). Выполнено пн 19, ср 21, пт 23. Сегодня пн 26 не выполнено → серия 3
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 19),
                          schedule: .weekdays([2, 4, 6]),
                          checkIns: checks([19, 21, 23].map { day(2026, 10, $0) }))
    let s = engine.buildStreak(h, now: now)
    check(s.current == 3, "дни недели: выходные не рвут серию, получили \(s.current)")
    check(engine.status(of: day(2026, 10, 20), for: h, now: now) == .rest, "вторник — день отдыха")
}

// MARK: N раз в неделю

do {
    // 3 раза в неделю. Неделя 12–18: 3 раза. Неделя 19–25: 3 раза. Текущая: 1 раз → серия 7
    let ds = [12, 14, 16, 19, 21, 23, 26].map { day(2026, 10, $0) }
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 12),
                          schedule: .timesPerWeek(3), checkIns: checks(ds))
    let s = engine.buildStreak(h, now: now)
    check(s.current == 7, "3/нед: серия 7, получили \(s.current)")
    check(s.weekDone == 1 && s.weekTarget == 3, "3/нед: на неделе 1 из 3")
}

do {
    // Неделя 12–18 недобрала (2 из 3) → серия считается только с 19-го
    let ds = [12, 14, 19, 21, 23].map { day(2026, 10, $0) }
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 12),
                          schedule: .timesPerWeek(3), checkIns: checks(ds))
    check(engine.buildStreak(h, now: now).current == 3, "3/нед: проваленная неделя обнуляет")
}

do {
    // Старт в субботу 17-го: неполная неделя, норма снижается до 2 дней
    let ds = [17, 18, 20, 22, 24].map { day(2026, 10, $0) }
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 17),
                          schedule: .timesPerWeek(3), checkIns: checks(ds))
    check(engine.buildStreak(h, now: now).current == 5, "3/нед: первая неполная неделя засчитана")
}

// MARK: Отказ от вредного

do {
    let h = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 1, 0))
    let q = engine.quitStreak(h, now: day(2026, 10, 11, 0))
    check(q.currentDays == 10, "отказ: 10 дней без срыва")
    check(q.relapseCount == 0 && !q.isRecordNow, "отказ: без срывов рекорд не подсвечивается")
}

do {
    // Старт 1-го, срыв 15-го, сейчас 20-е → текущая 5, рекорд 14
    let h = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 1, 0),
                          relapses: [RelapseValue(date: day(2026, 10, 15, 0), amount: 3, trigger: "Стресс")])
    let q = engine.quitStreak(h, now: day(2026, 10, 20, 0))
    check(q.currentDays == 5, "срыв: текущая 5, получили \(q.currentDays)")
    check(q.bestDays == 14, "срыв: рекорд 14 сохранён")
    check(!q.isRecordNow, "срыв: сейчас не рекорд")
    let later = engine.quitStreak(h, now: day(2026, 11, 5, 0))
    check(later.isRecordNow && later.bestDays == 21, "срыв: новый рекорд 21 день")
    check(engine.status(of: day(2026, 10, 15), for: h, now: now) == .relapse, "срыв: день срыва в календаре")
    check(engine.status(of: day(2026, 10, 16), for: h, now: now) == .clean, "срыв: чистый день")
}

do {
    // Срыв задним числом раньше старта сдвигает начало отсчёта
    let h = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 10, 0),
                          relapses: [RelapseValue(date: day(2026, 10, 5, 0), amount: 1, trigger: "")])
    let q = engine.quitStreak(h, now: day(2026, 10, 20, 0))
    check(q.currentDays == 15 && q.bestDays == 15, "срыв до старта: отсчёт от срыва")
}

// MARK: Награды

check(RewardEngine.next(after: 6)?.days == 7, "награды: следующая после 6 — неделя")
check(RewardEngine.newlyReached(from: 6, to: 7)?.days == 7, "награды: неделя получена")
check(RewardEngine.newlyReached(from: 7, to: 8) == nil, "награды: повторно не выдаётся")
check(RewardEngine.achieved(bestDays: 30).count == 6, "награды: к месяцу 6 штук")
let p = RewardEngine.progressToNext(days: 10.5)
check(p.next?.days == 14 && abs(p.progress - 0.5) < 0.001, "награды: прогресс 7→14 на 10,5 дня = 50%")

// MARK: Статистика

do {
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 17),
                          checkIns: checks([17, 18, 19, 21, 22, 23, 24, 25].map { day(2026, 10, $0) }))
    let r = stats.completionRate(h, days: 30, now: now)
    check(abs(r - 8.0 / 9.0) < 0.001, "статистика: 8 из 9 дней, получили \(r)")
    let w = stats.weeklyCounts(h, weeks: 2, now: now)
    check(w.map(\.count) == [6, 0], "статистика: по неделям \(w.map(\.count))")
}

do {
    let h = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 1, 0), relapses: [
        RelapseValue(date: day(2026, 10, 3), amount: 2, trigger: "Стресс"),
        RelapseValue(date: day(2026, 10, 9), amount: 5, trigger: "Компания"),
        RelapseValue(date: day(2026, 10, 12), amount: 1, trigger: "Стресс"),
    ])
    let t = stats.triggers(h)
    check(t.first?.trigger == "Стресс" && t.first?.count == 2, "статистика: главный триггер — стресс")
    let avoided = stats.avoidedUnits(h, baselinePerDay: 10, now: day(2026, 10, 11, 0))
    check(abs(avoided - (100 - 7)) < 0.001, "статистика: не выкурено 93, получили \(avoided)")
}

// MARK: Тексты

check(pluralDays(1) == "1 день" && pluralDays(3) == "3 дня" && pluralDays(11) == "11 дней" && pluralDays(22) == "22 дня", "склонения")
check(DurationText.compact(90061) == "1 д 1 ч", "длительность компактно")
check(DurationText.human(3 * 3600) == "3 часа", "длительность словами")

// MARK: Напарник: опыт

let comp = CompanionEngine(calendar: cal)

do {
    // Вода (ежедневно) выполнена 24, 25, 26; чтение (ежедневно) только 25 → идеальный день один (25-е)
    let water = HabitSnapshot(kind: .build, startDate: day(2026, 10, 24),
                              checkIns: checks([24, 25, 26].map { day(2026, 10, $0) }))
    let read = HabitSnapshot(kind: .build, startDate: day(2026, 10, 24),
                             checkIns: checks([25].map { day(2026, 10, $0) }))
    let x = comp.xp([water, read], now: now)
    check(x.habits == 40, "XP: 4 выполнения × 10, получили \(x.habits)")
    check(x.perfectDays == 30, "XP: один идеальный день, получили \(x.perfectDays)")
    check(x.today == 10, "XP сегодня: только вода, получили \(x.today)")
}

do {
    // Объём: две отметки по 1000 мл в один день — это одно выполнение, а не два
    let goal = Goal(target: 2000, unit: "мл", step: 250)
    let h = HabitSnapshot(kind: .build, startDate: day(2026, 10, 26), goal: goal,
                          checkIns: checks([day(2026, 10, 26, 9), day(2026, 10, 26, 15)], value: 1000))
    let x = comp.xp([h], now: now)
    check(x.habits == 10 && x.perfectDays == 30, "XP: объём засчитан один раз + идеальный день")
}

do {
    // «3 раза в неделю» не требуется каждый день для идеального дня
    let sport = HabitSnapshot(kind: .build, startDate: day(2026, 10, 20), schedule: .timesPerWeek(3),
                              checkIns: checks([day(2026, 10, 21)]))
    let water = HabitSnapshot(kind: .build, startDate: day(2026, 10, 26), checkIns: checks([day(2026, 10, 26)]))
    let x = comp.xp([sport, water], now: now)
    check(x.perfectDays == 30, "XP: идеальный день не ломается привычкой N/нед, получили \(x.perfectDays)")
}

do {
    // Отказ с 20-го 10:00. Полные сутки: 21–25 (5 дней), срыв 23-го → 4 чистых
    let h = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 20, 10),
                          relapses: [RelapseValue(date: day(2026, 10, 23, 20), amount: 1, trigger: "")])
    let x = comp.xp([h], now: now)
    check(x.cleanDays == 60, "XP: 4 чистых дня × 15, получили \(x.cleanDays)")
    check(x.today == 15, "XP сегодня: вчерашние чистые сутки")
}

do {
    // «Устоял»: 5 раз за день, засчитываются 3
    let ts = (0..<5).map { day(2026, 10, 26, 8 + $0) }
    let h = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 26, 7), resisted: ts)
    let x = comp.xp([h], now: now)
    check(x.resisted == 15, "XP: «устоял» не больше 3 раз в день")
    check(comp.resistReward(h, now: now) == 0, "XP: лимит исчерпан — награда 0")
}

// MARK: Напарник: уровни

check(XPRules.totalXP(forLevel: 1) == 0 && XPRules.totalXP(forLevel: 2) == 60 && XPRules.totalXP(forLevel: 3) == 180, "уровни: пороги")
check(XPRules.level(for: 59) == 1 && XPRules.level(for: 60) == 2 && XPRules.level(for: 600) == 5, "уровни: расчёт")
check(XPRules.level(for: 10_000_000) == XPRules.maxLevel, "уровни: потолок")
check(XPRules.stage(for: 1) == .egg && XPRules.stage(for: 2) == .baby && XPRules.stage(for: 5) == .teen && XPRules.stage(for: 10) == .adult, "стадии")
let lp = LevelProgress(xp: 120)
check(lp.level == 2 && lp.xpInLevel == 60 && lp.xpForNext == 120 && abs(lp.fraction - 0.5) < 0.001, "прогресс уровня")

// MARK: Напарник: настроение

do {
    let relapse = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 1),
                                relapses: [RelapseValue(date: day(2026, 10, 26, 10), amount: 1, trigger: "")])
    let water = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), checkIns: checks([day(2026, 10, 26)]))
    check(comp.mood([relapse, water], gapSinceLastOpen: nil, now: now) == .caring, "настроение: срыв важнее успехов")
    let idle = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), checkIns: checks([day(2026, 10, 25)]))
    check(comp.mood([idle], gapSinceLastOpen: 3 * 86_400, now: day(2026, 10, 26, 9)) == .sad, "настроение: не заходил 3 дня")
    check(comp.mood([water], gapSinceLastOpen: 3 * 86_400, now: now) == .happy, "настроение: вернулся и сделал — снова рад")
    check(comp.mood([water], gapSinceLastOpen: 3600, now: now) == .happy, "настроение: цели выполнены")
    let lazy = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1))
    check(comp.mood([lazy], gapSinceLastOpen: 3600, now: now) == .sad, "настроение: вчера пропуск, сегодня пусто после обеда")
    check(comp.mood([lazy], gapSinceLastOpen: 3600, now: day(2026, 10, 26, 9)) == .calm, "настроение: утром ещё спокоен")
    check(comp.questHabit([water, lazy], now: now) != nil, "просьба: есть невыполненная привычка")
}

// MARK: Напарник: фразы

do {
    let ctx = PhraseContext(userName: "Андрей", mood: .caring, hour: 15, today: DaySummary(due: 2, done: 0, doneAny: 0),
                            quest: nil, bestQuit: nil, level: 3, stage: .baby, strict: false)
    let line = CompanionPhrases.pick(ctx, seed: 0)
    check(line.contains("Андрей") && !line.contains("%"), "фразы: обращение по имени, без меток")
    var anon = ctx; anon.userName = ""
    let l2 = CompanionPhrases.pick(anon, seed: 0)
    check(!l2.contains(", ,") && !l2.contains("%") && !l2.contains(" !"), "фразы: без имени текст чистый")
    for m in CompanionMood.allCases {
        for hour in [3, 8, 14, 20] {
            for seed in 0..<16 {
                var c = ctx; c.mood = m; c.hour = hour; c.quest = "Вода"; c.bestQuit = ("Курение", 15)
                c.today = DaySummary(due: 3, done: 2, doneAny: 2); c.strict = seed % 2 == 0
                let t = CompanionPhrases.pick(c, seed: seed)
                if t.contains("%") || t.isEmpty { check(false, "фразы: метка не заменена: \(t)") }
            }
        }
    }
    check(true, "фразы: все комбинации без пропущенных меток")
}

// MARK: Здоровье и сон

do {
    func iv(_ sd: Int, _ sh: Int, _ ed: Int, _ eh: Int) -> SleepInterval {
        SleepInterval(start: day(2026, 10, sd, sh), end: day(2026, 10, ed, eh))
    }
    // Пересекающиеся и соседние промежутки склеиваются
    let merged = SleepMath.merge([iv(25, 23, 26, 3), iv(26, 2, 26, 6), iv(26, 7, 26, 8)])
    check(merged.count == 2, "сон: склейка пересечений, получили \(merged.count)")
    check(abs(merged[0].duration - 7 * 3600) < 1, "сон: 23:00–06:00 = 7 ч")

    // Ночное пробуждение на 30 минут не делит ночь; дневной сон не ночь
    let items = [iv(25, 23, 26, 3), iv(26, 3, 26, 3), SleepInterval(start: day(2026, 10, 26, 3).addingTimeInterval(1800), end: day(2026, 10, 26, 7)),
                 iv(26, 14, 26, 15)]
    let nights = SleepMath.nights(items, calendar: cal)
    check(nights.count == 1, "сон: одна ночь, дневной сон не считается, получили \(nights.count)")
    check(SleepMath.lastNight(nights, now: day(2026, 10, 26, 9), calendar: cal) != nil, "сон: последняя ночь найдена")
    check(SleepMath.lastNight(nights, now: day(2026, 10, 29, 9), calendar: cal) == nil, "сон: старая ночь не последняя")

    let adv = HealthAdvice(calendar: cal)
    var h = HealthSnapshot(sleepStart: day(2026, 10, 26, 1), sleepEnd: day(2026, 10, 26, 6), sleepSeconds: 5 * 3600, asOf: now)
    var tips = adv.tips(for: h, now: day(2026, 10, 26, 9))
    check(tips.contains { $0.kind == .sleepDeficit && $0.suggestedBedtimeMinutes != nil }, "здоровье: дефицит сна → лечь раньше")
    check(!tips.contains { $0.kind == .goodSleep }, "здоровье: нет похвалы при дефиците")
    check(tips.allSatisfy { !$0.text.contains("%") && !$0.text.contains("  ") }, "здоровье: тексты без меток и двойных пробелов")

    h = HealthSnapshot(sleepSeconds: 40 * 60)
    check(adv.tips(for: h, now: day(2026, 10, 26, 9)).isEmpty, "здоровье: обрывок сна не даёт советов")

    h = HealthSnapshot(sleepSeconds: 8 * 3600, workoutMinutes: 50)
    tips = adv.tips(for: h, now: day(2026, 10, 26, 18))
    check(adv.waterBoost(tips) == 500, "здоровье: тренировка → +500 мл воды")
    check(!tips.contains { $0.kind == .goodSleep }, "здоровье: похвала не дублирует другие советы")

    h = HealthSnapshot(sleepSeconds: 8 * 3600)
    check(adv.tips(for: h, now: day(2026, 10, 26, 9)).first?.kind == .goodSleep, "здоровье: хороший сон → похвала")
    check(HealthAdvice.hm(7.5 * 3600) == "7 ч 30 мин" && HealthAdvice.clock(1425) == "23:45", "здоровье: форматы времени")
    check(adv.tips(for: HealthSnapshot(), now: now).isEmpty, "здоровье: пустые данные — тишина")

    let fewSteps = HealthSnapshot(steps: 1200)
    check(adv.tips(for: fewSteps, now: day(2026, 10, 26, 10)).isEmpty, "здоровье: утром мало шагов — не ругаем")
    check(adv.tips(for: fewSteps, now: day(2026, 10, 26, 19)).first?.kind == .lowActivity, "здоровье: вечером мало шагов — подсказка")
}

// MARK: Проверка согласованности (QA)

do {
    let checker = ConsistencyChecker(calendar: cal)
    let water = HabitSnapshot(kind: .build, startDate: day(2026, 10, 20), goal: Goal(target: 2000, unit: "мл", step: 250),
                              checkIns: checks([day(2026, 10, 25, 9), day(2026, 10, 25, 14)], value: 1000), name: "Вода")
    let quit = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 10), name: "Курение")
    let clean = checker.check([water, quit], now: now)
    check(clean.isClean, "QA: чистые данные без замечаний: \(clean.summary) \(clean.issues.map(\.code))")

    // Простая отметка записана дважды за день — нестыковка (след двойного нажатия)
    var early = HabitSnapshot(kind: .build, startDate: day(2026, 10, 20), name: "Чтение")
    early.checkIns = checks([day(2026, 10, 24, 9), day(2026, 10, 24, 10)])
    check(checker.check([early], now: now).issues.contains { $0.code == "C03" }, "QA: двойная простая отметка замечена")

    // Срыв в будущем
    var future = quit
    future.relapses = [RelapseValue(date: day(2026, 11, 20), amount: 1, trigger: "")]
    check(!checker.check([future], now: now).isClean, "QA: срыв в будущем замечен")

    // Экраны показывают не то, что пересчёт
    let engineXP = CompanionEngine(calendar: cal).xp([water, quit], now: now).total
    let ok = QADisplayed(xpTotal: engineXP)
    check(checker.check([water, quit], displayed: ok, now: now).isClean, "QA: верный XP на экране — чисто")
    let bad = QADisplayed(xpTotal: engineXP + 40)
    check(checker.check([water, quit], displayed: bad, now: now).errors > 0, "QA: расхождение XP — ошибка")

    let report = checker.check([early], now: now)
    check(report.json().contains("\"issues\""), "QA: JSON-отчёт собирается")
}

// MARK: Сводка дня: единые числа

do {
    let comp = CompanionEngine(calendar: cal)
    let daily = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), checkIns: checks([day(2026, 10, 26, 9)]), name: "А")
    let weekly = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), schedule: .timesPerWeek(3), name: "Б")
    let s = comp.summary([daily, weekly], on: now)
    check(s.scheduled == 2 && s.scheduledDone == 1, "сводка: scheduled \(s.scheduled)/\(s.scheduledDone)")
    check(s.due == 1 && s.done == 1, "сводка: строгие числа отдельно")
    var archived = weekly; archived.isArchived = true
    check(comp.summary([daily, archived], on: now).scheduled >= 1, "сводка: архив не ломает расчёт")
}

// MARK: Быстрые карточки

do {
    let planner = QuickCardPlanner(calendar: cal)
    let water = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), goal: Goal(target: 2000, unit: "мл", step: 250), name: "Вода")
    let read = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), name: "Чтение")
    let quit = HabitSnapshot(kind: .quit, startDate: day(2026, 10, 10), name: "Курение")
    let deck = planner.deck([QuickHabit(id: "w", snapshot: water), QuickHabit(id: "r", snapshot: read), QuickHabit(id: "q", snapshot: quit)], now: now)
    check(deck.count == 4, "карточки: 3 привычки + настроение, получили \(deck.count)")
    check(deck.first?.kind == .resist && deck.last?.kind == .mood, "карточки: тяга первой, настроение последним")
    check(deck.allSatisfy { !$0.options.isEmpty }, "карточки: у каждой есть варианты ответа")

    let done = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), checkIns: checks([day(2026, 10, 26, 9)]), name: "Чтение")
    let deck2 = planner.deck([QuickHabit(id: "r", snapshot: done)], now: now, moodAnswered: true)
    check(deck2.isEmpty, "карточки: выполненное не спрашиваем")
    var arch = read; arch.isArchived = true
    check(planner.deck([QuickHabit(id: "r", snapshot: arch)], now: now, moodAnswered: true).isEmpty, "карточки: архив не спрашиваем")
    let many = (0..<9).map { QuickHabit(id: "h\($0)", snapshot: read) }
    check(planner.deck(many, now: now).count <= 5, "карточки: не больше пяти")

    // Время уведомления
    let none = planner.suggestedMinutes([read], now: now)
    check(none.minutes == 20 * 60 && !none.personalized, "время: мало данных → 20:00")
    var ins: [CheckInValue] = []
    for d in 15...25 { ins.append(CheckInValue(date: day(2026, 10, d, 21).addingTimeInterval(15 * 60), value: 1)) }
    let routine = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), checkIns: ins)
    let sug = planner.suggestedMinutes([routine], now: now)
    check(sug.personalized && sug.minutes == 21 * 60 - 15 + 0 || sug.minutes == 20 * 60 + 45, "время: по режиму дня \(sug.minutes)")
    check(sug.minutes % 5 == 0, "время: кратно 5 минутам")
    // Отметки задним числом (ровно 12:00) режим не определяют
    let backdated = HabitSnapshot(kind: .build, startDate: day(2026, 10, 1), checkIns: checks((15...25).map { day(2026, 10, $0, 12) }))
    check(!planner.suggestedMinutes([backdated], now: now).personalized, "время: задним числом не учитываем")
    let early = planner.suggestedMinutes([routine], bedtimeMinutes: 22 * 60, now: now)
    check(early.minutes <= 22 * 60 - 90, "время: не позже чем за 1,5 ч до сна")

    for a in [QuickAnswer.done, .added(250), .filled, .resisted, .relapse, .noUrge, .mood(1), .mood(3), .mood(5), .skipped] {
        for strict in [true, false] {
            for seed in 0..<6 {
                let t = QuickReactions.line(for: a, userName: seed % 2 == 0 ? "Андрей" : "", strict: strict, seed: seed)
                if t.isEmpty || t.contains("%") || t.contains("  ") || t.contains(" ,") { check(false, "реакция с ошибкой: «\(t)»") }
            }
        }
    }
    check(true, "реакции: чистые тексты")
    check(QuickReactions.finished(userName: "", strict: false, gainedXP: 25, seed: 0).contains("+25 XP"), "реакции: итог с XP")
}

// MARK: Разбор недели

do {
    let b = WeeklyReviewBuilder(calendar: cal)
    let good = HabitSnapshot(kind: .build, startDate: day(2026, 9, 1), checkIns: checks((20...26).map { day(2026, 10, $0, 9) }), name: "Зарядка")
    let bad = HabitSnapshot(kind: .build, startDate: day(2026, 9, 1), checkIns: checks([day(2026, 10, 20, 9)]), name: "Чтение")
    let quit = HabitSnapshot(kind: .quit, startDate: day(2026, 9, 1),
                             relapses: [RelapseValue(date: day(2026, 10, 24, 22), amount: 2, trigger: "Стресс")], name: "Курение")
    let r = b.build([good, bad, quit], now: now)
    check(r.habits.count == 3, "разбор: все привычки в разборе, получили \(r.habits.count)")
    check(r.strengths.contains { $0.contains("Зарядка") }, "разбор: сильная сторона найдена")
    check(r.dips.contains { $0.contains("Чтение") } && r.dips.contains { $0.contains("Стресс") }, "разбор: просадки и триггер")
    check(!r.microSteps.isEmpty && r.microSteps.count <= 3, "разбор: есть микро-шаги")
    let text = r.text()
    check(!text.isEmpty && !text.contains("%d") && !text.contains("  "), "разбор: офлайн-текст чистый")
    check(WeeklyReviewBuilder(calendar: cal).build([], now: now).text().contains("Пока нечего"), "разбор: пустые данные")
    var arch = good; arch.isArchived = true
    check(b.build([arch], now: now).isEmpty, "разбор: архив не входит")
}

// MARK: Промпт и ответы ИИ

do {
    let p = PersonaInput(name: "Искорка", species: "Дракончик", trait: "Смелая.", userName: "", strict: false)
    let phone = PersonaPrompt.build(p)
    check(!phone.contains("  ") && !phone.contains("%"), "промпт: нет двойных пробелов")
    check(!phone.contains("Пользователя зовут"), "промпт: без имени нет лишней фразы")
    var w = p; w.channel = .watch; w.userName = "Андрей"
    let watch = PersonaPrompt.build(w)
    check(watch.contains("120 символов") && watch.contains("Андрей"), "промпт: часы — коротко и по имени")
    var br = p; br.brainstorm = true
    check(PersonaPrompt.build(br).contains("Что скажешь?"), "промпт: мозговой штурм")

    check(ReplyPolish.clean("**Привет!**\n\n## Итог\n- пункт\n\n\n\nконец") == "Привет!\n\nИтог\n• пункт\n\nконец", "ответ: разметка убрана")
    let long = "Сегодня ты выполнил почти всё. Осталась вода. Давай закончим день красиво и спокойно, не торопясь, одним стаканом."
    let fit = ReplyPolish.watchFit(long)
    check(fit.count <= 120 && fit.hasSuffix("."), "часы: целые предложения ≤120, получили \(fit.count)")
    let oneLong = String(repeating: "слово ", count: 40)
    let cut = ReplyPolish.watchFit(oneLong)
    check(cut.count <= 120 && cut.hasSuffix("…"), "часы: длинное предложение режется по слову")
    check(ReplyPolish.watchFit("Коротко!") == "Коротко!", "часы: короткое не трогаем")
    check(ReplyPolish.ensureBrainstormEnding("Есть идея") == "Есть идея. Что скажешь?", "штурм: добавлен вопрос")
    check(ReplyPolish.ensureBrainstormEnding("Идея. Что скажешь?") == "Идея. Что скажешь?", "штурм: без дублей")
    check(ReplyPolish.ensureBrainstormEnding("Как тебе?") == "Как тебе? Что скажешь?", "штурм: после вопроса")
}

// MARK: Звуки

do {
    for e in SoundEvent.allCases {
        let buf = ToneSynth.render(ToneSynth.notes(for: e))
        check(!buf.isEmpty && buf.allSatisfy { abs($0) <= 1 }, "звук \(e.rawValue): буфер в пределах [-1, 1]")
        check(buf.first == 0 && buf.last == 0, "звук \(e.rawValue): начало и конец тихие (нет щелчка)")
    }
    let wav = WAVEncoder.encode([0, 0.5, -0.5], sampleRate: 44_100)
    check(wav.count == 44 + 6 && String(data: wav.prefix(4), encoding: .ascii) == "RIFF", "wav: заголовок и размер")

    var s = SoundSettings()
    check(SoundRules.allows(.tap, s, now: now, calendar: cal), "звук: по умолчанию включён")
    s.master = false
    check(!SoundRules.allows(.tap, s, now: now, calendar: cal), "звук: общий выключатель")
    s = SoundSettings(); s.pet = false
    check(!SoundRules.allows(.petTap, s, now: now, calendar: cal) && SoundRules.allows(.tap, s, now: now, calendar: cal), "звук: категории")
    s = SoundSettings(); s.quietMode = true
    check(SoundRules.isQuiet(s, now: day(2026, 10, 26, 23), calendar: cal), "тишина: 23:00 в тихих часах")
    check(SoundRules.isQuiet(s, now: day(2026, 10, 26, 7), calendar: cal), "тишина: 07:00 после полуночи")
    check(!SoundRules.isQuiet(s, now: day(2026, 10, 26, 12), calendar: cal), "тишина: полдень вне тихих часов")
    check(SoundRules.gain(0) == 0 && SoundRules.gain(1) <= 0.8 && SoundRules.gain(5) <= 0.8, "громкость: в пределах")

    for scene in AmbientScene.allCases {
        var g = AmbientGenerator(scene: scene)
        var buf = [Float](repeating: 0, count: 44_100)
        g.fill(&buf)
        let peak = buf.map { abs($0) }.max() ?? 0
        check(peak <= 0.9 && peak > 0.001 && buf.allSatisfy { $0.isFinite }, "фон \(scene.rawValue): конечный сигнал в пределах, пик \(peak)")
    }
    var f = FadeEnvelope()
    f.fadeIn(seconds: 1)
    var last: Float = 0
    for _ in 0..<44_100 { last = f.step(sampleRate: 44_100) }
    check(abs(last - 1) < 0.001, "fade: достиг 1")
    f.fadeOut(seconds: 0.5)
    for _ in 0..<22_100 { _ = f.step(sampleRate: 44_100) }
    check(f.isSilent, "fade: затух")

    check(HabitTheme.classify("Лечь спать до 23:00") == .sleep && HabitTheme.classify("Сон 8 часов") == .sleep, "тема: сон")
    check(HabitTheme.classify("Медитация") == .focus && HabitTheme.classify("Чтение") == .focus, "тема: концентрация")
    check(HabitTheme.classify("Персонал") == .other && HabitTheme.classify("Вода") == .other, "тема: персонал — не сон")
    check(RelaxPlanner.offer(afterCompleting: "Медитация", strict: false) != nil && RelaxPlanner.offer(afterCompleting: "Вода", strict: false) == nil, "релакс: только для фокуса и сна")
}

// MARK: Идеи

do {
    let first = IdeaBank.next(shown: [])
    check(first != nil, "идеи: есть первая")
    var shown: [String] = []
    for _ in 0..<(IdeaBank.all.count + 2) {
        if let i = IdeaBank.next(shown: shown) { shown.append(i.id) }
    }
    check(Set(shown.prefix(IdeaBank.all.count)).count == IdeaBank.all.count, "идеи: сначала все разные")
    check(IdeaBank.all.allSatisfy { IdeaBank.message($0, strict: false).hasSuffix("Что скажешь?") }, "идеи: каждое сообщение заканчивается вопросом")
    check(IdeaBank.next(shown: [], hasDeviceFeatures: false)?.needsDevice == false, "идеи: без устройства не предлагаем виджеты")
}

print(failures == 0 ? "✓ Все \(passed) проверок прошли" : "Провалено: \(failures), прошло: \(passed)")
exit(failures == 0 ? 0 : 1)
