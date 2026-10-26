import SwiftUI

/// Что показывать в сцене. Собирается из статуса напарника или задаётся вручную (превью, онбординг).
struct SceneConfig: Equatable {
    var character: CompanionCharacter
    var stage: CompanionStage = .adult
    var mood: CompanionMood = .calm
    var isNight = false
    var eggProgress: Double = 0
    var headwear: String? = nil
    var aura: String? = nil
    var decor: Set<String> = []
    var showIsland = true

    @MainActor
    static func from(_ s: CompanionStatus) -> SceneConfig {
        let manager = CompanionManager.shared
        return SceneConfig(character: s.character, stage: s.stage, mood: s.mood, isNight: s.isNight,
                    eggProgress: s.stage == .egg ? s.progress.fraction : 0,
                    headwear: s.stage == .egg ? nil : manager.state.headwear,
                    aura: s.stage == .egg ? nil : manager.state.aura,
                    decor: manager.visibleDecor(level: s.level))
    }
}

/// Живая сцена: персонаж на стеклянном островке, свечение, украшения и эффекты настроения.
/// Вся анимация считается от времени в TimelineView — без накапливающихся состояний,
/// поэтому ничего не «залипает» и не дёргается при перерисовке.
struct CompanionScene: View {
    var config: SceneConfig
    var size: CGFloat
    var interactive = true
    var onTap: (() -> Void)? = nil

    @State private var tapStart: Date?
    @State private var tapCount = 0

