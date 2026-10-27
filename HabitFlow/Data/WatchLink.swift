import Foundation
import WatchConnectivity
import SwiftData

/// Связь с будущим приложением для Apple Watch. Часы шлют вопрос, телефон отвечает одним-двумя короткими
/// предложениями. Отдельного приложения для часов в проекте пока нет, поэтому связь просто ждёт сообщений.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private override init() { super.init() }

    func start() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// Сообщение с ключом "ask" — вопрос; "status" — короткая фраза напарника без вопроса.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let question = message["ask"] as? String
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let habits = (try? AppData.shared.container.mainContext.fetch(FetchDescriptor<Habit>())) ?? []
            let text: String
            if let question, !question.trimmingCharacters(in: .whitespaces).isEmpty {
                text = await AICoach.watchReply(to: question, habits: habits)
            } else {
                text = AICoach.offlineWatchLine(habits)
            }
            reply(["reply": text])
        }
    }
}
