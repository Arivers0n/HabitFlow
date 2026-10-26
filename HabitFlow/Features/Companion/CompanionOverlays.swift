import SwiftUI

// MARK: - Новый уровень

struct LevelUpView: View {
    let event: LevelUpEvent
    let status: CompanionStatus
    var onClose: () -> Void
    @State private var appear = false

    var body: some View {
        let tint = Color(hex: status.character.tintHex)
        var config = SceneConfig.from(status)
        config.mood = .happy
        config.isNight = false
        return ZStack {
            Rectangle().fill(.black.opacity(0.6)).ignoresSafeArea().onTapGesture(perform: onClose)
            if Motion.enabled {
                Confetti(colors: [tint, .white, Color(hex: "FFD60A"), Appearance.shared.accent])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 14) {
                CompanionScene(config: config, size: 230)
                    .scaleEffect(appear ? 1 : 0.6)
                Text(event.hatched ? "\(status.character.name) вылупился!" : "Уровень \(event.level)!")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                if let st = event.stageChanged, !event.hatched {
                    Text("Новая стадия: \(st.title.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                if !event.gifts.isEmpty {
                    VStack(spacing: 8) {
                        Text("Подарки").font(.subheadline).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(event.gifts) { g in
                                Label(g.title, systemImage: g.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(Capsule().fill(tint.gradient))
                            }
                        }
                    }
                } else if event.hatched {
                    Text("Теперь он будет расти от каждой твоей привычки.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Ура!", action: onClose)
                    .buttonStyle(PrimaryButtonStyle(color: tint))
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .card(radius: 32, tint: tint)
            .padding(20)
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(Motion.bouncy ?? .default) { appear = true } }
    }
}

// MARK: - «Устоял перед искушением»

/// Короткая сцена: напарник расправляется с искушением своей суперсилой.
/// Всё движение считается от времени старта, без цепочек анимаций — стабильно и без рывков.
struct ResistView: View {
    let event: ResistEvent
    let character: CompanionCharacter?
    var onClose: () -> Void

    @State private var start = Date.now

    private var power: CompanionPower { character?.power ?? .light }
    private var tint: Color { Color(hex: character?.tintHex ?? "34C759") }

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.65)).ignoresSafeArea().onTapGesture(perform: onClose)

            VStack(spacing: 18) {
                TimelineView(.animation(paused: !Motion.enabled)) { ctx in
                    let t = Motion.enabled ? ctx.date.timeIntervalSince(start) : 3
                    stage(t: t)
                }
                .frame(width: 320, height: 230)

                TimelineView(.periodic(from: start, by: 0.2)) { ctx in
                    let shown = !Motion.enabled || ctx.date.timeIntervalSince(start) > 1.5
                    VStack(spacing: 8) {
                        Text("Искушение побеждено!")
                            .font(.title2.weight(.bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(event.xp > 0 ? "+\(event.xp) XP" : "Отмечено · опыт за сегодня уже получен")
                            .font(event.xp > 0 ? .headline : .footnote.weight(.semibold))
                            .foregroundStyle(event.xp > 0 ? tint : .secondary)
                            .padding(.top, 2)
                        Button("Дальше", action: onClose)
                            .buttonStyle(PrimaryButtonStyle(color: tint))
                            .padding(.top, 8)
                    }
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)
                    .animation(Motion.smooth, value: shown)
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .card(radius: 32, tint: tint)
            .padding(20)
        }
        .onAppear { start = .now }
    }

    private var subtitle: String {
        let who = character.map { CompanionManager.shared.displayName.isEmpty ? $0.name : CompanionManager.shared.displayName } ?? "Ты"
        let line = CompanionPhrases.resistedLine(name: CompanionManager.shared.state.userName,
                                                 strict: Appearance.shared.s.tone == .strict,
                                                 seed: event.id.hashValue)
        return "\(who) \(power.verb) «\(event.habitName)». \(line)"
    }

    // MARK: - Сцена

    @ViewBuilder
    private func stage(t: Double) -> some View {
        let W: CGFloat = 320, H: CGFloat = 230
        let from = CGPoint(x: W * 0.24, y: H * 0.58)
        let to = CGPoint(x: W * 0.76, y: H * 0.5)
        let hop = t < 0.45 ? sin(.pi * t / 0.45) : 0
        let q = clamp((t - 0.4) / 0.6)          // полёт снаряда
        let d = clamp((t - 1.0) / 0.8)          // разрушение
        let iconColor = Color(hex: event.colorHex)

        ZStack {
            // Напарник
            Group {
                if let c = character {
                    Image(c.imageName).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "shield.lefthalf.filled").resizable().scaledToFit()
                        .foregroundStyle(Palette.success.gradient).padding(16)
                }
            }
            .frame(width: 120, height: 130)
            .shadow(color: tint.opacity(0.5), radius: 12)
            .scaleEffect(x: 1 - 0.06 * hop, y: 1 + 0.08 * hop, anchor: .bottom)
            .position(x: from.x, y: from.y - CGFloat(hop) * 24)

            // Снаряд или луч
            projectile(q: q, from: from, to: to, t: t)

            // Искушение
            iconView(d: d, t: t, color: iconColor)
                .position(iconPosition(d: d, to: to))

            // Частицы разрушения
            if d > 0 && d < 1 {
                Particles(d: d, center: to, style: power)
            }
        }
        .frame(width: W, height: H)
    }

    private func iconPosition(d: Double, to: CGPoint) -> CGPoint {
        switch power {
        case .bubble: return CGPoint(x: to.x, y: to.y - CGFloat(d * d) * 160)
        case .rocket: return CGPoint(x: to.x + CGFloat(d) * 20, y: to.y - CGFloat(d * d) * 260)
        default: return to
        }
    }

    @ViewBuilder
    private func iconView(d: Double, t: Double, color: Color) -> some View {
        let base = HabitIcon(symbol: event.symbol, color: color, size: 70)
            .overlay {
                // Перечёркивание до удара
                Capsule().fill(Palette.danger).frame(width: 84, height: 6).rotationEffect(.degrees(-35))
                    .opacity(d > 0 ? 0 : 0.85)
            }
        switch power {
        case .fire:
            base.colorMultiply(Color(hex: "FF9A5A").opacity(1)).saturation(1 - d)
                .scaleEffect(1 - 0.7 * d).opacity(1 - d)
        case .laser, .ice:
            base.overlay(RoundedRectangle(cornerRadius: 21).fill(power == .ice ? Color(hex: "BFEFFF").opacity(0.7 * min(1, d * 4)) : .clear))
                .opacity(d > 0.25 ? 0 : 1)
        case .bubble:
            base.overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                .background(Circle().fill(Color(hex: "8EE6FF").opacity(0.2))).frame(width: 110, height: 110)
                .opacity(d > 0 ? 1 : 0))
                .opacity(d > 0.9 ? 0 : 1)
        case .nature:
            ZStack {
                base.scaleEffect(1 - d).opacity(1 - d)
                Image(systemName: "leaf.fill").font(.system(size: 44))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "8FD14F"), Color(hex: "3DBE6E")], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(d).opacity(d)
            }
        case .light:
            ZStack {
                Circle().fill(Color.white).frame(width: 140, height: 140).blur(radius: 20)
                    .scaleEffect(0.3 + d).opacity(d > 0 ? (1 - d) : 0)
                base.opacity(1 - d).brightness(d)
            }
        case .poof:
            base.scaleEffect(1 - d * 0.8).rotationEffect(.degrees(d * 120)).opacity(1 - d)
        case .rocket:
            base.overlay(alignment: .bottom) {
                Image(systemName: "flame.fill").font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "FFE27A"), Color(hex: "FF6A2A")], startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees(180))
                    .offset(y: 30)
                    .opacity(d > 0 ? 1 : 0)
            }
            .opacity(d > 0.85 ? 0 : 1)
        case .party:
            base.scaleEffect(d < 0.2 ? 1 + d * 1.5 : max(0, 1.3 - (d - 0.2) * 2.5)).opacity(d > 0.7 ? 0 : 1)
        }
    }

    @ViewBuilder
    private func projectile(q: Double, from: CGPoint, to: CGPoint, t: Double) -> some View {
        let active = q > 0 && q < 1
        switch power {
        case .laser:
            Path { path in
                path.move(to: CGPoint(x: from.x + 40, y: from.y - 40))
                path.addLine(to: CGPoint(x: from.x + 40 + (to.x - from.x - 40) * min(1, q * 1.6), y: from.y - 40 + (to.y - from.y + 40) * min(1, q * 1.6)))
            }
            .stroke(LinearGradient(colors: [Color(hex: "5AD8FF"), Color(hex: "FF4D6D")], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 4 + 2 * sin(t * 40), lineCap: .round))
            .shadow(color: Color(hex: "FF4D6D"), radius: 8)
            .opacity(q > 0 && t < 1.3 ? 1 : 0)
        case .rocket, .poof, .light:
            EmptyView()
        default:
            let look = projectileLook
            ForEach(0..<3, id: \.self) { i in
                let lag = Double(i) * 0.12
                let qi = clamp((q - lag) / (1 - lag))
                Image(systemName: look.symbol)
                    .font(.system(size: 26 - CGFloat(i) * 5, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: look.colors, startPoint: .top, endPoint: .bottom))
                    .shadow(color: look.colors[1].opacity(0.7), radius: 6)
                    .rotationEffect(.degrees(t * 200))
                    .position(x: from.x + 50 + (to.x - from.x - 50) * qi,
                              y: from.y - 30 + (to.y - from.y + 30) * qi - CGFloat(sin(.pi * qi)) * 30)
                    .opacity(active && qi > 0 ? 1 : 0)
            }
        }
    }

    private var projectileLook: (symbol: String, colors: [Color]) {
        switch power {
        case .fire: return ("flame.fill", [Color(hex: "FFE27A"), Color(hex: "FF5A2A")])
        case .ice: return ("snowflake", [Color.white, Color(hex: "7FD8FF")])
        case .bubble: return ("circle", [Color.white, Color(hex: "8EE6FF")])
        case .nature: return ("leaf.fill", [Color(hex: "B8F5A0"), Color(hex: "3DBE6E")])
        default: return ("sparkles", [Color(hex: "FFE27A"), Color(hex: "FF8FB8")])
        }
    }

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// Частицы разрушения в стиле суперсилы.
private struct Particles: View {
    let d: Double
    let center: CGPoint
    let style: CompanionPower

