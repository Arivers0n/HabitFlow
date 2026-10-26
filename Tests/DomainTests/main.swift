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

print(failures == 0 ? "✓ Все \(passed) проверок прошли" : "Провалено: \(failures), прошло: \(passed)")
exit(failures == 0 ? 0 : 1)
