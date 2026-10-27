import Foundation

/// Синхронизация настроек (напарник, оформление, причины срывов).
/// Каждая группа хранит время последней локальной правки и признак «надо отправить».
/// Побеждает более свежая правка.
@MainActor
enum PrefSync {
    struct Group {
        let key: String
        let export: () -> Data?
        let apply: (Data) -> Void
    }

    private static var groups: [String: Group] = [:]
    /// Пока применяем данные с сервера, локальные изменения не помечаются.
    private(set) static var applyingRemote = false

    static func register(_ key: String, export: @escaping () -> Data?, apply: @escaping (Data) -> Void) {
        groups[key] = Group(key: key, export: export, apply: apply)
    }

    static func ensureRegistered() {
        _ = CompanionManager.shared
        _ = Appearance.shared
        _ = TriggerLibrary.shared
        _ = WidgetStore.shared
    }

    static func markChanged(_ key: String) {
        guard !applyingRemote else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "prefs.mtime.\(key)")
        UserDefaults.standard.set(true, forKey: "prefs.dirty.\(key)")
        SyncEngine.shared.schedulePush()
    }

    static func mtime(_ key: String) -> Double {
        UserDefaults.standard.double(forKey: "prefs.mtime.\(key)")
    }

    /// Документы для отправки: только изменённые группы.
    static func dirtyDocs() -> [[String: Any]] {
        ensureRegistered()
        var out: [[String: Any]] = []
        for (key, g) in groups where UserDefaults.standard.bool(forKey: "prefs.dirty.\(key)") {
            guard let d = g.export(), let s = String(data: d, encoding: .utf8) else { continue }
            out.append(["cid": "prefs.\(key)", "kind": "prefs",
                        "data": ["json": s], "deleted": false,
                        "cts": mtime(key) * 1000])
        }
        return out
    }

    /// После входа: отправляем только то, что на этом устройстве действительно меняли.
    /// Нетронутые настройки свежей установки не должны затереть настройки с другого телефона.
    static func markAllDirty() {
        ensureRegistered()
        for key in groups.keys where mtime(key) > 0 {
            UserDefaults.standard.set(true, forKey: "prefs.dirty.\(key)")
        }
    }

    static func markSent(cid: String, cts: Double) {
        let key = String(cid.dropFirst("prefs.".count))
        // Если после отправки успели что-то поменять — не снимаем отметку.
        if abs(mtime(key) * 1000 - cts) < 1 {
            UserDefaults.standard.set(false, forKey: "prefs.dirty.\(key)")
        }
    }

    static func applyRemote(cid: String, data: [String: Any], cts: Double) {
        ensureRegistered()
        let key = String(cid.dropFirst("prefs.".count))
        guard let g = groups[key] else { return }
        let localDirty = UserDefaults.standard.bool(forKey: "prefs.dirty.\(key)")
        if localDirty && mtime(key) * 1000 > cts { return }
        guard let s = data["json"] as? String, let d = s.data(using: .utf8) else { return }
        applyingRemote = true
        g.apply(d)
        applyingRemote = false
        UserDefaults.standard.set(cts / 1000, forKey: "prefs.mtime.\(key)")
        UserDefaults.standard.set(false, forKey: "prefs.dirty.\(key)")
    }
}
