import Foundation
import SwiftData
import Observation
import AuthenticationServices
import UIKit

/// Адрес сервера по умолчанию — тот же, что у Копилки: аккаунт общий.
enum ServerDefaults {
    static let url = "https://2-27-25-140.sslip.io:8443"
    static var current: String {
        let s = UserDefaults.standard.string(forKey: "hf.server") ?? ""
        return s.isEmpty ? url : s
    }
}

/// Аккаунт и синхронизация через сервер Копилки (PocketBase + модуль HabitFlow).
/// Все записи синхронизируются по принципу «побеждает более свежая правка».
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum State: Equatable {
        case off, idle, syncing, error(String)
    }

    var state: State = .off
    var lastSync: Date? = UserDefaults.standard.object(forKey: "hf.lastSync") as? Date
    var userName = UserDefaults.standard.string(forKey: "hf.userName") ?? ""
    var userEmail = UserDefaults.standard.string(forKey: "hf.userEmail") ?? ""
    /// Есть ли на сервере модуль HabitFlow (без него работают только вход и ИИ).
    var moduleAvailable: Bool = UserDefaults.standard.bool(forKey: "hf.module")
    var serverAI: Bool = UserDefaults.standard.bool(forKey: "hf.serverAI")
    /// Последние «хлопки» от друзей — показываем новые.
    var newCheers: [Cheer] = []

    struct Cheer: Identifiable, Equatable, Codable {
        var id: String { "\(from)-\(ts)" }
        let from: String
        let name: String
        let emoji: String
        let companion: String
        let ts: Double
    }

    private(set) var context: ModelContext?
    private var pushTask: Task<Void, Never>?
    private var running = false
    private var lastProfileAt = Date.distantPast
    private var needsAnother = false

    var server: String {
        get { ServerDefaults.current }
        set { UserDefaults.standard.set(newValue, forKey: "hf.server") }
    }
    var userID: String { UserDefaults.standard.string(forKey: "hf.userID") ?? "" }
    var token: String? { Keychain.get("pb-token") }
    var loggedIn: Bool { token != nil }

    private init() {
        state = loggedIn ? .idle : .off
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    // MARK: - Сеть

    struct APIError: LocalizedError {
        let message: String
        let status: Int
        var errorDescription: String? { message }
    }

    static func normalize(_ s: String) -> String {
        var u = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return u }
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    @discardableResult
    func call(_ path: String, _ body: [String: Any]? = nil, auth: Bool = true, retry: Bool = true,
              timeout: TimeInterval = 30) async throws -> [String: Any] {
        guard let url = URL(string: server + path) else { throw APIError(message: "Неверный адрес сервера", status: 0) }
        var req = URLRequest(url: url)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let t = token { req.setValue(t, forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw APIError(message: "Нет связи с сервером", status: 0) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if code == 401 && auth && retry {
            if await refreshToken() { return try await call(path, body, auth: auth, retry: false, timeout: timeout) }
            logout()
            throw APIError(message: "Сессия истекла — войдите снова", status: 401)
        }
        guard (200..<300).contains(code) else {
            var msg = jStr(obj["message"])
            if let fields = obj["data"] as? [String: Any] {
                for (k, v) in fields {
                    let f = v as? [String: Any]
                    if jStr(f?["code"]) == "validation_not_unique" && k == "email" { msg = "Этот email уже зарегистрирован — войдите"; break }
                    if k == "password", jStr(f?["code"]).contains("length") { msg = "Пароль — минимум 8 символов"; break }
                    let fm = jStr(f?["message"])
                    if !fm.isEmpty { msg = fm }
                }
            }
            if code == 400 && path.contains("auth-with-password") { msg = "Неверная почта или пароль" }
            if code == 404 && path.hasPrefix("/api/hf/") { msg = "На сервере нет модуля HabitFlow" }
            throw APIError(message: msg.isEmpty ? "Ошибка сервера (\(code))" : msg, status: code)
        }
        return obj
    }

    private func refreshToken() async -> Bool {
        guard token != nil,
              let obj = try? await call("/api/collections/users/auth-refresh", [:], auth: true, retry: false),
              let t = obj["token"] as? String else { return false }
        Keychain.set("pb-token", t)
        return true
    }

    func ping(_ address: String) async -> Bool {
        let s = Self.normalize(address)
        guard let url = URL(string: s + "/api/kp/ping"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8)?.contains("kopilka") ?? false
    }

    func checkModule() async {
        guard let url = URL(string: server + "/api/hf/ping") else { return }
        var ok = false
        if let (data, resp) = try? await URLSession.shared.data(from: url),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           String(data: data, encoding: .utf8)?.contains("habitflow") == true {
            ok = true
        }
        moduleAvailable = ok
        UserDefaults.standard.set(ok, forKey: "hf.module")
    }

    // MARK: - Вход

    func register(server addr: String, name: String, email: String, password: String) async throws {
        server = Self.normalize(addr)
        try await call("/api/collections/users/records",
                       ["email": email, "password": password, "passwordConfirm": password,
                        "name": name, "emailVisibility": true], auth: false)
        try await login(server: addr, email: email, password: password)
    }

    func login(server addr: String, email: String, password: String) async throws {
        server = Self.normalize(addr)
        let obj = try await call("/api/collections/users/auth-with-password",
                                 ["identity": email, "password": password], auth: false)
        try await finishLogin(obj)
    }

    struct OAuthProvider {
        let authURL: String
        let codeVerifier: String
        let state: String
    }

    /// Какие сервисы входа включены на сервере: google, yandex, apple.
    func oauthProviders(_ address: String) async -> [String: OAuthProvider] {
        let s = Self.normalize(address)
        guard let url = URL(string: s + "/api/collections/users/auth-methods"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        let list = ((obj["oauth2"] as? [String: Any])?["providers"] as? [[String: Any]])
            ?? (obj["authProviders"] as? [[String: Any]]) ?? []
        var out: [String: OAuthProvider] = [:]
        for g in list {
            let auth = jStr(g["authURL"]).isEmpty ? jStr(g["authUrl"]) : jStr(g["authURL"])
            out[jStr(g["name"])] = OAuthProvider(authURL: auth, codeVerifier: jStr(g["codeVerifier"]), state: jStr(g["state"]))
        }
        return out
    }

    func loginWithOAuth(_ provider: String, server addr: String) async throws {
        let base = Self.normalize(addr)
        guard let p = await oauthProviders(base)[provider] else {
            throw APIError(message: "На сервере не включён этот способ входа", status: 0)
        }
        // Адрес возврата общий с Копилкой: сервер перенаправляет на koshelek://oauth,
        // а окно входа перехватывает этот адрес само — настраивать кабинеты Google и Яндекса заново не нужно.
        let redirect = base + "/api/kp/oauth-callback"
        let enc = redirect.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? redirect
        guard let url = URL(string: p.authURL + enc) else { throw APIError(message: "Неверный адрес входа", status: 0) }
        let callback = try await OAuthWeb.run(url: url)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ n: String) -> String { items.first { $0.name == n }?.value ?? "" }
        if !q("error").isEmpty {
            if ["user_cancelled_authorize", "access_denied"].contains(q("error")) { throw APIError(message: "Вход отменён", status: -1) }
            throw APIError(message: "Ошибка входа: \(q("error"))", status: 0)
        }
        guard q("state") == p.state, !q("code").isEmpty else {
            throw APIError(message: "Вход отменён или устарел — попробуйте ещё раз", status: 0)
        }
        server = base
        let obj = try await call("/api/collections/users/auth-with-oauth2",
                                 ["provider": provider, "code": q("code"), "codeVerifier": p.codeVerifier,
                                  "redirectURL": redirect], auth: false)
        try await finishLogin(obj)
    }

    private func finishLogin(_ obj: [String: Any]) async throws {
        guard let t = obj["token"] as? String, let rec = obj["record"] as? [String: Any] else {
            throw APIError(message: "Сервер вернул неожиданный ответ", status: 0)
        }
        let newID = jStr(rec["id"])
        let previous = UserDefaults.standard.string(forKey: "hf.lastUserID") ?? ""
        Keychain.set("pb-token", t)
        UserDefaults.standard.set(newID, forKey: "hf.userID")
        UserDefaults.standard.set(newID, forKey: "hf.lastUserID")
        var name = jStr(rec["name"])
        if name.isEmpty, let meta = obj["meta"] as? [String: Any] { name = jStr(meta["name"]) }
        userName = name
        userEmail = jStr(rec["email"])
        UserDefaults.standard.set(userName, forKey: "hf.userName")
        UserDefaults.standard.set(userEmail, forKey: "hf.userEmail")
        // Всё, что было сделано до входа или под другим аккаунтом, отправляем в этот аккаунт.
        if previous != newID { markEverythingDirty() }
        state = .idle
        await checkModule()
        await refreshAIStatus()
        await sync()
        // Имя для обращения берём из аккаунта — уже после загрузки, чтобы не затереть настройки с другого устройства.
        if CompanionManager.shared.state.userName.isEmpty, let first = name.split(separator: " ").first {
            CompanionManager.shared.state.userName = String(first)
        }
    }

    func refreshAIStatus() async {
        guard loggedIn, let obj = try? await call("/api/kp/ai/status") else { return }
        serverAI = jBool(obj["enabled"])
        UserDefaults.standard.set(serverAI, forKey: "hf.serverAI")
    }

    /// Выйти. Данные остаются на устройстве и уйдут в аккаунт при следующем входе.
    func logout() {
        Keychain.set("pb-token", nil)
        UserDefaults.standard.removeObject(forKey: "hf.userID")
        serverAI = false
        UserDefaults.standard.set(false, forKey: "hf.serverAI")
        state = .off
        pushTask?.cancel()
    }

    // MARK: - Синхронизация

    private var cursorKey: String { "hf.cursor.\(userID)@\(server)" }

    /// Отправить изменения через пару секунд после последней правки.
    func schedulePush() {
        guard loggedIn, moduleAvailable else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sync(pullToo: false)
        }
    }

    func sync(pullToo: Bool = true) async {
        guard loggedIn, let ctx = context else { return }
        if !moduleAvailable {
            await checkModule()
            guard moduleAvailable else { state = .idle; return }
        }
        guard !running else { needsAnother = true; return }
        running = true
        state = .syncing
        defer {
            running = false
            // Пока шла синхронизация, могли появиться новые правки — отправим и их.
            if needsAnother { needsAnother = false; schedulePush() }
        }
        do {
            try await push(ctx)
            if pullToo { try await pull(ctx) }
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: "hf.lastSync")
            state = .idle
            // Карточку для друзей обновляем при полной синхронизации или раз в пару минут.
            if pullToo || Date().timeIntervalSince(lastProfileAt) > 120 {
                lastProfileAt = .now
                await publishProfile(ctx)
            }
        } catch let e as APIError where e.status == 404 {
            moduleAvailable = false
            UserDefaults.standard.set(false, forKey: "hf.module")
            state = .idle
        } catch {
            state = loggedIn ? .error(error.localizedDescription) : .off
        }
    }

    // MARK: Отправка

    private func push(_ ctx: ModelContext) async throws {
        var docs: [[String: Any]] = []
        var sent: [(model: any SyncStamped, stamp: Date)] = []

        func collect<T: PersistentModel & SyncStamped>(_ t: T.Type, kind: String, encode: (T) -> [String: Any]?) {
            let all = (try? ctx.fetch(FetchDescriptor<T>())) ?? []
            for m in all where m.dirty {
                guard let data = encode(m) else { continue }
                docs.append(["cid": m.id.uuidString, "kind": kind, "data": data, "deleted": false,
                             "cts": m.updatedAt.timeIntervalSince1970 * 1000])
                sent.append((m, m.updatedAt))
            }
        }
        collect(Habit.self, kind: "habit") { SyncCodec.habit($0) }
        collect(CheckIn.self, kind: "checkin") { SyncCodec.checkIn($0) }
        collect(Relapse.self, kind: "relapse") { SyncCodec.relapse($0) }
        collect(Resist.self, kind: "resist") { SyncCodec.resist($0) }

        let tombs = Tombstones.all
        for t in tombs {
            docs.append(["cid": t.cid, "kind": t.kind, "data": [:] as [String: Any], "deleted": true, "cts": t.ts * 1000])
        }
        let prefs = PrefSync.dirtyDocs()
        docs.append(contentsOf: prefs)
        guard !docs.isEmpty else { return }

        // Сначала привычки, потом всё, что на них ссылается, — так другой телефон не получит «сирот».
        let order = ["habit": 0, "prefs": 0, "checkin": 1, "relapse": 1, "resist": 1]
        docs.sort { (order[jStr($0["kind"])] ?? 2) < (order[jStr($1["kind"])] ?? 2) }

        var index = 0
        while index < docs.count {
            let chunk = Array(docs[index..<min(index + 400, docs.count)])
            try await call("/api/hf/push", ["docs": chunk], timeout: 60)
            index += chunk.count
        }
        for s in sent where abs(s.model.updatedAt.timeIntervalSince(s.stamp)) < 0.001 {
            s.model.dirty = false
        }
        Tombstones.remove(tombs.map(\.cid))
        for p in prefs { PrefSync.markSent(cid: jStr(p["cid"]), cts: jNum(p["cts"])) }
        try? ctx.save()
    }

    // MARK: Получение

    private func pull(_ ctx: ModelContext) async throws {
        var since = UserDefaults.standard.double(forKey: cursorKey)
        var pages = 0
        repeat {
            let obj = try await call("/api/hf/pull", ["since": since], timeout: 60)
            let docs = obj["docs"] as? [[String: Any]] ?? []
            SyncCodec.apply(docs, ctx: ctx)
            since = max(since, jNum(obj["cursor"]))
            UserDefaults.standard.set(since, forKey: cursorKey)
            pages += 1
            if !jBool(obj["more"]) || pages > 40 { break }
        } while true
        SyncCodec.retryOrphans(ctx: ctx)
        try? ctx.save()
    }

    /// Всё пометить к отправке (после входа в аккаунт).
    func markEverythingDirty() {
        guard let ctx = context else { return }
        func mark<T: PersistentModel & SyncStamped>(_ t: T.Type) {
            for m in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] { m.dirty = true }
        }
        mark(Habit.self); mark(CheckIn.self); mark(Relapse.self); mark(Resist.self)
        PrefSync.markAllDirty()
        try? ctx.save()
    }

    // MARK: - Карточка для друзей

    private func publishProfile(_ ctx: ModelContext) async {
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).filter { !$0.isArchived }
        let engine = StreakEngine()
        let mgr = CompanionManager.shared
        let status = mgr.status(habits)
        var list: [[String: Any]] = []
        for h in habits.sorted(by: { $0.sortOrder < $1.sortOrder }) where h.isShared {
            var item: [String: Any] = ["name": h.name, "symbol": h.symbol, "color": h.colorHex, "kind": h.kindRaw]
            if h.kind == .build {
                let s = engine.buildStreak(h.snapshot)
                item["streak"] = s.current
                item["best"] = s.best
                item["today"] = s.todayDone
            } else {
                let q = engine.quitStreak(h.snapshot)
                item["streak"] = q.currentDays
                item["best"] = q.bestDays
                item["since"] = q.since.timeIntervalSince1970
            }
            list.append(item)
        }
        let display = mgr.state.userName.isEmpty ? userName : mgr.state.userName
        var data: [String: Any] = ["name": display, "habits": Array(list.prefix(30)), "updated": Date().timeIntervalSince1970]
        if let s = status {
            data["companion"] = s.character.id
            data["companionName"] = mgr.displayName
            data["level"] = s.level
            data["stage"] = s.stage.rawValue
            data["mood"] = s.mood.rawValue
        }
        guard let obj = try? await call("/api/hf/profile", ["data": data]) else { return }
        handleCheers(obj["cheers"])
    }

    func handleCheers(_ raw: Any?) {
        let list = (raw as? [[String: Any]] ?? []).map {
            Cheer(from: jStr($0["from"]), name: jStr($0["name"]), emoji: jStr($0["emoji"]),
                  companion: jStr($0["companion"]), ts: jNum($0["ts"]))
        }
        let seen = UserDefaults.standard.double(forKey: "hf.cheersSeen")
        let fresh = list.filter { $0.ts > seen }.sorted { $0.ts < $1.ts }
        if !fresh.isEmpty && fresh != newCheers {
            newCheers = fresh
            Haptics.success()
        }
    }

    func markCheersSeen() {
        if let last = newCheers.map(\.ts).max() {
            UserDefaults.standard.set(last, forKey: "hf.cheersSeen")
        }
        newCheers = []
    }
}

