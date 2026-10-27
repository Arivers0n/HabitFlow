import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// Виджеты HabitFlow. Дизайн рисуется по конфигу из конструктора в приложении:
// расширение ничего не решает само, только читает общий контейнер и вызывает общий рендерер.

@main
struct HabitFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitFlowWidget()
    }
}

// MARK: - Выбор слота

struct SlotEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Виджет")
    static var defaultQuery = SlotQuery()

    var id: Int
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SlotQuery: EntityQuery {
    private func all() -> [SlotEntity] {
        let set = WidgetShared.readConfigs() ?? WidgetConfigSet.makeDefault()
        return set.slots.map { SlotEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [Int]) async throws -> [SlotEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SlotEntity] { all() }

    func defaultResult() async -> SlotEntity? { all().first }
}

struct SelectSlotIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Какой виджет показать"
    static var description = IntentDescription("Выберите один из своих дизайнов из конструктора HabitFlow.")

    @Parameter(title: "Виджет")
    var slot: SlotEntity?
}

// MARK: - Данные записи

struct HabitFlowEntry: TimelineEntry {
    let date: Date
    let design: WidgetDesign
    let snapshot: WidgetSnapshot
    /// Реальные данные приложения дошли до виджета (иначе показываем пример).
    let hasData: Bool
    let petImage: UIImage?
}

extension WidgetFamily {
    var kind: WidgetFamilyKind {
        switch self {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemLarge: return .large
        case .accessoryCircular: return .lockCircular
        case .accessoryRectangular: return .lockRectangular
        case .accessoryInline: return .lockInline
        default: return .medium
        }
    }
}

struct HabitFlowProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitFlowEntry {
        makeEntry(slot: 1, family: context.family.kind, sample: true)
    }

    func snapshot(for configuration: SelectSlotIntent, in context: Context) async -> HabitFlowEntry {
        makeEntry(slot: configuration.slot?.id ?? 1, family: context.family.kind, sample: context.isPreview)
    }

    func timeline(for configuration: SelectSlotIntent, in context: Context) async -> Timeline<HabitFlowEntry> {
        let entry = makeEntry(slot: configuration.slot?.id ?? 1, family: context.family.kind, sample: false)
        // Раз в полчаса и обязательно после полуночи: цели дня сбрасываются.
        let calendar = Calendar.habitFlow
        let half = Date().addingTimeInterval(30 * 60)
        let midnight = calendar.startOfDay(for: calendar.addingDays(1, to: .now)).addingTimeInterval(5)
        return Timeline(entries: [entry], policy: .after(min(half, midnight)))
    }

    private func makeEntry(slot: Int, family: WidgetFamilyKind, sample: Bool) -> HabitFlowEntry {
        let configs = (WidgetShared.readConfigs() ?? WidgetConfigSet.makeDefault()).validated()
        let design = configs.slot(slot)?.design(for: family) ?? WidgetPresets.make(.night, for: family)
        let real = sample ? nil : WidgetShared.readSnapshot()
        let snapshot = real ?? WidgetSnapshot.sample()
        var pet: UIImage?
        if snapshot.hasPetImage, let data = WidgetShared.readPet() { pet = UIImage(data: data) }
        return HabitFlowEntry(date: .now, design: design, snapshot: snapshot, hasData: real != nil || sample, petImage: pet)
    }
}

// MARK: - Вид

struct HabitFlowEntryView: View {
    let entry: HabitFlowEntry

    var body: some View {
        if entry.design.family.isLockScreen {
            WidgetLockView(design: entry.design, snapshot: entry.snapshot, now: entry.date, systemBackground: true)
                .widgetURL(URL(string: "habitflow://today"))
                .containerBackground(for: .widget) { Color.clear }
        } else {
            WidgetDesignView(design: entry.design, snapshot: entry.snapshot, now: entry.date, petImage: entry.petImage)
                .overlay(alignment: .topTrailing) { warning }
                .widgetURL(URL(string: "habitflow://today"))
                .containerBackground(for: .widget) {
                    WidgetBackgroundView(background: entry.design.background)
                }
        }
    }

    @ViewBuilder
    private var warning: some View {
        if !entry.hasData {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.yellow)
                .padding(8)
        }
    }
}

struct HabitFlowWidget: Widget {
    let kind = "HabitFlowWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectSlotIntent.self, provider: HabitFlowProvider()) { entry in
            HabitFlowEntryView(entry: entry)
        }
        .configurationDisplayName("HabitFlow")
        .description("Ваш дизайн из конструктора: цели дня, серии, напарник.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}
