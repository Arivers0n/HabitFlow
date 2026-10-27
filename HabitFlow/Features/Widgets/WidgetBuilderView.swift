import SwiftUI
import SwiftData
import UIKit

/// Конструктор виджетов: слот → размер → живой предпросмотр → фон, раскладка и блоки.
/// Здесь только интерфейс. Значения проверяет и ограничивает Domain (WidgetDesign.validated),
/// хранение и доставку виджету делает WidgetStore.
struct WidgetBuilderView: View {
    @Environment(\.modelContext) private var context
    @State private var store = WidgetStore.shared
    @State private var slotID = 1
    @State private var family: WidgetFamilyKind = .small
    @State private var design = WidgetPresets.make(.night, for: .small)
    @State private var useSample = false
    @State private var saveTask: Task<Void, Never>?
    @State private var renaming = false
    @State private var newName = ""

    private var snapshot: WidgetSnapshot {
        if useSample { return WidgetSnapshot.sample() }
        return store.lastSnapshot ?? WidgetShared.readSnapshot() ?? WidgetSnapshot.sample()
    }

    var body: some View {
        Form {
            selectorSection
            previewSection
            presetSection
            if !family.isLockScreen {
                backgroundSection
                layoutSection
            }
            blocksSection
            linkSection
        }
        .navigationTitle("Виджеты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear {
            applyShotArguments()
            load()
            store.refresh(context: context)
        }
        .onChange(of: slotID) { _, _ in load() }
        .onChange(of: family) { _, _ in load() }
        .onChange(of: design) { _, _ in scheduleSave() }
        .alert("Название виджета", isPresented: $renaming) {
            TextField("Название", text: $newName)
            Button("Готово") { store.rename(slot: slotID, to: newName) }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Загрузка и сохранение

    /// Снимки экрана в CI: `-hfWidgetFamily medium`, `-hfWidgetSlot 2` (только вместе с -hfShot).
    private func applyShotArguments() {
        let ud = UserDefaults.standard
        guard ud.string(forKey: "hfShot") != nil else { return }
        if let raw = ud.string(forKey: "hfWidgetFamily"), let f = WidgetFamilyKind(rawValue: raw) { family = f }
        let slot = ud.integer(forKey: "hfWidgetSlot")
        if (1...WidgetConfigSet.slotCount).contains(slot) { slotID = slot }
    }

    private func load() {
        design = store.design(slot: slotID, family: family)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if design.validated() != store.design(slot: slotID, family: family) {
                store.update(design, inSlot: slotID)
            }
        }
    }

    // MARK: Разделы

    private var selectorSection: some View {
        Section {
            Picker("Виджет", selection: $slotID) {
                ForEach(store.configs.slots) { slot in
                    Text(slot.name).tag(slot.id)
                }
            }
            Button("Переименовать") {
                newName = store.configs.slot(slotID)?.name ?? ""
                renaming = true
            }
            Picker("Размер", selection: $family) {
                Section("Рабочий стол") {
                    ForEach(WidgetFamilyKind.desktop, id: \.self) { Text($0.title).tag($0) }
                }
                Section("Экран блокировки") {
                    ForEach(WidgetFamilyKind.lock, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } footer: {
            Text("В системе добавьте виджет HabitFlow, нажмите на него и выберите здесь созданный виджет. Для каждого размера дизайн свой.")
        }
    }

    private var previewSection: some View {
        Section {
            PreviewBox(design: design, snapshot: snapshot, petImage: petImage)
            Toggle("Показать пример данных", isOn: $useSample)
        } header: {
            Text("Так выглядит")
        }
    }

    private var petImage: UIImage? {
        guard snapshot.hasPetImage, let data = WidgetShared.readPet() else { return nil }
        return UIImage(data: data)
    }

    private var presetSection: some View {
        Section("Пресеты") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WidgetPreset.allCases, id: \.self) { preset in
                        Button(preset.title) {
                            design = WidgetPresets.make(preset, for: family)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var backgroundSection: some View {
        Section("Фон") {
            Picker("Тип", selection: $design.background.kind) {
                ForEach(WidgetBackgroundKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            HexColorRow(title: "Цвет", hex: $design.background.colorA)
            if design.background.kind == .gradient {
                HexColorRow(title: "Второй цвет", hex: $design.background.colorB)
                SliderRow(title: "Угол", value: $design.background.angle, range: 0...360, step: 5, format: "%.0f°")
            }
            SliderRow(title: "Непрозрачность", value: $design.background.opacity, range: 0...1, step: 0.05, format: "%.2f")
        }
    }

    private var layoutSection: some View {
        Section("Раскладка") {
            Picker("Расположение", selection: $design.layout) {
                ForEach(WidgetLayoutKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Выравнивание", selection: $design.align) {
                ForEach(WidgetAlign.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            SliderRow(title: "Отступ от краёв", value: $design.padding, range: 0...32, step: 1, format: "%.0f")
            SliderRow(title: "Между колонками", value: $design.spacing, range: 0...32, step: 1, format: "%.0f")
        }
    }

    private var blocksSection: some View {
        Section {
            ForEach($design.blocks) { $block in
                NavigationLink {
                    WidgetBlockEditor(block: $block, family: family)
                } label: {
                    BlockRow(block: block)
                }
            }
            .onMove { design.blocks.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { design.blocks.remove(atOffsets: $0) }

            Menu {
                ForEach(addableKinds, id: \.self) { kind in
                    Button(kind.title) { add(kind) }
                }
            } label: {
                Label("Добавить блок", systemImage: "plus.circle.fill")
            }
            .disabled(design.blocks.count >= family.maxBlocks)
        } header: {
            Text("Блоки (\(design.blocks.count) из \(family.maxBlocks))")
        } footer: {
            Text("Порядок меняется перетаскиванием (кнопка «Изменить» сверху). Нажмите на блок, чтобы настроить шрифт, цвет, размер и подписи.")
        }
    }

    private var addableKinds: [WidgetBlockKind] {
        WidgetBlockKind.allCases.filter { !family.isLockScreen || $0.allowedOnLockScreen }
    }

    private func add(_ kind: WidgetBlockKind) {
        var b = WidgetBlock(kind: kind)
        if let ref = design.blocks.first {
            b.style.colorHex = ref.style.colorHex
            b.style.design = ref.style.design
            b.accentHex = ref.accentHex
            b.trackHex = ref.trackHex
            b.trackOpacity = ref.trackOpacity
        }
        design.blocks.append(b)
    }

    private var linkSection: some View {
        Section {
            LabeledContent("Канал данных", value: WidgetShared.channel.title)
            if let group = WidgetShared.groupName {
                LabeledContent("Группа", value: group)
            }
            if let t = store.lastRefresh {
                LabeledContent("Данные обновлены", value: t.formatted(date: .omitted, time: .shortened))
            }
            Button("Обновить виджеты сейчас") { store.refresh(context: context) }
        } header: {
            Text("Связь с виджетом")
        } footer: {
            Text(store.hasAccess
                 ? "Виджет получает дизайн и данные из приложения."
                 : "Подпись не даёт приложению ни App Group, ни общую связку ключей, поэтому виджет не увидит ни дизайн, ни данные: он покажет пример с жёлтым значком. Конструктор при этом работает.")
        }
    }
}

// MARK: - Строка блока

private struct BlockRow: View {
    let block: WidgetBlock

    var body: some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.kind.title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        if block.kind == .customText { return block.text.isEmpty ? "Мой текст" : block.text }
        return "\(Int(block.style.size)) пт · \(block.style.design.title)"
    }

    private var symbol: String {
        switch block.kind {
        case .dayRing: return "circle.dashed"
        case .doneText: return "checkmark.circle"
        case .percentText: return "percent"
        case .bestQuit: return "flame"
        case .quitList: return "list.bullet"
        case .buildStreak: return "bolt"
        case .level: return "chart.bar"
        case .phrase: return "text.bubble"
        case .nextHabit: return "arrow.right.circle"
        case .weekDots: return "ellipsis"
        case .date: return "calendar"
        case .greeting: return "hand.wave"
        case .petImage: return "pawprint"
        case .customText: return "textformat"
        }
    }
}

// MARK: - Предпросмотр с масштабом

private struct PreviewBox: View {
    let design: WidgetDesign
    let snapshot: WidgetSnapshot
    let petImage: UIImage?

    var body: some View {
        let size = design.family.previewSize
        let inset = 14.0
        GeometryReader { geo in
            let scale = min(1, (geo.size.width - inset * 2) / size.width)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "5B6B7F"), Color(hex: "2D3A4B")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                WidgetPreviewView(design: design, snapshot: snapshot, petImage: petImage)
                    .scaleEffect(scale)
                    .frame(width: size.width * scale + 20 * scale, height: size.height * scale + 20 * scale)
            }
        }
        .frame(height: size.height + 20 + inset * 2)
        .listRowInsets(EdgeInsets())
    }
}

// MARK: - Общие элементы

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format = "%.0f"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// Цвет: выбор из палитры и точный ввод hex.
struct HexColorRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            ColorPicker(title, selection: pickerBinding, supportsOpacity: false)
            TextField("HEX", text: $hex)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .monospaced))
                .frame(width: 84)
        }
    }

    private var pickerBinding: Binding<Color> {
        Binding(get: { Color(hex: hex) },
                set: { hex = $0.widgetHex })
    }
}

extension Color {
    /// «RRGGBB» без прозрачности.
    var widgetHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let v = (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
        return String(format: "%06X", v)
    }
}