    private var tint: Color { Color(hex: config.character.tintHex) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: !Motion.enabled)) { ctx in
            layers(t: ctx.date.timeIntervalSinceReferenceDate, now: ctx.date)
        }
        .frame(width: size, height: size * 0.92)
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactive else { return }
            tapCount += 1
            tapStart = .now
            Haptics.tap()
            if tapCount % 3 == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Haptics.soft() }
            }
            onTap?()
        }
        .accessibilityElement()
        .accessibilityLabel("\(config.character.name), \(config.mood.title.lowercased())")
        .accessibilityAddTraits(interactive ? .isButton : [])
    }

    private func layers(t: Double, now: Date) -> some View {
        let W: CGFloat = size
        let H: CGFloat = size * 0.92
        let g = SceneGeometry(W: W, H: H, stage: config.stage, aspect: config.character.aspect)
        let m = motion(t: t, now: now, g: g)
        return ZStack {
            backLayers(g: g, t: t)
            shadow(g: g, m: m)
            AuraLayer(aura: config.aura, t: t, g: g, back: true)
            characterLayer(g: g, t: t, m: m)
            AuraLayer(aura: config.aura, t: t, g: g, back: false)
            headwearLayer(g: g, t: t, m: m)
            if config.showIsland {
                DecorLayer(decor: config.decor, back: false, g: g, t: t, mood: config.mood)
            }
            MoodEffects(mood: config.mood, isNight: config.isNight && config.mood != .caring,
                        t: t, g: g, stage: config.stage)
        }
        .frame(width: W, height: H)
    }

    @ViewBuilder
    private func backLayers(g: SceneGeometry, t: Double) -> some View {
        let glowOpacity: Double = config.mood == .sad ? 0.22 : 0.45
        let pulse: CGFloat = 1 + 0.04 * CGFloat(sin(t * 0.9))
        let glowY: CGFloat = g.feetY - g.charH * 0.55
        Circle()
            .fill(RadialGradient(colors: [glowColor.opacity(glowOpacity), glowColor.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: g.W * 0.5))
            .frame(width: g.W, height: g.W)
            .scaleEffect(pulse)
            .position(x: g.W / 2, y: glowY)

        if config.decor.contains("moon") {
            SkyMoon(t: t)
                .frame(width: g.W * 0.16, height: g.W * 0.16)
                .position(x: g.W * 0.14, y: g.H * 0.14)
        }
        if config.aura == "rainbow" && config.stage != .egg {
            let rainbowY: CGFloat = g.islandY - g.charH * 0.45
            RainbowArc()
                .frame(width: g.W * 0.82, height: g.W * 0.41)
                .opacity(0.55 + 0.15 * sin(t * 0.7))
                .position(x: g.W / 2, y: rainbowY)
        }
        if config.showIsland {
            let islandH: CGFloat = g.islandW * 0.5
            let islandCenter: CGFloat = g.islandY + g.islandW * 0.12
            Island(tint: tint, stage: config.stage)
                .frame(width: g.islandW, height: islandH)
                .position(x: g.W / 2, y: islandCenter)
            DecorLayer(decor: config.decor, back: true, g: g, t: t, mood: config.mood)
        }
    }

    private func shadow(g: SceneGeometry, m: Motion3) -> some View {
        let w: CGFloat = g.charW * 0.62 * (1 - m.lift * 0.35)
        let h: CGFloat = g.islandW * 0.07
        return Ellipse()
            .fill(Color.black.opacity(0.28))
            .frame(width: w, height: h)
            .blur(radius: 3)
            .position(x: g.W / 2, y: g.feetY)
    }

    private func characterLayer(g: SceneGeometry, t: Double, m: Motion3) -> some View {
        let sad = config.mood == .sad
        let y: CGFloat = g.feetY - g.charH / 2 + m.dy
        return character(g: g, t: t)
            .scaleEffect(x: m.sx, y: m.sy, anchor: .bottom)
            .rotationEffect(.degrees(m.tilt), anchor: .bottom)
            .rotation3DEffect(.degrees(m.flip), axis: (x: 0, y: 1, z: 0))
            .saturation(sad ? 0.75 : 1)
            .brightness(sad ? -0.04 : 0)
            .position(x: g.W / 2, y: y)
    }

    @ViewBuilder
    private func headwearLayer(g: SceneGeometry, t: Double, m: Motion3) -> some View {
        if let hw = config.headwear {
            let x: CGFloat = g.W / 2 + CGFloat(config.character.headX - 0.5) * g.charW
            let float: CGFloat = 3 * CGFloat(sin(t * 2.1 + 1))
            let y: CGFloat = g.feetY - g.charH + m.dy - g.W * 0.07 + float
            Headwear(id: hw, t: t)
                .frame(width: g.W * 0.15, height: g.W * 0.15)
                .position(x: x, y: y)
        }
    }

    private var glowColor: Color {
        config.mood == .sad ? Color(hex: "7A86A8") : tint
    }

    @ViewBuilder
    private func character(g: SceneGeometry, t: Double) -> some View {
        if config.stage == .egg {
            EggView(tint: tint, progress: config.eggProgress, t: t)
                .frame(width: g.charH * 0.78, height: g.charH)
        } else {
            Image(config.character.imageName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: g.charW, height: g.charH)
                .shadow(color: tint.opacity(0.35), radius: 10)
        }
    }

    // MARK: - Движение

    struct Motion3 {
        var dy: CGFloat = 0
        var sx: CGFloat = 1
        var sy: CGFloat = 1
        var tilt: Double = 0
        var flip: Double = 0
        var lift: CGFloat = 0
    }

    private func motion(t: Double, now: Date, g: SceneGeometry) -> Motion3 {
        var m = Motion3()
        let sleeping = config.isNight && (config.mood == .calm || config.mood == .happy)
        let (amp, speed, squash): (Double, Double, Double) = {
            if config.stage == .egg { return (0, 1.2, 0) }
            if sleeping { return (1, 0.7, 0.02) }
            switch config.mood {
            case .happy: return (6, 2.6, 0.035)
            case .calm: return (3, 1.5, 0.02)
            case .sad: return (1.2, 0.8, 0.012)
            case .caring: return (2.2, 1.1, 0.018)
            }
        }()
        let wave = sin(t * speed)
        m.dy = CGFloat(-abs(wave) * amp)
        m.sy = CGFloat(1 + squash * wave)
        m.sx = CGFloat(1 - squash * 0.6 * wave)
        m.tilt = config.mood == .sad ? -5 : (config.mood == .happy ? 2.5 * sin(t * speed * 0.5) : 0)
        if config.stage == .egg {
            let shake = config.eggProgress > 0.75 ? 7.0 : 3.0
            m.tilt = shake * sin(t * 3) * max(0, sin(t * 0.8))
        }

        // Реакция на тап: прыжок, каждый третий — сальто
        if let start = tapStart {
            let p = now.timeIntervalSince(start) / 0.75
            if p >= 0 && p < 1 {
                let up = sin(.pi * p)
                m.dy -= CGFloat(up) * g.charH * 0.28
                m.lift = CGFloat(up)
                if p < 0.12 { m.sy *= CGFloat(1 - 0.12 * (p / 0.12)); m.sx *= CGFloat(1 + 0.08 * (p / 0.12)) }
                if p > 0.88 { let q = (p - 0.88) / 0.12; m.sy *= CGFloat(0.9 + 0.1 * q); m.sx *= CGFloat(1.06 - 0.06 * q) }
                if tapCount % 3 == 0 && config.stage != .egg {
                    let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                    m.flip = 360 * e
                }
            }
        }
        return m
    }
}

