import Foundation
import Observation

/// ИИ-функции HabitFlow: чат с напарником, привычки из текста, разбор недели и срыва.
@MainActor
enum AICoach {

    // MARK: - Контекст

    /// Короткая сводка о привычках для ИИ. Только то, что нужно для совета.
    static func context(_ habits: [Habit], now: Date = .now) -> String {
        let engine = StreakEngine()
        let stats = StatsEngine()
        let cal = Calendar.habitFlow
        var lines: [String] = []
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM, HH:mm"
        lines.append("Сейчас: \(f.string(from: now)).")

        let active = habits.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        if active.isEmpty { lines.append("Привычек пока нет.") }
        for h in active.prefix(25) {
            let snap = h.snapshot
            if h.kind == .build {
                let s = engine.buildStreak(snap, now: now)
                let rate = Int((stats.completionRate(snap, days: 14, now: now) * 100).rounded())
                var t = "• Полезная «\(h.name)» (\(h.scheduleText)): серия \(s.current), рекорд \(s.best), выполнение за 2 недели \(rate)%"
                t += s.todayDone ? ", сегодня сделано" : (s.isScheduledToday ? ", сегодня ещё нет" : ", сегодня по плану отдых")
                if !h.goal.isBinary { t += " (сегодня \(NumberText.value(s.todayValue)) из \(NumberText.value(h.goal.target)) \(h.goal.unit))" }
                lines.append(t)
            } else {
                let q = engine.quitStreak(snap, now: now)
                var t = "• Отказ от «\(h.name)»: без срыва \(DurationText.human(q.current)), рекорд \(DurationText.human(q.best)), срывов всего \(q.relapseCount)"
                let recent = h.relapses.filter { now.timeIntervalSince($0.date) < 21 * 86_400 }.sorted { $0.date > $1.date }
                if !recent.isEmpty {
                    let items = recent.prefix(5).map { r -> String in
                        let d = cal.isDateInToday(r.date) ? "сегодня" : r.date.formatted(.dateTime.day().month().locale(Locale(identifier: "ru_RU")))
                        var s = "\(d): \(NumberText.value(r.amount)) \(h.unitName.isEmpty ? "раз" : h.unitName)"
                        if !r.trigger.isEmpty { s += ", причина «\(r.trigger)»" }
                        if !r.note.isEmpty { s += ", заметка: \(r.note.prefix(120))" }
                        return s
                    }
                    t += ". Недавние срывы: " + items.joined(separator: "; ")
                }
                let resisted = h.resists.filter { now.timeIntervalSince($0.date) < 7 * 86_400 }.count
                if resisted > 0 { t += ". За неделю устоял перед искушением \(resisted) раз" }
                lines.append(t)
            }
        }
        if let s = CompanionManager.shared.status(habits, now: now) {
            let treats = CompanionManager.shared.state.treats
            lines.append("Напарник: уровень \(s.level), опыт \(s.xp.total), настроение «\(s.mood.title)», угощений \(treats).")
            if s.today.scheduled > 0 {
                lines.append("Целей на сегодня: \(s.today.scheduledDone) из \(s.today.scheduled).")
            }
        }
        if let avg = MoodLog.shared.average(now: now) {
            lines.append("Настроение по быстрым карточкам за неделю: в среднем \(String(format: "%.1f", avg)) из 5.")
        }
        let health = HealthService.shared.promptText(now: now)
        if !health.isEmpty { lines.append(health) }
        // Если данные расходятся сами с собой, напарник может честно сказать разработчику.
        let report = ConsistencyChecker().check(habits.map(\.snapshot), now: now)
        let problems = report.promptText(limit: 4)
        if !problems.isEmpty { lines.append("Замечания проверки данных:\n" + problems) }
        return lines.joined(separator: "\n")
    }

    /// Роль напарника для ИИ. Для часов ответ короткий (1–2 предложения).
    static func persona(channel: AIChannel = .phone, brainstorm: Bool = false) -> String {
        let mgr = CompanionManager.shared
        let input = PersonaInput(name: mgr.displayName.isEmpty ? "Напарник" : mgr.displayName,
                                 species: mgr.character?.species,
                                 trait: mgr.character?.trait,
                                 userName: mgr.state.userName,
                                 strict: Appearance.shared.s.tone == .strict,
                                 channel: channel,
                                 brainstorm: brainstorm)
        return PersonaPrompt.build(input)
    }

