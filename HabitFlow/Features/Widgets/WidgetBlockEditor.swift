import SwiftUI

/// Подробная настройка одного блока: что показывает, шрифт, цвет, размер, подписи, форма.
struct WidgetBlockEditor: View {
    @Binding var block: WidgetBlock
    let family: WidgetFamilyKind

    private var kinds: [WidgetBlockKind] {
        WidgetBlockKind.allCases.filter { !family.isLockScreen || $0.allowedOnLockScreen }
    }

    var body: some View {
        Form {
            contentSection
            fontSection
            if !family.isLockScreen { colorSection }
            if block.kind.usesAccent { shapeSection }
            captionSection
            spacingSection
        }
        .navigationTitle(block.kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var contentSection: some View {
        Section("Что показывать") {
            Picker("Блок", selection: $block.kind) {
                ForEach(kinds, id: \.self) { Text($0.title).tag($0) }
            }
            if block.kind == .customText {
                TextField("Текст", text: $block.text, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }

    private var fontSection: some View {
        Section("Шрифт") {
            Picker("Начертание", selection: $block.style.design) {
                ForEach(WidgetFontDesign.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            SliderRow(title: "Размер", value: $block.style.size, range: WidgetTextStyle.sizeRange, step: 1, format: "%.0f пт")
            Stepper("Толщина: \(weightName)", value: $block.style.weight, in: 0...8)
            Picker("Выравнивание", selection: $block.style.alignment) {
                ForEach(WidgetAlign.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("ЗАГЛАВНЫЕ", isOn: $block.style.uppercase)
            SliderRow(title: "Межбуквенный интервал", value: $block.style.tracking,
                      range: WidgetTextStyle.trackingRange, step: 0.5, format: "%.1f")
            Stepper("Строк не больше: \(block.style.lineLimit)", value: $block.style.lineLimit, in: 1...6)
        }
    }

    private var colorSection: some View {
        Section("Цвет текста") {
            HexColorRow(title: "Цвет", hex: $block.style.colorHex)
            SliderRow(title: "Непрозрачность", value: $block.style.opacity, range: 0.1...1, step: 0.05, format: "%.2f")
        }
    }

    private var shapeSection: some View {
        Section("Форма") {
            if !family.isLockScreen {
                HexColorRow(title: "Цвет заливки", hex: $block.accentHex)
                HexColorRow(title: "Цвет подложки", hex: $block.trackHex)
                SliderRow(title: "Яркость подложки", value: $block.trackOpacity, range: 0...1, step: 0.02, format: "%.2f")
            }
            SliderRow(title: "Толщина", value: $block.thickness, range: WidgetBlock.thicknessRange, step: 1, format: "%.0f")
        }
    }

    private var captionSection: some View {
        Section("Подпись") {
            Toggle("Показывать подпись", isOn: $block.showCaption)
            if block.showCaption {
                SliderRow(title: "Размер подписи", value: $block.captionScale, range: 0.4...1, step: 0.05, format: "×%.2f")
            }
        }
    }

    private var spacingSection: some View {
        Section("Отступ") {
            SliderRow(title: "После блока", value: $block.spaceAfter, range: 0...40, step: 1, format: "%.0f")
        }
    }

    private var weightName: String {
        let names = ["сверхтонкий", "тонкий", "лёгкий", "обычный", "средний", "полужирный", "жирный", "плотный", "чёрный"]
        return names[min(max(block.style.weight, 0), names.count - 1)]
    }
}
