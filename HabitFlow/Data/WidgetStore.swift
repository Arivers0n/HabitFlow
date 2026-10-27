import Foundation
import Observation
import SwiftData
import UIKit
import WidgetKit

/// Хозяин дизайнов виджетов в приложении: хранит конфиги, отдаёт их расширению через общий контейнер
/// и обновляет снимок данных (цели дня, серии, фраза напарника) после любого изменения привычек.
/// Логика выбора чисел — в Domain (WidgetSnapshotBuilder), здесь только хранение и доставка.
@MainActor
@Observable
final class WidgetStore {
    static let shared = WidgetStore()

    private static let key = "widgets.configs"
    private static let customizedKey = "widgets.customized"
    private static let petKey = "widgets.petID"

    private(set) var configs: WidgetConfigSet
    private(set) var lastRefresh: Date?
    private(set) var lastSnapshot: WidgetSnapshot?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let builder = WidgetSnapshotBuilder()

    /// Дизайн уже менялся руками (или пришёл с другого устройства) — бэкап не должен его затирать.
    var isCustomized: Bool { UserDefaults.standard.bool(forKey: Self.customizedKey) }

    /// Подпись дала право на общую группу: без неё виджет не увидит ни дизайн, ни данные.
    var hasAccess: Bool { WidgetShared.hasAccess }

    private init() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: Self.key), let set = try? JSONDecoder().decode(WidgetConfigSet.self, from: data) {
            configs = set.validated()
        } else {
            let fresh = WidgetConfigSet.makeDefault()
            configs = fresh
            // Сразу запоминаем, чтобы случайные номера дизайнов не менялись при каждом запуске.
            if let data = try? JSONEncoder().encode(fresh) { ud.set(data, forKey: Self.key) }
        }
        PrefSync.register("widgets", export: { [weak self] in
            guard let self else { return nil }
            return try? JSONEncoder().encode(self.configs)
        }, apply: { [weak self] data in
            guard let self, let set = try? JSONDecoder().decode(WidgetConfigSet.self, from: data) else { return }
            self.store(set.validated(), userEdit: false)
        })
        deliverConfigs()
    }

    // MARK: - Правки из конструктора

    func design(slot id: Int, family: WidgetFamilyKind) -> WidgetDesign {
        configs.slot(id)?.design(for: family) ?? WidgetPresets.make(.night, for: family)
    }

    func update(_ design: WidgetDesign, inSlot id: Int) {
        var next = configs
        next.update(design, inSlot: id)
        store(next, userEdit: true)
    }

    func rename(slot id: Int, to name: String) {
        var next = configs
        guard let i = next.slots.firstIndex(where: { $0.id == id }) else { return }
        next.slots[i].name = name
        store(next.validated(), userEdit: true)
    }

    func applyPreset(_ preset: WidgetPreset, slot id: Int, family: WidgetFamilyKind) {
        update(WidgetPresets.make(preset, for: family), inSlot: id)
    }

    /// Восстановление из копии или с другого устройства.
    func replaceAll(_ set: WidgetConfigSet) {
        store(set.validated(), userEdit: true)
    }

    private func store(_ set: WidgetConfigSet, userEdit: Bool) {
        configs = set
        let ud = UserDefaults.standard
        if let data = try? JSONEncoder().encode(set) { ud.set(data, forKey: Self.key) }
        ud.set(true, forKey: Self.customizedKey)
        if userEdit { PrefSync.markChanged("widgets") }
        deliverConfigs()
    }

    private func deliverConfigs() {
        WidgetShared.writeConfigs(configs)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Снимок данных

    /// Откладывает пересчёт на секунду: серия отметок подряд даёт один снимок.
    func scheduleRefresh(context: ModelContext) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refresh(context: context)
        }
    }

    func refresh(context: ModelContext, now: Date = .now) {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let mgr = CompanionManager.shared
        let status = mgr.status(habits, now: now)
        let phrase = status.map { mgr.phrase(for: $0) } ?? ""
        var snap = builder.make(habits: habits.map(\.snapshot), userName: mgr.state.userName,
                                petName: mgr.displayName, phrase: phrase,
                                mood: status?.mood ?? .calm, now: now)
        snap.hasPetImage = syncPetImage(mgr.character)
        lastSnapshot = snap
        lastRefresh = now
        guard WidgetShared.hasAccess else { return }
        WidgetShared.writeSnapshot(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Кладёт уменьшенную картинку питомца в общий канал (расширению не нужен весь каталог картинок).
    private func syncPetImage(_ character: CompanionCharacter?) -> Bool {
        guard WidgetShared.hasAccess, let character else { return false }
        let ud = UserDefaults.standard
        if ud.string(forKey: Self.petKey) == character.id, WidgetShared.readPet() != nil { return true }
        guard let image = UIImage(named: character.imageName) else {
            WidgetShared.removePet()
            return false
        }
        let longest = max(image.size.width, image.size.height)
        let k = min(1, 320 / max(longest, 1))
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = scaled.pngData(), WidgetShared.writePet(png) else { return false }
        ud.set(character.id, forKey: Self.petKey)
        return true
    }
}
