import Foundation

/// Контекст для выбора фразы напарника.
struct PhraseContext: Sendable {
    var userName: String
    var mood: CompanionMood
    var hour: Int
    var today: DaySummary
    var quest: String?
    var bestQuit: (name: String, days: Int)?
    var level: Int
    var stage: CompanionStage
    var strict: Bool
}

/// Фразы напарника. Обращение к пользователю без рода («мы сделали», а не «ты сделал»),
/// чтобы текст был верным для любого человека.
/// Подстановки: %N — «, Имя» или пусто; %H — название привычки; %D — «15 дней».
enum CompanionPhrases {

    // MARK: - Пулы

    static let morning = [
        "Доброе утро%N! Готовы сделать этот день классным?",
        "Утро%N! Начнём со стакана воды?",
        "Привет%N! Новый день — новая серия.",
        "С добрым утром%N! Я уже на ногах и жду.",
    ]
    static let morningStrict = [
        "Утро%N. План на день ждёт.",
        "Подъём%N. Привычки сами себя не сделают.",
        "Доброе утро%N. Начнём с первой цели.",
    ]

    static let day = [
        "Как идут дела%N? Я тут, если что.",
        "Отличная погода, чтобы сделать что-то полезное%N.",
        "Маленький шаг сейчас — большая серия потом%N.",
    ]
    static let dayStrict = [
        "Середина дня%N. Проверим план.",
        "Самое время закрыть ещё одну цель%N.",
    ]

    static let evening = [
        "Вечер%N! Давай посмотрим, что мы успели.",
        "Тихий вечер%N. Можно закрыть последние цели и отдыхать.",
    ]
    static let eveningStrict = [
        "Вечер%N. До конца дня ещё можно успеть.",
    ]

    static let night = [
        "Уже поздно%N. Сон — тоже полезная привычка. Спокойной ночи!",
        "Ночь%N… Я немного вздремну. Завтра продолжим.",
    ]

    static let happy = [
        "Ура%N! Я чувствую, как становлюсь сильнее!",
        "Мы молодцы%N! Так держать!",
        "Вот это день%N! Искры летят сами собой.",
    ]
    static let happyStrict = [
        "Хорошая работа%N. Темп держим.",
        "Отлично%N. Так и продолжаем.",
    ]

    static let sad = [
        "Мне тебя не хватало%N… Давай сделаем сегодня хотя бы одну маленькую вещь?",
        "Немного грустно без тебя%N. Начнём с малого?",
        "Ничего страшного%N, бывают и такие дни. Одна отметка — и я оживу.",
    ]
    static let sadStrict = [
        "Есть пропуски%N. Вернёмся в ритм с одной цели.",
        "Серия ждёт%N. Начни с самой простой привычки.",
    ]

    static let caring = [
        "Всё в порядке%N. Ошибаться — нормально. Главное, что мы вместе и пробуем снова.",
        "Срыв — тоже часть пути%N. Я рядом, и мы не сдаёмся.",
        "Обнимаю%N. Рекорд никуда не делся, а новая серия уже началась.",
        "Давай без самокритики%N. Сделаем выводы и пойдём дальше.",
    ]
    static let caringStrict = [
        "Срыв зафиксирован%N. Разберём причину и продолжим.",
        "Бывает%N. Рекорд сохранён — теперь цель его побить.",
    ]

    static let quest = [
        "Мне нужно немного энергии — давай сделаем «%H»?",
        "Поможешь мне подрасти%N? Осталось «%H».",
        "Давай вместе: «%H», и я засияю!",
    ]
    static let questStrict = [
        "Следующая цель%N: «%H».",
        "Не забудь про «%H»%N.",
    ]

    static let streak = [
        "%D без «%H»! Это невероятно%N!",
        "Уже %D без «%H»%N. Посмотри, как вырос наш островок!",
    ]
    static let streakStrict = [
        "%D без «%H»%N. Держим планку.",
    ]