// MARK: - Геометрия сцены

struct SceneGeometry {
    let W: CGFloat, H: CGFloat
    let islandW: CGFloat
    let islandY: CGFloat
    let charH: CGFloat
    let charW: CGFloat
    let feetY: CGFloat

    init(W: CGFloat, H: CGFloat, stage: CompanionStage, aspect: Double) {
        self.W = W
        self.H = H
        let islandScale: CGFloat = [0.7, 0.8, 0.9, 1.0][stage.rawValue]
        let charScale: CGFloat = [0.5, 0.66, 0.82, 1.0][stage.rawValue]
        islandW = W * 0.86 * islandScale
        islandY = H * 0.8
        charH = H * 0.6 * charScale
        charW = stage == .egg ? charH * 0.78 : charH * CGFloat(aspect)
        feetY = islandY + islandW * 0.02
    }
}

// MARK: - Островок

struct Island: View {
    var tint: Color
    var stage: CompanionStage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let topH = w * 0.26
            ZStack(alignment: .top) {
                // Низ островка
                IslandBottom(topHeight: topH)
                    .fill(LinearGradient(colors: [tint.opacity(scheme == .dark ? 0.55 : 0.45), tint.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        IslandBottom(topHeight: topH)
                            .stroke(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    )
                // Верх — стеклянная площадка
                Ellipse()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Ellipse().fill(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.22 : 0.5), tint.opacity(0.35)],
                                                      startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(Ellipse().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.2))
                    .overlay(
                        Ellipse().fill(Color.white.opacity(0.35))
                            .frame(width: w * 0.5, height: topH * 0.18)
                            .blur(radius: 4)
                            .offset(x: -w * 0.12, y: -topH * 0.22)
                    )
                    .frame(width: w, height: topH)
                if stage == .adult {
                    Ellipse()
                        .stroke(tint, lineWidth: 2)
                        .blur(radius: 5)
                        .frame(width: w * 1.02, height: topH * 1.05)
                        .opacity(0.7)
                }
            }
        }
    }
}

private struct IslandBottom: Shape {
    var topHeight: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.minY + topHeight / 2
        p.move(to: CGPoint(x: r.minX, y: y))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.minX + r.width * 0.14, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: y), control: CGPoint(x: r.maxX - r.width * 0.14, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Яйцо

struct EggView: View {
    var tint: Color
    var progress: Double
    var t: Double

    var body: some View {
        ZStack {
            EggShape()
                .fill(LinearGradient(colors: [Color.white.opacity(0.95), tint.opacity(0.85), tint],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            EggShape()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.35, y: 0.28),
                                     startRadius: 0, endRadius: 60))
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ForEach(0..<4, id: \.self) { i in
                    let pos = [(0.3, 0.55), (0.68, 0.42), (0.58, 0.72), (0.4, 0.3)][i]
                    Circle().fill(Color.white.opacity(0.35))
                        .frame(width: w * [0.18, 0.13, 0.15, 0.1][i])
                        .position(x: w * pos.0, y: h * pos.1)
                }
                if progress > 0.45 {
                    Crack(seed: 1).stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: w * 0.36, height: h * 0.14)
                        .position(x: w * 0.42, y: h * 0.4)
                }
                if progress > 0.75 {
                    Crack(seed: 2).stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: w * 0.3, height: h * 0.12)
                        .position(x: w * 0.62, y: h * 0.58)
                }
            }
            EggShape().strokeBorderLike(Color.white.opacity(0.5))
        }
        .shadow(color: tint.opacity(0.5), radius: 14)
    }
}

struct EggShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.62),
                   control1: CGPoint(x: r.minX + w * 0.86, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.36))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.86),
                   control2: CGPoint(x: r.minX + w * 0.78, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.62),
                   control1: CGPoint(x: r.minX + w * 0.22, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.86))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.36),
                   control2: CGPoint(x: r.minX + w * 0.14, y: r.minY))
        p.closeSubpath()
        return p
    }
}

extension Shape {
    func strokeBorderLike(_ color: Color) -> some View {
        stroke(color, lineWidth: 1.2).padding(0.6)
    }
}

