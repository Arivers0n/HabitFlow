import SwiftUI
import UIKit
import WidgetKit

// Рендерер виджетов. Файл входит и в приложение, и в расширение: конструктор показывает ровно то,
// что потом нарисует система. Логика — в Domain (WidgetContent), здесь только отрисовка готовых значений.
// Выражения держим мелкими и типизированными, чтобы компилятор не уходил в «unable to type-check».

// MARK: - Стиль → SwiftUI

private func widgetColor(_ hex: String, opacity: Double = 1) -> Color {
    let c = HexColor.rgb(hex)
    return Color(red: c.r, green: c.g, blue: c.b).opacity(opacity)
}

extension WidgetTextStyle {
    var fontWeight: Font.Weight {
        let all: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        return all[min(max(weight, 0), all.count - 1)]
    }

    var fontDesign: Font.Design {
        switch design {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    func font(scale: Double = 1) -> Font {
        Font.system(size: size * scale, weight: fontWeight, design: fontDesign)
    }

    var color: Color { widgetColor(colorHex, opacity: opacity) }

    var textAlignment: TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontal: HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

extension WidgetAlign {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Фон

struct WidgetBackgroundView: View {
    let background: WidgetBackground

    var body: some View {
        let a = widgetColor(background.colorA, opacity: background.opacity)
        let b = widgetColor(background.colorB, opacity: background.opacity)
        switch background.kind {
        case .solid:
            a
        case .gradient:
            LinearGradient(colors: [a, b], startPoint: start, endPoint: end)
        }
    }

    private var radians: Double { background.angle * .pi / 180 }
    private var start: UnitPoint {
        UnitPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2)
    }
    private var end: UnitPoint {
        UnitPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
    }
}

// MARK: - Один блок

struct WidgetBlockView: View {
    let block: WidgetBlock
    let value: WidgetValue
    var petImage: UIImage?
    /// Экран блокировки: кольцо превращается в короткую полоску.
    var compact = false

    private var style: WidgetTextStyle { block.style }

    var body: some View {
        switch value {
        case .text(let t):
            textView(t)
        case .stat(let v, let caption):
            statView(v, caption)
        case .ring(let f, let center, let caption):
            if compact { compactRing(f, center) } else { ringView(f, center, caption) }
        case .bar(let f, let label):
            barView(f, label)
        case .dots(let d):
            dotsView(d)
        case .lines(let l):
            linesView(l)
        case .pet(let stage, _, let name):
            petView(stage, name)
        }
    }

    // Текст

    private func styled(_ s: String, scale: Double = 1) -> some View {
        Text(s)
            .font(style.font(scale: scale))
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
            .foregroundStyle(style.color)
            .multilineTextAlignment(style.textAlignment)
            .minimumScaleFactor(0.6)
    }

    private func textView(_ t: String) -> some View {
        styled(t)
            .lineLimit(style.lineLimit)
            .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    private func statView(_ v: String, _ caption: String) -> some View {
        VStack(alignment: style.horizontal, spacing: 1) {
            styled(v).lineLimit(style.lineLimit)
            if block.showCaption {
                styled(caption, scale: block.captionScale).opacity(0.8).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    private func linesView(_ lines: [String]) -> some View {
        let shown = Array(lines.prefix(max(1, style.lineLimit)))
        return VStack(alignment: style.horizontal, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                styled(line).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    // Кольцо

    private func ringView(_ f: Double, _ center: String, _ caption: String) -> some View {
        ZStack {
            Circle()
                .stroke(widgetColor(block.trackHex, opacity: block.trackOpacity), lineWidth: block.thickness)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, f)))
                .stroke(widgetColor(block.accentHex),
                        style: StrokeStyle(lineWidth: block.thickness, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                styled(center).lineLimit(1)
                if block.showCaption {
                    styled(caption, scale: block.captionScale).opacity(0.8).lineLimit(1)
                }
            }
            .padding(block.thickness + 2)
        }
        .padding(block.thickness / 2)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.frameAlignment)
    }

    private func compactRing(_ f: Double, _ center: String) -> some View {
        HStack(spacing: 6) {
            styled(center).lineLimit(1)
            bar(f)
        }
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    // Полоска

    private func bar(_ f: Double) -> some View {
        let h = max(4, block.thickness * 0.6)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(widgetColor(block.trackHex, opacity: block.trackOpacity))
                Capsule().fill(widgetColor(block.accentHex))
                    .frame(width: geo.size.width * max(0, min(1, f)))
            }
        }
        .frame(height: h)
    }

    private func barView(_ f: Double, _ label: String) -> some View {
        VStack(alignment: style.horizontal, spacing: 3) {
            styled(label).lineLimit(1)
            bar(f)
        }
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    // Неделя

    private static let letters = ["П", "В", "С", "Ч", "П", "С", "В"]

    private func dotColor(_ d: WidgetDot) -> Color {
        switch d {
        case .done: return widgetColor(block.accentHex)
        case .partial: return widgetColor(block.accentHex, opacity: 0.5)
        case .missed: return widgetColor(block.trackHex, opacity: min(1, block.trackOpacity * 2))
        case .today, .future, .none: return widgetColor(block.trackHex, opacity: block.trackOpacity)
        }
    }

    private func dotView(_ d: WidgetDot, index: Int) -> some View {
        let size = min(18.0, max(6.0, block.thickness))
        return VStack(spacing: 2) {
            Circle()
                .fill(dotColor(d))
                .overlay(Circle().stroke(widgetColor(block.accentHex), lineWidth: d == .today ? 1.5 : 0))
                .frame(width: size, height: size)
            if block.showCaption {
                Text(Self.letters[index % 7])
                    .font(style.font(scale: block.captionScale))
                    .foregroundStyle(style.color.opacity(0.8))
            }
        }
    }

    private func dotsView(_ dots: [WidgetDot]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(dots.enumerated()), id: \.offset) { i, d in
                dotView(d, index: i)
            }
        }
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
    }

    // Питомец

    private func stageEmoji(_ stage: String) -> String {
        switch stage {
        case "Яйцо": return "🥚"
        case "Малыш": return "🐣"
        case "Подросток": return "🐾"
        default: return "⭐️"
        }
    }

    private func petView(_ stage: String, _ name: String) -> some View {
        VStack(spacing: 2) {
            if let img = petImage, stage != "Яйцо" {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(stageEmoji(stage))
                    .font(.system(size: style.size * 2))
                    .minimumScaleFactor(0.4)
            }
            if block.showCaption {
                styled(name, scale: block.captionScale).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.frameAlignment)
    }
}

// MARK: - Рабочий стол

private struct ResolvedBlock: Identifiable {
    let block: WidgetBlock
    let value: WidgetValue
    var id: UUID { block.id }
}

struct WidgetDesignView: View {
    let design: WidgetDesign
    let snapshot: WidgetSnapshot
    var now: Date = .now
    var petImage: UIImage?

    private var items: [ResolvedBlock] {
        design.blocks.map { b in
            ResolvedBlock(block: b, value: WidgetContent.value(for: b, snapshot: snapshot, now: now))
        }
    }

    var body: some View {
        content
            .padding(design.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        let list = items
        switch design.layout {
        case .stack:
            stack(list)
        case .leadingFeature:
            leadingFeature(list)
        case .topFeature:
            topFeature(list)
        }
    }

    private func cell(_ item: ResolvedBlock) -> some View {
        WidgetBlockView(block: item.block, value: item.value, petImage: petImage)
            .padding(.bottom, item.block.spaceAfter)
    }

    private func stack(_ list: [ResolvedBlock]) -> some View {
        VStack(alignment: design.align.horizontal, spacing: 0) {
            ForEach(list) { item in cell(item) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: design.align.frame)
    }

    private func leadingFeature(_ list: [ResolvedBlock]) -> some View {
        HStack(spacing: design.spacing) {
            if let first = list.first { cell(first) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.dropFirst())) { item in cell(item) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func topFeature(_ list: [ResolvedBlock]) -> some View {
        VStack(alignment: .leading, spacing: design.spacing) {
            if let first = list.first { cell(first) }
            ForEach(Array(list.dropFirst())) { item in cell(item) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Экран блокировки

struct WidgetLockView: View {
    let design: WidgetDesign
    let snapshot: WidgetSnapshot
    var now: Date = .now
    /// В виджете подложку рисует система, в предпросмотре — мы.
    var systemBackground = false

    private var first: WidgetBlock? { design.blocks.first }

    private func value(_ b: WidgetBlock) -> WidgetValue {
        WidgetContent.value(for: b, snapshot: snapshot, now: now)
    }

    var body: some View {
        switch design.family {
        case .lockCircular: circular
        case .lockInline: inline
        default: rectangular
        }
    }

    // Круг: кольцо с числом либо просто короткий текст.
    @ViewBuilder
    private var circular: some View {
        ZStack {
            circleBackground
            if let b = first {
                circleContent(b, value(b))
            }
        }
    }

    @ViewBuilder
    private var circleBackground: some View {
        if systemBackground {
            AccessoryWidgetBackground()
        } else {
            Circle().fill(Color.white.opacity(0.18))
        }
    }

    @ViewBuilder
    private func circleContent(_ b: WidgetBlock, _ v: WidgetValue) -> some View {
        if case .ring(let f, let center, _) = v {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: b.thickness)
                Circle().trim(from: 0, to: max(0.001, min(1, f)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: b.thickness, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(center)
                    .font(b.style.font())
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.white)
                    .padding(b.thickness + 2)
            }
            .padding(design.padding + b.thickness / 2)
        } else {
            Text(WidgetContent.plainText(v))
                .font(b.style.font())
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white)
                .padding(design.padding + 4)
        }
    }

    // Строка: только текст.
    private var inline: some View {
        let text = first.map { WidgetContent.plainText(value($0)) } ?? ""
        return Text(text)
            .font(first?.style.font() ?? .body)
            .foregroundStyle(Color.white)
            .lineLimit(1)
    }

    // Прямоугольник: до трёх строк.
    private var rectangular: some View {
        ZStack(alignment: .topLeading) {
            rectBackground
            VStack(alignment: .leading, spacing: design.spacing) {
                ForEach(design.blocks) { b in
                    rectRow(b)
                }
            }
            .padding(design.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var rectBackground: some View {
        if systemBackground {
            AccessoryWidgetBackground().clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.18))
        }
    }

    private func rectRow(_ b: WidgetBlock) -> some View {
        var white = b
        white.style.colorHex = "FFFFFF"
        white.style.opacity = 1
        white.accentHex = "FFFFFF"
        white.trackHex = "FFFFFF"
        return WidgetBlockView(block: white, value: value(b), petImage: nil, compact: true)
    }
}

// MARK: - Предпросмотр в приложении

/// Виджет любого размера в рамке нужного размера — для конструктора.
struct WidgetPreviewView: View {
    let design: WidgetDesign
    let snapshot: WidgetSnapshot
    var now: Date = .now
    var petImage: UIImage?

    var body: some View {
        let size = design.family.previewSize
        Group {
            if design.family.isLockScreen {
                lockPreview(size)
            } else {
                desktopPreview(size)
            }
        }
    }

    private func desktopPreview(_ size: (width: Double, height: Double)) -> some View {
        WidgetDesignView(design: design, snapshot: snapshot, now: now, petImage: petImage)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackgroundView(background: design.background))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func lockPreview(_ size: (width: Double, height: Double)) -> some View {
        WidgetLockView(design: design, snapshot: snapshot, now: now)
            .frame(width: size.width, height: size.height)
            .padding(10)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
