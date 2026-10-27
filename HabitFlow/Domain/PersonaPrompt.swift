import Foundation

// Роль напарника для ИИ и «полировка» ответов. Чистый Swift: правила проверяются тестами.

enum AIChannel: String, Sendable {
    /// Обычный чат в телефоне.
    case phone
    /// Часы: 1–2 коротких предложения, чтобы текст помещался на маленьком экране.
    case watch
}

struct PersonaInput: Sendable {
    var name: String
    var species: String?
    var trait: String?
    var userName: String
    var strict: Bool
    var channel: AIChannel = .phone
    /// Если true, в конце ответа напарник предлагает идею и спрашивает «Что скажешь?».
    var brainstorm: Bool = false
}

enum PersonaPrompt {

    static func build(_ p: PersonaInput) -> String {
        var parts: [String] = []
        let user = p.userName.trimmingCharacters(in: .whitespaces)

        if let species = p.species, !species.isEmpty {
            var intro = "Ты — \(p.name), \(species.lowercased()), напарник пользователя в приложении привычек HabitFlow."
            if let trait = p.trait, !trait.isEmpty { intro += " Характер: \(trait)" }
            parts.append(intro)
        } else {
            parts.append("Ты — дружелюбный напарник в приложении привычек HabitFlow.")
        }
        parts.append("Говори от первого лица, по-русски, на «ты». Не используй род там, где можно обойтись без него: «мы сделали», «получилось».")

        switch p.channel {
        case .phone:
            parts.append("Отвечай коротко: 2–5 предложений, без списков и без markdown-разметки, если о них не просят.")
        case .watch:
            parts.append("Запрос пришёл с Apple Watch. Ответь одним или двумя короткими предложениями, всего не больше 120 символов, без списков, эмодзи и разметки.")
        }
        parts.append(p.strict ? "Тон прямой и деловой, без сюсюканья, но без упрёков."
                              : "Тон тёплый и поддерживающий.")
        if !user.isEmpty { parts.append("Пользователя зовут \(user), иногда обращайся по имени.") }

        parts.append("Опирайся на данные о привычках ниже, называй конкретные цифры и привычки. Не выдумывай данные, которых нет.")
        parts.append("Настроение зависит от выполнения привычек: радуйся успехам, при просадках поддерживай без упрёков.")
        parts.append("После срыва никогда не ругай и не стыди: срыв — часть пути, рекорд сохраняется. Помоги понять причину и предложи один простой план на похожую ситуацию.")
        parts.append("Не ставь диагнозов и не назначай лекарств. Если речь о сильной зависимости от алкоголя или о тяжёлом самочувствии, мягко посоветуй обратиться к врачу.")
        parts.append("Если человек пишет о желании навредить себе, бережно предложи обратиться к близким и к специалисту или на линию психологической помощи.")
        parts.append("Данные о сне и тренировках используй только как мягкую подсказку: сон мало — лечь пораньше, была тренировка — добавить воды.")

        if p.brainstorm && p.channel == .phone {
            parts.append("Предложи одну небольшую идею по улучшению приложения или привычек и закончи сообщение вопросом «Что скажешь?».")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum ReplyPolish {

    /// Убирает markdown и лишние пробелы: в пузырях чата и на часах разметка выглядит мусором.
    static func clean(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("```") { continue }
            while l.hasPrefix("#") { l.removeFirst() }
            l = l.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") { l = "• " + l.dropFirst(2) }
            if l == "---" || l == "***" { continue }
            lines.append(l)
        }
        var s = lines.joined(separator: "\n")
        for mark in ["**", "__", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
        s = s.replacingOccurrences(of: "\\*([^*\\n]+)\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Для часов: целые предложения, не больше `limit` символов, без переносов и эмодзи-мусора.
    static func watchFit(_ text: String, limit: Int = 120) -> String {
        let flat = clean(text).replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "• ", with: "")
            .replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if flat.count <= limit { return flat }

        var out = ""
        for sentence in sentences(flat) {
            let candidate = out.isEmpty ? sentence : out + " " + sentence
            if candidate.count > limit { break }
            out = candidate
        }
        if !out.isEmpty { return out }

        // Одно длинное предложение: режем по слову и ставим многоточие.
        var cut = ""
        for word in flat.split(separator: " ") {
            let next = cut.isEmpty ? String(word) : cut + " " + word
            if next.count > limit - 1 { break }
            cut = next
        }
        while let last = cut.last, ",;:—-".contains(last) { cut.removeLast() }
        return cut + "…"
    }

    /// Предложения с сохранением знаков в конце.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            if ".!?…".contains(ch) {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next == " " || next == "\n" || i + 1 == chars.count {
                    let t = current.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { result.append(t) }
                    current = ""
                }
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// Мозговой штурм всегда заканчивается вопросом «Что скажешь?» — один раз.
    static func ensureBrainstormEnding(_ text: String) -> String {
        var s = clean(text)
        let ending = "Что скажешь?"
        if s.lowercased().hasSuffix(ending.lowercased()) { return s }
        if s.isEmpty { return ending }
        if let last = s.last, "?!.…".contains(last) { return s + " " + ending }
        return s + ". " + ending
    }
}
