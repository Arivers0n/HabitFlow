import SwiftUI

/// Фон всего приложения. Тёмный по умолчанию, с мягким свечением акцента —
/// на нём хорошо читается стекло карточек.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ap = Appearance.shared
        let accent = ap.accent
        ZStack {
            base(ap.s.background)
            switch ap.s.background {
            case .deep:
                glow(accent, x: 0.15, y: -0.05, size: 1.1, opacity: scheme == .dark ? 0.32 : 0.18)
                glow(Color(hex: "9B6BFF"), x: 0.95, y: 0.25, size: 0.8, opacity: scheme == .dark ? 0.16 : 0.1)
            case .midnight:
                glow(Color(hex: "3A4BFF"), x: 0.5, y: -0.1, size: 1.3, opacity: 0.35)
                glow(accent, x: 0.9, y: 0.9, size: 0.9, opacity: 0.16)
            case .aurora:
                AuroraLayer(accent: accent, dark: scheme == .dark)
            case .graphite:
                glow(accent, x: 0.0, y: 0.0, size: 1.0, opacity: scheme == .dark ? 0.14 : 0.1)
            case .oled:
                EmptyView()
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func base(_ style: BackgroundStyle) -> some View {
        if scheme == .light {
            switch style {
            case .oled: Color.white
            case .graphite: Color(hex: "EEEFF2")
            default: LinearGradient(colors: [Color(hex: "F4F6FB"), Color(hex: "E9ECF5")], startPoint: .top, endPoint: .bottom)
            }
        } else {
            switch style {
            case .deep: LinearGradient(colors: [Color(hex: "0B0D14"), Color(hex: "05060A")], startPoint: .top, endPoint: .bottom)
            case .midnight: LinearGradient(colors: [Color(hex: "0A1030"), Color(hex: "04061A")], startPoint: .top, endPoint: .bottom)
            case .aurora: Color(hex: "06070D")
            case .graphite: LinearGradient(colors: [Color(hex: "1C1D21"), Color(hex: "121316")], startPoint: .top, endPoint: .bottom)
            case .oled: Color.black
            }
        }
    }

    private func glow(_ color: Color, x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double) -> some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height) * size
            Circle()
                .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: d)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
        .allowsHitTesting(false)
    }
}

/// Медленно плывущие цветные пятна (период ≈ 28 с). Без анимации, если движение выключено.
///
/// Раньше: `repeatForever` на частоте дисплея (до 120 Гц) + `.blur(60)` на весь экран. Под стеклянными
/// карточками это заставляло GPU каждый кадр пересчитывать размытие фона под каждой карточкой.
/// Теперь: пятна — радиальные градиенты (размытие не нужно), кадры — 15 в секунду. Движение медленнее
/// ~8 pt/с, шаг на кадр меньше 1 pt, глазом разницы не видно, а нагрузка в разы ниже.
private struct AuroraLayer: View {
    var accent: Color
    var dark: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !Motion.enabled)) { ctx in
            let t = Motion.enabled ? ctx.date.timeIntervalSinceReferenceDate : 0
            // 0 → 1 → 0, плавно в обе стороны (как раньше easeInOut + autoreverses)
            let k = CGFloat((1 - cos(t * 2 * Double.pi / 28)) / 2)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    blob(accent, d: w * 1.1)
                        .offset(x: mix(w * 0.05, -w * 0.25, k), y: mix(-h * 0.2, -h * 0.32, k))
                    blob(Color(hex: "2ECFC4"), d: w * 0.9)
                        .offset(x: mix(w * 0.15, w * 0.3, k), y: mix(-h * 0.18, -h * 0.05, k))
                    blob(Color(hex: "B65CFF"), d: w * 0.8)
                        .offset(x: mix(-w * 0.3, -w * 0.1, k), y: mix(h * 0.15, h * 0.3, k))
                }
                .frame(width: w, height: h)
                .opacity(dark ? 0.55 : 0.35)
            }
        }
        .allowsHitTesting(false)
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat { a + (b - a) * k }

    /// Мягкое пятно: плотная середина и плавный спад к краю — как размытый круг, но без фильтра размытия.
    private func blob(_ c: Color, d: CGFloat) -> some View {
        let r = d * 0.65
        return Circle()
            .fill(RadialGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: c, location: 0),
                    Gradient.Stop(color: c.opacity(0.7), location: 0.4),
                    Gradient.Stop(color: c.opacity(0), location: 1)
                ]),
                center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
    }
}