    // MARK: - Привычки из текста

    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        var draft: HabitDraft
        var why: String
        var selected = true
    }

    static func habits(from text: String) async throws -> [Suggestion] {
        let buildSymbols = SymbolCatalog.build.joined(separator: ", ")
        let quitSymbols = SymbolCatalog.quit.joined(separator: ", ")
        let prompt = """
        Человек описал, какие привычки хочет завести или от каких отказаться:
        «\(text.prefix(1500))»

        Составь из этого список привычек для трекера. Верни ТОЛЬКО JSON-массив без пояснений. Каждый элемент:
        {"name": "короткое название, 1–3 слова", "kind": "build" или "quit",
         "symbol": одно из полезных [\(buildSymbols)] или вредных [\(quitSymbols)],
         "schedule": "daily" | "perWeek" | "weekdays", "timesPerWeek": 1–7, "weekdays": [номера: 1 — вс, 2 — пн … 7 — сб],
         "volume": true, если цель в количестве (вода, страницы, минуты, шаги), "target": число в день, "unit": "мл" | "мин" | "стр" | "шагов" | "км" | "раз",
         "step": шаг кнопки «+», "unitName": для вредной — в чём считать срыв ("сигарет", "порций", "бокалов"),
         "baselinePerDay": сколько обычно в день для вредной (0, если не сказано), "costPerUnit": цена единицы в рублях (0, если не сказано),
         "why": одно короткое предложение, зачем эта привычка}
        Если человек сказал «бросить» или «меньше» — это quit. Разумные цели: вода 1500–2500 мл с шагом 250, чтение 10–30 стр, медитация 5–15 мин.
        Не больше 6 привычек.
        """
        let raw = try await json(prompt)
        guard let arr = raw as? [[String: Any]] else { throw AIError.badReply }
        var out: [Suggestion] = []
        for item in arr.prefix(6) {
            let name = jStr(item["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            var d = HabitDraft()
            d.name = String(name.prefix(40))
            d.kind = jStr(item["kind"]) == "quit" ? .quit : .build
            let symbols = SymbolCatalog.symbols(for: d.kind)
            let sym = jStr(item["symbol"])
            d.symbol = symbols.contains(sym) ? sym : symbols[0]
            let palette = Palette.colors(for: d.kind)
            d.colorHex = palette[out.count % palette.count]
            d.note = jStr(item["why"])
            if d.kind == .build {
                switch jStr(item["schedule"]) {
                case "perWeek":
                    d.scheduleType = "perWeek"
                    d.timesPerWeek = max(1, min(7, jInt(item["timesPerWeek"]) == 0 ? 3 : jInt(item["timesPerWeek"])))
                case "weekdays":
                    let days = Set((item["weekdays"] as? [Any] ?? []).map { jInt($0) }.filter { (1...7).contains($0) })
                    if !days.isEmpty { d.scheduleType = "weekdays"; d.weekdays = days }
                default:
                    d.scheduleType = "daily"
                }
                if jBool(item["volume"]), jNum(item["target"]) > 0 {
                    d.isVolume = true
                    d.goalTarget = min(100_000, jNum(item["target"]))
                    let unit = jStr(item["unit"]).trimmingCharacters(in: .whitespaces)
                    d.goalUnit = unit.isEmpty ? "раз" : String(unit.prefix(10))
                    let step = jNum(item["step"])
                    d.goalStep = step > 0 && step <= d.goalTarget ? step : max(1, (d.goalTarget / 4).rounded())
                }
            } else {
                d.unitName = String(jStr(item["unitName"]).prefix(16))
                d.baselinePerDay = max(0, min(1000, jNum(item["baselinePerDay"])))
                d.costPerUnit = max(0, min(100_000, jNum(item["costPerUnit"])))
            }
            out.append(Suggestion(draft: d, why: jStr(item["why"])))
        }
        guard !out.isEmpty else { throw AIError.badReply }
        return out
    }

    private static func json(_ prompt: String) async throws -> Any {
        try await AI.json(prompt, system: "Ты помогаешь настраивать трекер привычек. Отвечай только валидным JSON.")
    }

    // MARK: - Разбор недели

    static func weekKey(_ now: Date = .now) -> String {
        let cal = Calendar.habitFlow
        let ws = cal.startOfWeek(now)
        return "hf.review.\(Int(ws.timeIntervalSince1970))"
    }

    static var cachedReview: String? {
        UserDefaults.standard.string(forKey: weekKey())
    }

    /// Разбор недели по истории: работает без сети и без ИИ.
    static func offlineReview(_ habits: [Habit], now: Date = .now) -> WeeklyReview {
        let sleep = HealthService.shared.snapshot?.sleepAverageSeconds
        return WeeklyReviewBuilder().build(habits.map(\.snapshot), sleepAverage: sleep, now: now)
    }

    /// Разбор недели: факты считаем сами, ИИ лишь складывает их в живой текст. Нет ИИ или сети — показываем расчёт.
    static func weeklyReview(_ habits: [Habit]) async throws -> String {
        let review = offlineReview(habits)
        let strict = Appearance.shared.s.tone == .strict
        let fallback = review.text(strict: strict)
        guard !review.isEmpty, AI.available else { return fallback }

        let prompt = """
        Данные о привычках:
        \(context(habits))

        Посчитанные факты недели (опирайся на них, ничего не добавляй от себя):
        \(review.promptFacts)

        Сделай короткий разбор недели от первого лица: сильные стороны (с цифрами), просадки и один-три микро-шага на следующую неделю. \
        До 120 слов, 3–4 коротких абзаца, без заголовков и без markdown-разметки.
        """
        do {
            let raw = try await AI.ask(prompt, system: persona(), model: AI.smartModel, maxTokens: 700)
            let text = ReplyPolish.clean(raw)
            guard !text.isEmpty else { return fallback }
            UserDefaults.standard.set(text, forKey: weekKey())
            return text
        } catch {
            return fallback
        }
    }

    // MARK: - Идеи

    private static let shownIdeasKey = "hf.ideas.shown"

    /// Следующая идея для мозгового штурма и готовое сообщение, оканчивающееся вопросом «Что скажешь?».
    static func nextIdea() -> (idea: AppIdea, message: String)? {
        let shown = UserDefaults.standard.stringArray(forKey: shownIdeasKey) ?? []
        guard let idea = IdeaBank.next(shown: shown) else { return nil }
        var list = shown.filter { $0 != idea.id }
        list.append(idea.id)
        UserDefaults.standard.set(list, forKey: shownIdeasKey)
        return (idea, IdeaBank.message(idea, strict: Appearance.shared.s.tone == .strict))
    }

    // MARK: - Короткий ответ для часов

    static func watchReply(to text: String, habits: [Habit]) async -> String {
        let system = persona(channel: .watch) + "\n\nДанные о привычках пользователя:\n" + context(habits)
        do {
            let answer = try await AI.chat([AI.Message(role: "user", text: text)], system: system, maxTokens: 200)
            let fit = ReplyPolish.watchFit(answer)
            if !fit.isEmpty { return fit }
        } catch {}
        return offlineWatchLine(habits)
    }

    /// Ответ часам без сети: одна короткая фраза напарника по состоянию дня.
    static func offlineWatchLine(_ habits: [Habit]) -> String {
        let mgr = CompanionManager.shared
        guard let s = mgr.status(habits) else { return "Привет! Открой HabitFlow на телефоне." }
        return ReplyPolish.watchFit(mgr.phrase(for: s))
    }
}

// MARK: - Чат с напарником

@MainActor
@Observable
final class CoachChat {
    static let shared = CoachChat()
    private static let key = "hf.chat.v1"

    var messages: [AI.Message] {
        didSet { persist() }
    }
    var thinking = false
    var error: String?
    /// Сообщение, которое нужно отправить при открытии чата (например, разбор срыва).
    var pending: String?

    private init() {
        messages = (UserDefaults.standard.data(forKey: Self.key))
            .flatMap { try? JSONDecoder().decode([AI.Message].self, from: $0) } ?? []
    }

    func send(_ text: String, habits: [Habit]) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !thinking else { return }
        error = nil
        messages.append(AI.Message(role: "user", text: t))
        await reply(habits: habits)
    }

    func retry(habits: [Habit]) async {
        guard !thinking, messages.last?.role == "user" else { return }
        error = nil
        await reply(habits: habits)
    }

    private func reply(habits: [Habit]) async {
        thinking = true
        defer { thinking = false }
        let system = AICoach.persona() + "\n\nДанные о привычках пользователя:\n" + AICoach.context(habits)
        do {
            let answer = try await AI.chat(Array(messages.suffix(16)), system: system)
            let cleaned = ReplyPolish.clean(answer)
            guard !cleaned.isEmpty else { throw AIError.badReply }
            messages.append(AI.Message(role: "assistant", text: cleaned))
            Haptics.soft()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }

    func clear() {
        messages = []
        error = nil
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(Array(messages.suffix(60))) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }
}
