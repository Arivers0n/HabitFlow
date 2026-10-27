import Foundation

/// Общий контейнер приложения и расширения виджетов (App Group).
/// Файл входит в оба таргета, поэтому здесь только Foundation: ни SwiftData, ни WidgetKit.
///
/// Приложение пересобирают и подписывают чужим сертификатом, а подписывающие программы могут
/// переименовать группу. Поэтому идентификатор не зашит намертво, а берётся из профиля,
/// встроенного в подписанную сборку (embedded.mobileprovision), — приложение и расширение
/// находят одну и ту же группу, как бы её ни назвали. Если группы нет совсем, контейнера нет:
/// конструктор в приложении работает, а виджет показывает пример и подсказку.
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
        guard let url = containerURL else { return nil }
        return candidateGroups().first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) == url }
    }

    static var hasAccess: Bool { containerURL != nil }

    // MARK: Файлы

    static func url(_ name: String) -> URL? { containerURL?.appendingPathComponent(name) }

    static func read<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let u = url(file), let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, file: String) -> Bool {
        guard let u = url(file), let data = try? JSONEncoder().encode(value) else { return false }
        do { try data.write(to: u, options: .atomic); return true } catch { return false }
    }

    static func readConfigs() -> WidgetConfigSet? { read(WidgetConfigSet.self, file: configFile) }
    @discardableResult static func writeConfigs(_ set: WidgetConfigSet) -> Bool { write(set, file: configFile) }

    static func readSnapshot() -> WidgetSnapshot? { read(WidgetSnapshot.self, file: snapshotFile) }
    @discardableResult static func writeSnapshot(_ s: WidgetSnapshot) -> Bool { write(s, file: snapshotFile) }

    static var petImageURL: URL? {
        guard let u = url(petFile), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
}
