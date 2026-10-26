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

/// Медленно плывущие цветные пятна. Без анимации, если движение выключено.
private struct AuroraLayer: View {
    var accent: Color
    var dark: Bool
    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                blob(accent, d: w * 1.1).offset(x: phase ? -w * 0.25 : w * 0.05, y: phase ? -h * 0.32 : -h * 0.2)
                blob(Color(hex: "2ECFC4"), d: w * 0.9).offset(x: phase ? w * 0.3 : w * 0.15, y: phase ? -h * 0.05 : -h * 0.18)
                blob(Color(hex: "B65CFF"), d: w * 0.8).offset(x: phase ? -w * 0.1 : -w * 0.3, y: phase ? h * 0.3 : h * 0.15)
            }
            .frame(width: w, height: h)
            .blur(radius: 60)
            .opacity(dark ? 0.55 : 0.35)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard Motion.enabled else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private func blob(_ c: Color, d: CGFloat) -> some View {
        Circle().fill(c).frame(width: d, height: d)
    }
}
