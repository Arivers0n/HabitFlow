import SwiftUI

// MARK: - Карточка: стекло / сплошная / контур

struct CardBackground: ViewModifier {
    var radius: CGFloat = 26
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch Appearance.shared.s.cardStyle {
        case .glass:
            glass(content, shape)
        case .solid:
            content
                .background(shape.fill(scheme == .dark ? Color(white: 0.11) : Color.white))
                .overlay(shape.fill((tint ?? .clear).opacity(scheme == .dark ? 0.07 : 0.05)).allowsHitTesting(false))
                .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.06 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 12, y: 4)
        case .outline:
            content
                .background(shape.fill(Color.primary.opacity(0.025)))
                .overlay(shape.strokeBorder((tint ?? .primary).opacity(0.35), lineWidth: 1.2))
        }
    }

    @ViewBuilder
    private func glass(_ content: Content, _ shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint.opacity(0.14)), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            materialGlass(content, shape)
        }
        #else
        materialGlass(content, shape)
        #endif
    }

    private func materialGlass(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.fill((tint ?? .clear).opacity(0.08)).allowsHitTesting(false))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.16 : 0.5), .white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
                .allowsHitTesting(false)
            )
    }
}

extension View {
    func card(radius: CGFloat = 26, tint: Color? = nil) -> some View {
        modifier(CardBackground(radius: radius, tint: tint))
    }
}

// MARK: - Кнопки

/// Лёгкое «вдавливание» при нажатии.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Главная кнопка экрана: крупная, во всю ширину, под большой палец.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.35), radius: 14, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Кольцо прогресса

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
        }
    }
}

// MARK: - Значок привычки

struct HabitIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if symbol.isSingleEmoji {
                Text(symbol).font(.system(size: size * 0.52))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.35), radius: size * 0.18, y: size * 0.08)
    }
}

extension String {
    var isSingleEmoji: Bool {
        count == 1 && (unicodeScalars.first?.properties.isEmojiPresentation ?? false
                       || unicodeScalars.count > 1)
    }
}

// MARK: - Чипы и раскладка в строки

struct Chip: View {
    var title: String
    var symbol: String? = nil
    var selected: Bool
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.subheadline) }
            Text(title).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            Capsule().fill(selected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
        )
        .overlay(Capsule().strokeBorder(selected ? .clear : Color.primary.opacity(0.08)))
        .contentShape(Capsule())
    }
}

/// Раскладывает элементы строками с переносом — для чипов.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Мелкие блоки

struct StatTile: View {
    var value: String
    var caption: String
    var symbol: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(radius: 22)
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Карточка-пустышка с призывом к действию.
struct EmptyStateCard: View {
    var symbol: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .card()
    }
}
