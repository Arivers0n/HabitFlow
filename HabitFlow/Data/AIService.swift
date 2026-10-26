import Foundation

// MARK: - Ошибки

enum AIError: LocalizedError {
    case unavailable, http(Int, String), badReply, network(String), badURL

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "ИИ недоступен: войдите в аккаунт (Настройки → Аккаунт) или добавьте свой ключ в «Умные функции»."
        case .http(let code, let msg):
            if code == 401 { return msg.contains("Сессия") ? msg : "Ключ API не подходит. Проверьте его в настройках." }
            if code == 503 && !msg.isEmpty { return msg }
            if code == 429 { return msg.isEmpty ? "Слишком много запросов. Попробуйте через минуту." : msg }
            if code == 404 && msg.lowercased().contains("model") { return "Модель не найдена. Проверьте название модели в настройках." }
            if code == 404 { return "По этому адресу нет API. Проверьте Base URL." }
            if code == 400 && msg.contains("credit") { return "На балансе API закончились деньги." }
            if code >= 500 { return "ИИ временно недоступен. Попробуйте позже." }
            return "Ошибка ИИ (\(code)): \(msg.prefix(140))"
        case .badReply: return "Не получилось разобрать ответ. Попробуйте ещё раз."
        case .network(let m): return "Нет связи с ИИ: \(m)"
        case .badURL: return "Неверный Base URL. Нужен адрес вида https://gateway.example.com"
        }
    }
}

// MARK: - Настройки подключения

/// Свой ключ, свой шлюз и своя модель. Без них ИИ идёт через сервер (нужен вход).
enum AIConfig {
    static let defaultBase = "https://api.anthropic.com"
    static let defaultFast = "claude-haiku-5-5"
    static let defaultSmart = "claude-sonnet-5-5"

    static var apiKey: String? {
        get { Keychain.get("anthropic-api-key") }
        set { Keychain.set("anthropic-api-key", newValue) }
    }

    static var baseURL: String {
        get { Keychain.get("anthropic-base-url") ?? "" }
        set { Keychain.set("anthropic-base-url", newValue) }
    }

    static var model: String {
        get { Keychain.get("anthropic-model") ?? "" }
        set { Keychain.set("anthropic-model", newValue) }
    }

    static var isCustomBase: Bool { !baseURL.isEmpty }

    static func endpoint(for base: String = baseURL) throws -> URL {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { b = defaultBase }
        if !b.lowercased().hasPrefix("http") { b = "https://" + b }
        while b.hasSuffix("/") { b.removeLast() }
        let lower = b.lowercased()
        if lower.hasSuffix("/v1/messages") {
        } else if lower.hasSuffix("/v1") {
            b += "/messages"
        } else {
            b += "/v1/messages"
        }
        guard let url = URL(string: b), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            throw AIError.badURL
        }
        return url
    }
}

// MARK: - Клиент

@MainActor
enum AI {
    /// ИИ через сервер: ключ лежит на сервере, приложение передаёт только токен входа.
    static var usesServer: Bool {
        AIConfig.apiKey == nil && SyncEngine.shared.loggedIn && SyncEngine.shared.serverAI
    }

    static var available: Bool { AIConfig.apiKey != nil || usesServer }

    static var statusText: String {
        if AIConfig.apiKey != nil { return AIConfig.isCustomBase ? "Свой шлюз" : "Свой ключ" }
        if usesServer { return "Через сервер" }
        if SyncEngine.shared.loggedIn { return "На сервере не включён" }
        return "Нужен вход или ключ"
    }

    static var fastModel: String { AIConfig.model.isEmpty ? AIConfig.defaultFast : AIConfig.model }
    static var smartModel: String { AIConfig.model.isEmpty ? AIConfig.defaultSmart : AIConfig.model }

    struct Message: Codable, Equatable, Identifiable {
        var id = UUID()
        let role: String   // user | assistant
        let text: String
        var date = Date()
    }

    /// Один вопрос — один ответ.
    static func ask(_ prompt: String, system: String? = nil, model: String? = nil, maxTokens: Int = 1500) async throws -> String {
        try await chat([Message(role: "user", text: prompt)], system: system, model: model, maxTokens: maxTokens)
    }

    /// Диалог с системной ролью.
    static func chat(_ messages: [Message], system: String?, model: String? = nil, maxTokens: Int = 1200) async throws -> String {
        // Диалог должен начинаться с пользователя и чередоваться — склеиваем подряд идущие реплики.
        var merged: [[String: Any]] = []
        for m in messages where !m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let last = merged.last, last["role"] as? String == m.role {
                merged[merged.count - 1]["content"] = (last["content"] as? String ?? "") + "\n\n" + m.text
            } else {
                merged.append(["role": m.role, "content": m.text])
            }
        }
        while let first = merged.first, first["role"] as? String != "user" { merged.removeFirst() }
        guard !merged.isEmpty else { throw AIError.badReply }
        var body: [String: Any] = ["model": model ?? fastModel, "max_tokens": maxTokens, "messages": merged]
        if let system { body["system"] = system }
        return try await send(body, timeout: 90)
    }

    /// Ответ в JSON: вырезаем объект или массив из текста.
    static func json(_ prompt: String, system: String? = nil, model: String? = nil) async throws -> Any {
        let text = try await ask(prompt, system: system, model: model, maxTokens: 2000)
        let s = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        let start = s.firstIndex(where: { $0 == "{" || $0 == "[" })
        let end = s.lastIndex(where: { $0 == "}" || $0 == "]" })
        guard let start, let end, start <= end,
              let data = String(s[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { throw AIError.badReply }
        return obj
    }

    static func send(_ body: [String: Any], timeout: TimeInterval) async throws -> String {
        if usesServer { return try await sendViaServer(body, timeout: timeout) }
        guard let key = AIConfig.apiKey else { throw AIError.unavailable }
        var req = URLRequest(url: try AIConfig.endpoint())
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        if AIConfig.isCustomBase { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }

    private static func sendViaServer(_ body: [String: Any], timeout: TimeInterval) async throws -> String {
        guard let token = SyncEngine.shared.token,
              let url = URL(string: SyncEngine.shared.server + "/api/kp/ai") else { throw AIError.unavailable }
        var b = body
        if AIConfig.model.isEmpty { b.removeValue(forKey: "model") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout + 10
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        do {
            return try await perform(req)
        } catch AIError.http(401, _) {
            throw AIError.http(401, "Сессия истекла — войдите в аккаунт снова")
        }
    }

    private static func perform(_ req: URLRequest) async throws -> String {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw AIError.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            let msg = ((obj?["error"] as? [String: Any])?["message"] as? String)
                ?? (obj?["message"] as? String)
                ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AIError.http(code, msg)
        }
        let blocks = obj?["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.badReply }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