private struct Crack: Shape {
    var seed: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts: [(Double, Double)] = seed == 1
            ? [(0, 0.5), (0.2, 0.1), (0.4, 0.8), (0.6, 0.2), (0.8, 0.9), (1, 0.4)]
            : [(0, 0.3), (0.25, 0.9), (0.5, 0.2), (0.75, 0.85), (1, 0.5)]
        for (i, pt) in pts.enumerated() {
            let c = CGPoint(x: r.minX + r.width * pt.0, y: r.minY + r.height * pt.1)
            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
        }
        return p
    }
}

// MARK: - Украшения островка

private struct DecorLayer: View {
    var decor: Set<String>
    var back: Bool
    var g: SceneGeometry
    var t: Double
    var mood: CompanionMood

    var body: some View {
        let w = g.islandW
        let cx = g.W / 2, y = g.islandY
        ZStack {
            if back {
                if decor.contains("tree") {
                    symbol("tree.fill", size: g.W * 0.2, colors: [Color(hex: "3DDC97"), Color(hex: "1F8F55")])
                        .position(x: cx - w * 0.3, y: y - g.W * 0.08)
                } else if decor.contains("sprout") {
                    symbol("leaf.fill", size: g.W * 0.08, colors: [Color(hex: "8FD14F"), Color(hex: "3DBE6E")])
                        .rotationEffect(.degrees(-20 + 4 * sin(t * 1.3)), anchor: .bottom)
                        .position(x: cx - w * 0.3, y: y - g.W * 0.035)
                }
                if decor.contains("house") {
                    symbol("house.fill", size: g.W * 0.15, colors: [Color(hex: "FFD9A8"), Color(hex: "E08A4A")])
                        .position(x: cx + w * 0.3, y: y - g.W * 0.06)
                }
                if decor.contains("tent") {
                    symbol("tent.fill", size: g.W * 0.12, colors: [Color(hex: "FFB340"), Color(hex: "E0702A")])
                        .position(x: cx - w * 0.44, y: y - g.W * 0.02)
                }
            } else {
                if decor.contains("flowers") {
                    HStack(spacing: 2) {
                        symbol("camera.macro", size: g.W * 0.06, colors: [Color(hex: "FF8FB8"), Color(hex: "E5507E")])
                        symbol("camera.macro", size: g.W * 0.045, colors: [Color(hex: "FFD27A"), Color(hex: "F0A020")])
                            .offset(y: g.W * 0.01)
                    }
                    .rotationEffect(.degrees(3 * sin(t * 1.1)), anchor: .bottom)
                    .position(x: cx - w * 0.36, y: y + g.W * 0.03)
                }
                if decor.contains("campfire") {
                    let lit = mood != .sad
                    ZStack {
                        Circle().fill(Color.orange.opacity(lit ? 0.45 : 0)).blur(radius: 10)
                            .frame(width: g.W * 0.12)
                        symbol(lit ? "flame.fill" : "smoke.fill", size: g.W * 0.07,
                               colors: lit ? [Color(hex: "FFE27A"), Color(hex: "FF6A2A")] : [Color.gray, Color.gray.opacity(0.6)])
                            .scaleEffect(x: lit ? 1 + 0.06 * sin(t * 9) : 1, y: lit ? 1 + 0.1 * sin(t * 7 + 1) : 1, anchor: .bottom)
                    }
                    .position(x: cx + w * 0.33, y: y + g.W * 0.02)
                }
                if decor.contains("lantern") {
                    ZStack {
                        Circle().fill(Color(hex: "FFE27A").opacity(0.35 + 0.1 * sin(t * 2))).blur(radius: 8)
                            .frame(width: g.W * 0.1)
                        symbol("lightbulb.fill", size: g.W * 0.055, colors: [Color(hex: "FFF3B0"), Color(hex: "F0B020")])
                    }
                    .position(x: cx + w * 0.46, y: y - g.W * 0.01)
                }
                if mood == .caring {
                    symbol("cup.and.saucer.fill", size: g.W * 0.07, colors: [Color.white, Color(hex: "D8C2A8")])
                        .overlay(alignment: .top) {
                            Steam(t: t).frame(width: g.W * 0.05, height: g.W * 0.06).offset(y: -g.W * 0.05)
                        }
                        .position(x: cx + w * 0.22, y: y + g.W * 0.04)
                }
            }
        }
    }

    private func symbol(_ name: String, size: CGFloat, colors: [Color]) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .shadow(color: colors.last!.opacity(0.4), radius: 4, y: 2)
    }
}