    static let egg = [
        "Тук-тук… Кажется, я скоро вылуплюсь!",
        "Внутри что-то шевелится. Ещё немного опыта!",
        "Тепло… Выполни привычку — и я проснусь.",
    ]

    static let tap = [
        "Хи-хи, щекотно!", "Ещё разок!", "Оп-ля!", "Я тебя тоже!", "Вжух!", "Привет-привет!",
    ]

    static let resisted = [
        "Победа%N! Искушение повержено!",
        "Вот это сила воли%N! Горжусь нами.",
        "Бам! Ещё одно искушение мимо%N.",
    ]
    static let resistedStrict = [
        "Устояли%N. Так и надо.",
        "Искушение отбито%N.",
    ]

    // MARK: - Выбор

    static func pick(_ c: PhraseContext, seed: Int) -> String {
        if c.stage == .egg { return fill(choose(egg, seed), c) }

        switch c.mood {
        case .caring: return fill(choose(c.strict ? caringStrict : caring, seed), c)
        case .sad: return fill(choose(c.strict ? sadStrict : sad, seed), c)
        default: break
        }

        if c.hour >= 23 || c.hour < 5 { return fill(choose(night, seed), c) }

        // Иногда — особые фразы: стрик, просьба, итог дня
        let roll = ((seed % 4) + 4) % 4
        if roll == 0, let q = c.bestQuit {
            return fill(choose(c.strict ? streakStrict : streak, seed / 4), c, habit: q.name, days: q.days)
        }
        if roll == 1, let questName = c.quest {
            return fill(choose(c.strict ? questStrict : quest, seed / 4), c, habit: questName)
        }
        if roll == 2, c.today.due > 0, c.today.done > 0, c.hour >= 17 {
            let done = c.today.done, due = c.today.due
            if done == due { return fill(c.strict ? "Все %d из %d целей%N. Чисто." : "Сегодня мы закрыли все цели%N! Я сияю!", c, done, due) }
            return fill(c.strict ? "%d из %d%N. Добьём остальное." : "Ого, сегодня уже %d из %d целей%N!", c, done, due)
        }
        if c.mood == .happy { return fill(choose(c.strict ? happyStrict : happy, seed), c) }

        switch c.hour {
        case 5..<12: return fill(choose(c.strict ? morningStrict : morning, seed), c)
        case 12..<18: return fill(choose(c.strict ? dayStrict : day, seed), c)
        default: return fill(choose(c.strict ? eveningStrict : evening, seed), c)
        }
    }

    static func caringLine(name: String, strict: Bool, seed: Int) -> String {
        fill(choose(strict ? caringStrict : caring, seed), name: name)
    }

    static func resistedLine(name: String, strict: Bool, seed: Int) -> String {
        fill(choose(strict ? resistedStrict : resisted, seed), name: name)
    }

    static func tapLine(seed: Int) -> String { choose(tap, seed) }

    // MARK: - Подстановки

    static func choose(_ pool: [String], _ seed: Int) -> String {
        let n = pool.count
        return pool[((seed % n) + n) % n]
    }

    static func fill(_ template: String, name: String, habit: String = "", days: Int = 0) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return template
            .replacingOccurrences(of: "%N", with: trimmed.isEmpty ? "" : ", \(trimmed)")
            .replacingOccurrences(of: "%H", with: habit)
            .replacingOccurrences(of: "%D", with: pluralDays(days))
    }

    private static func fill(_ t: String, _ c: PhraseContext, habit: String = "", days: Int = 0) -> String {
        fill(t, name: c.userName, habit: habit, days: days)
    }

    private static func fill(_ t: String, _ c: PhraseContext, _ a: Int, _ b: Int) -> String {
        var s = t
        if let r = s.range(of: "%d") { s.replaceSubrange(r, with: "\(a)") }
        if let r = s.range(of: "%d") { s.replaceSubrange(r, with: "\(b)") }
        return fill(s, name: c.userName)
    }
}
