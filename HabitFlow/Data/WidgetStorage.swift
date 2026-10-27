import Foundation
import Security

/// Общий контейнер приложения и расширения виджетов (App Group).
/// Файл входит в оба таргета, поэтому здесь только Foundation: ни SwiftData, ни WidgetKit.
///
/// Приложение пересобирают и подписывают чужим сертификатом, а подписывающие программы могут
/// переименовать группу. Поэтому идентификатор не зашит намертво, а берётся из профиля,
/// встроенного в подписанную сборку (embedded.mobileprovision), — приложение и расширение
/// находят одну и ту же группу, как бы её ни назвали.
///
/// Запасной канал: если App Group подписью не выдан, данные идут через общую группу связки ключей
/// «<команда>.habitflow.shared». Ей достаточно wildcard-права профиля, а префикс команды
/// узнаётся запросом к самой связке. Если не работают оба канала, конструктор в приложении
/// всё равно работает, а виджет показывает пример и подсказку.
enum WidgetShared {
    static let defaultGroup = "group.com.ariverson.habitflow"
    static let configFile = "widget-configs.json"
    static let snapshotFile = "widget-snapshot.json"
    static let petFile = "widget-pet.png"

    // MARK: Контейнер

    /// Группы из встроенного профиля. В неподписанной сборке (CI, симулятор) профиля нет — список пуст.
    static func provisionedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)), start.lowerBound < end.upperBound
        else { return [] }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let obj = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Any],
              let ents = obj["Entitlements"] as? [String: Any],
              let groups = ents["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }

    /// Порядок попыток: привычное имя, потом группы с «habitflow» в названии, потом остальные.
    static func candidateGroups() -> [String] {
        let provisioned = provisionedGroups().sorted()
        var out: [String] = []
        func add(_ g: String) { if !out.contains(g) { out.append(g) } }
        if provisioned.contains(defaultGroup) { add(defaultGroup) }
        provisioned.filter { $0.lowercased().contains("habitflow") }.forEach(add)
        provisioned.forEach(add)
        add(defaultGroup)
        return out
    }

    /// Папка общей группы или nil, если подпись не даёт права App Group.
    static let containerURL: URL? = {
        for group in candidateGroups() {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return url }
        }
        return nil
    }()

    /// Название найденной группы — для экрана диагностики.
    static var groupName: String? {
        switch channel {
        case .appGroup:
            guard let url = containerURL else { return nil }
            return candidateGroups().first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) == url }
        case .keychain:
            return SharedKeychain.group
        case .none:
            return nil
        }
    }

    // MARK: Канал

    enum Channel: Sendable {
        case appGroup, keychain, none

        var title: String {
            switch self {
            case .appGroup: "App Group"
            case .keychain: "Связка ключей (запасной)"
            case .none: "нет"
            }
        }
    }

    /// Какой канал реально работает в этой сборке. Проверяется один раз за запуск.
    static let channel: Channel = {
        if containerURL != nil { return .appGroup }
        if SharedKeychain.canWrite { return .keychain }
        return .none
    }()

    static var hasAccess: Bool { channel != .none }

    // MARK: Данные

    static func url(_ name: String) -> URL? { containerURL?.appendingPathComponent(name) }

    static func readData(_ name: String) -> Data? {
        switch channel {
        case .appGroup:
            guard let u = url(name) else { return nil }
            return try? Data(contentsOf: u)
        case .keychain:
            return SharedKeychain.read(name)
        case .none:
            return nil
        }
    }

    @discardableResult
    static func writeData(_ data: Data, name: String) -> Bool {
        switch channel {
        case .appGroup:
            guard let u = url(name) else { return false }
            do { try data.write(to: u, options: .atomic); return true } catch { return false }
        case .keychain:
            return SharedKeychain.write(name, data)
        case .none:
            return false
        }
    }

    static func removeData(_ name: String) {
        switch channel {
        case .appGroup:
            if let u = url(name) { try? FileManager.default.removeItem(at: u) }
        case .keychain:
            SharedKeychain.remove(name)
        case .none:
            break
        }
    }

    static func read<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let data = readData(file) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, file: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return writeData(data, name: file)
    }

    static func readConfigs() -> WidgetConfigSet? { read(WidgetConfigSet.self, file: configFile) }
    @discardableResult static func writeConfigs(_ set: WidgetConfigSet) -> Bool { write(set, file: configFile) }

    static func readSnapshot() -> WidgetSnapshot? { read(WidgetSnapshot.self, file: snapshotFile) }
    @discardableResult static func writeSnapshot(_ s: WidgetSnapshot) -> Bool { write(s, file: snapshotFile) }

    static func readPet() -> Data? { readData(petFile) }
    @discardableResult static func writePet(_ png: Data) -> Bool { writeData(png, name: petFile) }
    static func removePet() { removeData(petFile) }
}

// MARK: - Общая связка ключей

/// Общая группа связки ключей двух процессов одной команды.
enum SharedKeychain {
    private static let service = "com.ariverson.habitflow.widgets"

    /// «<команда>.habitflow.shared». Префикс команды берём у самой системы: кладём пробную запись
    /// в стандартную группу процесса и читаем, как её назвали («КОМАНДА.com.ariverson…»).
    static let group: String? = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ariverson.habitflow.probe",
            kSecAttrAccount as String: "team",
        ]
        var found: CFTypeRef?
        var query = probe
        query[kSecReturnAttributes as String] = true
        var status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecItemNotFound {
            var add = probe
            add[kSecValueData as String] = Data([1])
            add[kSecReturnAttributes as String] = true
            status = SecItemAdd(add as CFDictionary, &found)
        }
        guard status == errSecSuccess,
              let attrs = found as? [String: Any],
              let full = attrs[kSecAttrAccessGroup as String] as? String,
              let team = full.split(separator: ".").first, !team.isEmpty
        else { return nil }
        return "\(team).habitflow.shared"
    }()

    private static func base(_ name: String, group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecAttrAccessGroup as String: group]
    }

    static func read(_ name: String) -> Data? {
        guard let group else { return nil }
        var q = base(name, group: group)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func write(_ name: String, _ data: Data) -> Bool {
        guard let group else { return false }
        let key = base(name, group: group)
        var status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = key
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func remove(_ name: String) {
        guard let group else { return }
        SecItemDelete(base(name, group: group) as CFDictionary)
    }

    /// Группа реально доступна: пробная запись в неё сохраняется.
    static var canWrite: Bool { write("probe", Data([1])) }
}