private struct Steam: View {
    var t: Double
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<2 {
                let phase = (t * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                var p = Path()
                let x0 = size.width * (0.35 + 0.3 * Double(i))
                p.move(to: CGPoint(x: x0, y: size.height))
                for k in 1...6 {
                    let yy = size.height * (1 - Double(k) / 6)
                    p.addLine(to: CGPoint(x: x0 + 3 * sin(Double(k) + t * 3), y: yy))
                }
                ctx.opacity = 0.6 * (1 - phase)
                ctx.stroke(p, with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}

private struct SkyMoon: View {
    var t: Double
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "FFE27A").opacity(0.3)).blur(radius: 10)
            Image(systemName: "moon.stars.fill")
                .resizable().scaledToFit()
                .foregroundStyle(LinearGradient(colors: [Color(hex: "FFF3B0"), Color(hex: "FFC94A")], startPoint: .top, endPoint: .bottom))
                .opacity(0.85 + 0.15 * sin(t * 1.5))
        }
    }
}

private struct RainbowArc: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let colors = ["FF6B6B", "FFB340", "FFE27A", "3DDC97", "5AC8FA"]
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    let d = w - CGFloat(i) * 12
                    Circle()
                        .trim(from: 0.5, to: 1)
                        .stroke(Color(hex: colors[i]).opacity(0.7), lineWidth: 5)
                        .frame(width: d, height: d)
                        .position(x: w / 2, y: h)
                }
            }
            .blur(radius: 1.2)
        }
    }
}

// MARK: - Ауры

private struct AuraLayer: View {
    var aura: String?
    var t: Double
    var g: SceneGeometry
    var back: Bool