    var body: some View {
        Canvas { ctx, _ in
            let n = style == .party ? 26 : 16
            for i in 0..<n {
                let fi = Double(i)
                let angle = fi / Double(n) * 2 * .pi + fi * 0.37
                let speed = 60 + (fi * 37).truncatingRemainder(dividingBy: 50)
                var x = center.x + CGFloat(cos(angle) * speed * d)
                var y = center.y + CGFloat(sin(angle) * speed * d)
                let alpha = 1 - d
                let color: Color
                var size: CGFloat = 6
                switch style {
                case .fire:
                    x = center.x + CGFloat(cos(angle) * 30 * d)
                    y = center.y - CGFloat(speed * 1.4 * d) + CGFloat(fi.truncatingRemainder(dividingBy: 5) * 4)
                    color = i % 2 == 0 ? Color(hex: "FFB340") : Color(hex: "FF5A2A")
                    size = 5
                case .laser:
                    color = i % 2 == 0 ? Color(hex: "5AD8FF") : Color(hex: "C9D2E6")
                    size = 8
                case .ice:
                    color = i % 2 == 0 ? .white : Color(hex: "8EE6FF")
                    size = 7
                case .nature:
                    color = Color(hex: "8FD14F")
                case .bubble, .light:
                    color = .white
                    size = 4
                case .poof:
                    color = Color(white: 0.85)
                    size = 18 * CGFloat(d) + 6
                    y -= 10
                case .rocket:
                    color = Color(hex: "FFB340")
                    size = 5
                case .party:
                    let palette = ["FF6B6B", "FFE27A", "3DDC97", "5AC8FA", "B65CFF"]
                    color = Color(hex: palette[i % palette.count])
                    y += CGFloat(d * d * 80)
                }
                let rect = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
                var c = ctx
                c.opacity = alpha
                switch style {
                case .laser, .ice, .party:
                    c.translateBy(x: rect.midX, y: rect.midY)
                    c.rotate(by: .radians(angle + d * 6))
                    c.fill(Path(CGRect(x: -size / 2, y: -size / 2, width: size, height: size * (style == .party ? 0.5 : 1))), with: .color(color))
                default:
                    c.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
