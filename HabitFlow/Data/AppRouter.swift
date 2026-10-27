import Foundation
import Observation
import SwiftData

/// Переходы между экранами из любого места: Siri, быстрые действия, ссылки, уведомления.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Tab: Int { case today = 0, companion, progress, settings }

    var tab: Tab = .today
    var showNewHabit = false
    var showAIComposer = false
    var showChat = false
    var showFriends = false
    /// Стопка быстрых карточек.
    var showCards = false
    var showReview = false
    var showRelax = false
    var settingsPage: SettingsPage?
    var toast: String?

    /// Страницы настроек, которые можно открыть ссылкой.
    enum SettingsPage: String, Hashable { case quickCards, sounds, health, qa, widgets }

    private init() {}

    func open(_ t: Tab) {
        tab = t
    }

    /// Открыть чат с напарником и сразу отправить сообщение.
    func chat(about text: String?) {
        CoachChat.shared.pending = text
        tab = .companion
        showChat = true
    }

    func say(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toast == text { toast = nil }
        }
    }

    /// habitflow://new, //companion, //chat, //friends, //join?code=…&server=…
    func handle(url: URL) {
        guard url.scheme == "habitflow" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ n: String) -> String { items.first { $0.name == n }?.value ?? "" }
        switch url.host ?? "" {
        case "new": tab = .today; showNewHabit = true
        case "ai": tab = .today; showAIComposer = true
        case "companion": tab = .companion
        case "chat": chat(about: nil)
        case "progress": tab = .progress
        case "today": tab = .today
        case "cards": tab = .today; showCards = true
        case "review": tab = .progress; showReview = true
        case "relax": showRelax = true
        case "settings":
            if let page = SettingsPage(rawValue: url.path.replacingOccurrences(of: "/", with: "")) {
                tab = .settings
                settingsPage = page
            } else {
                tab = .settings
            }
        case "friends", "join":
            let code = q("code").uppercased().filter { $0.isLetter || $0.isNumber }
            if !code.isEmpty { UserDefaults.standard.set(code, forKey: "hf.pendingJoin") }
            let server = q("server")
            if !server.isEmpty, !SyncEngine.shared.loggedIn {
                SyncEngine.shared.server = SyncEngine.normalize(server)
            }
            tab = .progress
            showFriends = true
        case "debug":
            // Только для снимков экрана в CI (запуск с -hfShot).
            guard UserDefaults.standard.string(forKey: "hfShot") != nil else { return }
            debug(url.path)
        default: break
        }
    }

    private func debug(_ path: String) {
        let mgr = CompanionManager.shared
        switch path {
        case "/hatch":
            mgr.levelUp = LevelUpEvent(level: 2, gifts: [], hatched: true, stageChanged: .baby)
        case "/levelup":
            mgr.levelUp = LevelUpEvent(level: 10, gifts: GiftCatalog.gifts(at: 10), hatched: false, stageChanged: .adult)
        case "/resist":
            let ctx = TestMode.shared.data?.container.mainContext
            if let h = ((try? ctx?.fetch(FetchDescriptor<Habit>())) ?? []).first(where: { $0.kind == .quit }) {
                mgr.showResist(h, xp: 5)
            }
        case "/chat":
            CoachChat.shared.messages = [
                AI.Message(role: "user", text: "Мне тяжело держаться"),
                AI.Message(role: "assistant", text: "Понимаю, Андрей. Ты уже 3 часа без сигарет — это настоящий шаг. Когда накатывает, попробуй 5 минут прогулки или стакан воды: тяга обычно отступает за пару минут."),
            ]
            chat(about: nil)
        default: break
        }
    }
}