    var body: some View {
        let cx = g.W / 2, cy = g.feetY - g.charH * 0.5
        let rx = g.charW * 0.62 + 10, ry = g.charH * 0.32
        ZStack {
            switch aura {
            case "sparks":
                ForEach(0..<3, id: \.self) { i in
                    let a = t * 1.1 + Double(i) * 2.094
                    let front = sin(a) > 0
                    if front != back {
                        Image(systemName: "sparkle")
                            .font(.system(size: g.W * 0.05, weight: .bold))
                            .foregroundStyle(Color(hex: "FFE27A"))
                            .shadow(color: .yellow, radius: 4)
                            .scaleEffect(0.7 + 0.3 * (sin(a) + 1) / 2)
                            .position(orbit(cx: cx, cy: cy - g.charH * 0.1, rx: rx, ry: ry * 0.35, angle: a))
                    }
                }
            case "fireflies" where !back:
                ForEach(0..<7, id: \.self) { i in
                    let fi = Double(i)
                    Circle()
                        .fill(Color(hex: "D9FF8A"))
                        .frame(width: 4, height: 4)
                        .shadow(color: Color(hex: "D9FF8A"), radius: 4)
                        .opacity(0.4 + 0.6 * (sin(t * (1.3 + fi * 0.2) + fi) + 1) / 2)
                        .position(drift(cx: cx, cy: cy, rx: rx * 1.2, ry: ry * 1.1,
                                        ax: t * (0.3 + fi * 0.07) + fi * 1.7, ay: t * (0.4 + fi * 0.05) + fi))
                }
            case "hearts" where !back:
                ForEach(0..<3, id: \.self) { i in
                    let p = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Image(systemName: "heart.fill")
                        .font(.system(size: g.W * 0.045))
                        .foregroundStyle(Color(hex: "FF6B9A"))
                        .opacity(sin(.pi * p))
                        .position(rise(x: cx + (i == 1 ? -rx * 0.9 : rx * 0.9), y: cy + ry * 0.6,
                                       wobble: 6 * sin(t * 2 + Double(i)), height: g.charH * 0.7, p: p))
                }
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Над головой

private struct Headwear: View {
    var id: String
    var t: Double

    var body: some View {
        Group {
            switch id {
            case "halo":
                Ellipse()
                    .stroke(LinearGradient(colors: [Color(hex: "FFF3B0"), Color(hex: "FFC94A")], startPoint: .leading, endPoint: .trailing), lineWidth: 4)
                    .frame(height: 14)
                    .shadow(color: Color(hex: "FFD27A"), radius: 6)
                    .opacity(0.9 + 0.1 * sin(t * 2))
            case "crown":
                glyph("crown.fill", [Color(hex: "FFE58A"), Color(hex: "E3A92F")])
            case "cap":
                glyph("graduationcap.fill", [Color(hex: "4A4F66"), Color(hex: "1E2236")])
            case "comet":
                glyph("sparkles", [Color(hex: "CFF4FF"), Color(hex: "7FD8FF")])
                    .rotationEffect(.degrees(12 * sin(t * 1.4)))
            default:
                glyph("star.fill", [Color(hex: "FFE27A"), Color(hex: "FFB020")])
                    .rotationEffect(.degrees(t * 25))
            }
        }
        .rotationEffect(.degrees(4 * sin(t * 1.7)))
    }

    private func glyph(_ name: String, _ colors: [Color]) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .shadow(color: colors.last!.opacity(0.6), radius: 5)
    }
}

// MARK: - Эффекты настроения

private struct MoodEffects: View {
    var mood: CompanionMood
    var isNight: Bool
    var t: Double
    var g: SceneGeometry
    var stage: CompanionStage

    var body: some View {
        let cx = g.W / 2
        let top = g.feetY - g.charH
        ZStack {
            if stage != .egg && isNight && mood != .sad {
                // Сон: «Z» поднимаются и тают
                ForEach(0..<3, id: \.self) { i in
                    let p = (t * 0.3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Text("Z")
                        .font(.system(size: 10 + 8 * p, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "B9C6FF"))
                        .opacity(sin(.pi * p))
                        .position(rise(x: cx + g.charW * 0.35, y: top + 10, wobble: 22 * p, height: 40, p: p))
                }
            } else {
                switch mood {
                case .happy:
                    ForEach(0..<5, id: \.self) { i in
                        let fi = Double(i)
                        let a = fi * 1.256 + 0.3
                        Image(systemName: "star.fill")
                            .font(.system(size: 6 + CGFloat(i % 3) * 3))
                            .foregroundStyle(Color(hex: "FFE27A"))
                            .shadow(color: .yellow, radius: 3)
                            .opacity(max(0, sin(t * 2.2 + fi * 1.3)))
                            .position(orbit(cx: cx, cy: top + g.charH * 0.35, rx: g.charW * 0.7, ry: -g.charH * 0.45, angle: a))
                    }
                case .sad:
                    RainCloud(t: t)
                        .frame(width: g.W * 0.3, height: g.W * 0.3)
                        .position(x: cx + g.charW * 0.05, y: top - g.W * 0.04)
                case .caring:
                    ForEach(0..<2, id: \.self) { i in
                        let p = (t * 0.4 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12 + 4 * p))
                            .foregroundStyle(Color(hex: "FF8FB8"))
                            .opacity(sin(.pi * p))
                            .position(rise(x: cx - g.charW * 0.42, y: top + g.charH * 0.4,
                                           wobble: 8 * sin(t * 2 + Double(i)), height: 45, p: p))
                    }
                case .calm:
                    EmptyView()
                }
            }
        }
    }
}

private struct RainCloud: View {
    var t: Double
    var body: some View {
        ZStack(alignment: .top) {
            Canvas { ctx, size in
                for i in 0..<9 {
                    let fi = Double(i)
                    let p = (t * 1.4 + fi * 0.37).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.2 + 0.6 * ((fi * 0.618).truncatingRemainder(dividingBy: 1)))
                    let y = size.height * (0.3 + 0.65 * p)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - 1.5, y: y + 6))
                    ctx.opacity = 0.75 * (1 - p)
                    ctx.stroke(path, with: .color(Color(hex: "8EC5FF")), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
            Image(systemName: "cloud.fill")
                .resizable().scaledToFit()
                .foregroundStyle(LinearGradient(colors: [Color(hex: "C9D2E6"), Color(hex: "8C97B0")], startPoint: .top, endPoint: .bottom))
                .frame(height: 30)
                .offset(x: 2 * sin(t * 0.8))
        }
    }
}


// MARK: - Помощники координат (простые типы — быстрее для компилятора)

func orbit(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, angle: Double) -> CGPoint {
    CGPoint(x: cx + rx * CGFloat(cos(angle)), y: cy + ry * CGFloat(sin(angle)))
}

func drift(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, ax: Double, ay: Double) -> CGPoint {
    CGPoint(x: cx + rx * CGFloat(sin(ax)), y: cy + ry * CGFloat(cos(ay)))
}

func rise(x: CGFloat, y: CGFloat, wobble: Double, height: CGFloat, p: Double) -> CGPoint {
    CGPoint(x: x + CGFloat(wobble), y: y - CGFloat(p) * height)
}