// MARK: - Удалённые записи

/// Что удалили на этом устройстве — чтобы удалить и на сервере.
enum Tombstones {
    struct Item: Codable { let cid: String; let kind: String; let ts: Double }
    private static let key = "hf.tombstones"

    static var all: [Item] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }

    static func add(_ id: UUID, kind: String) {
        var list = all.filter { $0.cid != id.uuidString }
        list.append(Item(cid: id.uuidString, kind: kind, ts: Date().timeIntervalSince1970))
        save(Array(list.suffix(5000)))
    }

    static func contains(_ cid: String) -> Bool { all.contains { $0.cid == cid } }

    static func remove(_ cids: [String]) {
        let set = Set(cids)
        save(all.filter { !set.contains($0.cid) })
    }

    static func removeOne(_ id: UUID) { remove([id.uuidString]) }

    private static func save(_ list: [Item]) {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Окно входа через сервисы

@MainActor
final class OAuthWeb: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: OAuthWeb?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL) async throws -> URL {
        let w = OAuthWeb()
        current = w
        defer { current = nil }
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "koshelek") { cb, err in
                if let cb { cont.resume(returning: cb) }
                else if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: SyncEngine.APIError(message: "Вход отменён", status: -1))
                } else {
                    cont.resume(throwing: SyncEngine.APIError(message: err?.localizedDescription ?? "Не удалось войти", status: 0))
                }
            }
            s.presentationContextProvider = w
            s.prefersEphemeralWebBrowserSession = false
            w.session = s
            if !s.start() {
                cont.resume(throwing: SyncEngine.APIError(message: "Не удалось открыть окно входа", status: 0))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
