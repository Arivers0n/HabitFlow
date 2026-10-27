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

/// Как сцена отвечает на касания.
enum SceneMode {
    /// Только смотреть (онбординг, превью, окно срыва).
    case display
    /// Карточка на «Сегодня»: тап — прыжок и «желе». Не мешает прокрутке.
    case card
    /// Площадка напарника: гладить, щекотать, поднимать и бросать, кормить.
    case full
}

/// Живая сцена: персонаж на стеклянном островке, свечение, украшения и эффекты настроения.
/// Вся анимация считается от времени в TimelineView, физика — в PetSim,
/// поэтому ничего не «залипает» и не дёргается при перерисовке.
struct CompanionScene: View {
    var config: SceneConfig
    var size: CGFloat
    var mode: SceneMode
    var feedToken: Int
    var onTap: (() -> Void)?
    var onEvent: ((PetEvent) -> Void)?

    init(config: SceneConfig, size: CGFloat, interactive: Bool = true, mode: SceneMode? = nil,
         feedToken: Int = 0, onEvent: ((PetEvent) -> Void)? = nil, onTap: (() -> Void)? = nil) {
        self.config = config
        self.size = size
        self.mode = mode ?? (interactive ? .card : .display)
        self.feedToken = feedToken
        self.onTap = onTap
        self.onEvent = onEvent
    }

    @State private var sim = PetSim()
    @State private var charRect = CGRect.zero

    private var tint: Color { Color(hex: config.character.tintHex) }
    private var isEgg: Bool { config.stage == .egg }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !Motion.enabled)) { ctx in
            layers(now: ctx.date)
        }
        .frame(width: size, height: size * 0.92)
        .contentShape(Rectangle())
        .modifier(PetGestures(mode: isEgg ? .display : mode, sim: sim, charRect: { currentCharRect() }))
        .onAppear {
            MotionTracker.shared.start()
            sim.onEvent = { e in handle(e) }
        }
        .onDisappear { MotionTracker.shared.stop() }
        .onChange(of: feedToken) { _, _ in
            sim.feed(["🍓", "🍎", "🍪", "🍌", "🫐", "🥕", "🍒"].randomElement() ?? "🍓")
        }
        .accessibilityElement()
        .accessibilityLabel("\(config.character.name), \(config.mood.title.lowercased())")
        .accessibilityAddTraits(mode == .display ? [] : .isButton)
        .accessibilityAction { sim.tap(at: CGPoint(x: 0.5, y: 0.4), allowSpin: true) }
    }

    private func handle(_ e: PetEvent) {
        if e == .tap { onTap?() }
        if e == .petted { CompanionManager.shared.petted() }
        onEvent?(e)
    }

    private func geometry() -> SceneGeometry {
        SceneGeometry(W: size, H: size * 0.92, stage: config.stage, aspect: config.character.aspect)
    }

    private func currentCharRect() -> CGRect {
        let g = geometry()
        return CGRect(x: g.W / 2 - g.charW / 2 + sim.offset.width,
                      y: g.feetY - g.charH + sim.offset.height,
                      width: g.charW, height: g.charH)
    }

    private func layers(now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        let g = geometry()
        sim.step(now, canHold: mode == .full && !isEgg,
                 sleepy: mode == .full && !isEgg && (config.mood == .calm || config.mood == .happy))
        let tilt = MotionTracker.shared.step(now)
        let m = motion(t: t, now: now, g: g)
        let asleep = sim.asleep || (config.isNight && mode != .full && config.mood != .caring && config.mood != .sad)
        return ZStack {
            backLayers(g: g, t: t)
                .offset(x: -tilt.x * 10, y: -tilt.y * 6)
            Group {
                if config.showIsland { islandLayer(g: g, t: t) }
                shadow(g: g, m: m)
            }
            .offset(x: tilt.x * 4, y: tilt.y * 2)
            Group {
                AuraLayer(aura: config.aura, t: t, g: g, back: true)
                characterLayer(g: g, t: t, m: m, now: now, tilt: tilt, asleep: asleep)
                AuraLayer(aura: config.aura, t: t, g: g, back: false)
                headwearLayer(g: g, t: t, m: m)
            }
            .offset(x: tilt.x * 8 + sim.offset.width + m.dx, y: tilt.y * 5 + sim.offset.height)
            if config.showIsland {
                DecorLayer(decor: config.decor, back: false, g: g, t: t, mood: config.mood)
                    .offset(x: tilt.x * 11, y: tilt.y * 7)
            }
            MoodEffects(mood: config.mood, isNight: asleep, t: t, g: g, stage: config.stage)
                .offset(x: tilt.x * 8 + sim.offset.width, y: sim.offset.height)
            PlayEffects(sim: sim, now: now, g: g, tint: tint)
        }
        .frame(width: g.W, height: g.H)
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
        if config.aura == "rainbow" && !isEgg {
            let rainbowY: CGFloat = g.islandY - g.charH * 0.45
            RainbowArc()
                .frame(width: g.W * 0.82, height: g.W * 0.41)
                .opacity(0.55 + 0.15 * sin(t * 0.7))
                .position(x: g.W / 2, y: rainbowY)
        }
    }

    @ViewBuilder
    private func islandLayer(g: SceneGeometry, t: Double) -> some View {
        let islandH: CGFloat = g.islandW * 0.5
        let islandCenter: CGFloat = g.islandY + g.islandW * 0.12
        // Остров не меняется между кадрами: рисуем его в картинку один раз (запас в 14 pt — под свечение кольца),
        // дальше двигается только готовая текстура, а не пересчитывается размытие.
        Island(tint: tint, stage: config.stage)
            .frame(width: g.islandW, height: islandH)
            .padding(14)
            .drawingGroup()
            .padding(-14)
            .position(x: g.W / 2, y: islandCenter)
        DecorLayer(decor: config.decor, back: true, g: g, t: t, mood: config.mood)
    }

    private func shadow(g: SceneGeometry, m: Motion3) -> some View {
        let lift = min(1, m.lift + max(0, -sim.offset.height) / 160)
        let w: CGFloat = g.charW * 0.62 * (1 - lift * 0.45)
        let h: CGFloat = g.islandW * 0.07
        return Ellipse()
            .fill(Color.black.opacity(0.28 * (1 - Double(lift) * 0.5)))
            .frame(width: w, height: h)
            .blur(radius: 3 + lift * 3)
            .position(x: g.W / 2 + sim.offset.width * 0.9, y: g.feetY)
    }

    @ViewBuilder
    private func characterLayer(g: SceneGeometry, t: Double, m: Motion3, now: Date, tilt: CGPoint, asleep: Bool) -> some View {
        let sad = config.mood == .sad
        let y: CGFloat = g.feetY - g.charH / 2 + m.dy
        if isEgg {
            let fill: CGFloat = 0.8
            let side = g.charH / fill
            let bottom = EggArt.bottomFraction(fill: fill)
            Egg3DView(tintHex: config.character.tintHex, seed: config.character.id,
                      progress: config.eggProgress, interactive: mode != .display, fill: fill)
                .frame(width: side, height: side)
                .position(x: g.W / 2, y: g.feetY - side * (0.5 - bottom))
        } else {
            PetBody(config: config, g: g, sim: sim, t: t, now: now, tilt: tilt, tint: tint,
                    squashExtra: m.squash, asleep: asleep)
                .scaleEffect(x: m.sx, y: m.sy, anchor: .bottom)
                .rotationEffect(.degrees(m.tilt), anchor: .bottom)
                .rotationEffect(.degrees(m.spin))
                .rotation3DEffect(.degrees(Double(tilt.x) * 10), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                .rotation3DEffect(.degrees(Double(-tilt.y) * 6), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                .saturation(sad ? 0.75 : 1)
                .brightness(sad ? -0.04 : (asleep ? -0.05 : 0))
                .position(x: g.W / 2, y: y)
        }
    }

    @ViewBuilder
    private func headwearLayer(g: SceneGeometry, t: Double, m: Motion3) -> some View {
        if let hw = config.headwear, !isEgg {
            let x: CGFloat = g.W / 2 + CGFloat(config.character.headX - 0.5) * g.charW
            let float: CGFloat = 3 * CGFloat(sin(t * 2.1 + 1))
            let y: CGFloat = g.feetY - g.charH * m.sy + m.dy - g.W * 0.07 + float
            Headwear(id: hw, t: t)
                .frame(width: g.W * 0.15, height: g.W * 0.15)
                .rotationEffect(.degrees(m.tilt * 0.6))
                .position(x: x, y: y)
        }
    }

    private var glowColor: Color {
        config.mood == .sad ? Color(hex: "7A86A8") : tint
    }

    // MARK: - Движение

    struct Motion3 {
        var dy: CGFloat = 0
        var dx: CGFloat = 0
        var sx: CGFloat = 1
        var sy: CGFloat = 1
        var tilt: Double = 0
        var spin: Double = 0
        var lift: CGFloat = 0
        var squash: CGFloat = 0
    }

    private func motion(t: Double, now: Date, g: SceneGeometry) -> Motion3 {
        var m = Motion3()
        if isEgg { return m }
        let sleeping = sim.asleep || (config.isNight && (config.mood == .calm || config.mood == .happy))
        let (amp, speed, squash): (Double, Double, Double) = {
            if sleeping { return (0.8, 0.6, 0.02) }
            switch config.mood {
            case .happy: return (6, 2.6, 0.035)
            case .calm: return (3, 1.5, 0.02)
            case .sad: return (1.2, 0.8, 0.012)
            case .caring: return (2.2, 1.1, 0.018)
            }
        }()
        let wave = sin(t * speed)
        let held = sim.hold == .holding || sim.airborne
        if !held {
            m.dy = CGFloat(-abs(wave) * amp)
            m.sy = CGFloat(1 + squash * wave)
            m.sx = CGFloat(1 - squash * 0.6 * wave)
        }
        m.tilt = config.mood == .sad || sleeping ? -4 : (config.mood == .happy ? 2.5 * sin(t * speed * 0.5) : 0)

        // Сам по себе: раз в несколько секунд подпрыгивает, оглядывается или пританцовывает
        if !held && !sleeping && config.mood != .sad && now.timeIntervalSince(sim.lastInteraction) > 3 {
            let period = config.mood == .happy ? 6.0 : 9.0
            let slot = Int(t / period)
            let local = t - Double(slot) * period
            let kind = (slot &* 7919 &+ config.character.id.count) % 5
            if local < 1.1 {
                let p = local / 1.1
                switch kind {
                case 0:
                    // подпрыжка
                    if p < 0.5 { m.dy -= CGFloat(sin(.pi * p * 2)) * g.charH * 0.08 }
                case 1:
                    // оглядывается: разворот и обратно
                    m.sx *= CGFloat(cos(.pi * 2 * p))
                case 2:
                    // пританцовывает
                    m.tilt += 8 * sin(p * .pi * 4) * (1 - p)
                case 3:
                    // потягивается
                    m.squash -= CGFloat(0.08 * sin(.pi * p))
                default:
                    break
                }
            }
        }

        // В руке — болтается, в полёте — кувыркается по скорости
        if sim.hold == .holding {
            m.tilt = Double(max(-25, min(25, sim.velocity.width / 40)))
        } else if sim.airborne {
            m.tilt = Double(max(-35, min(35, sim.velocity.width / 30)))
        }

        // Прыжок от тапа, каждый третий — с оборотом
        let p = now.timeIntervalSince(sim.jumpStart) / 0.72
        if p >= 0 && p < 1 {
            let up = sin(.pi * p)
            m.dy -= CGFloat(up) * g.charH * 0.28
            m.lift = CGFloat(up)
            if p < 0.12 { m.squash += CGFloat(0.12 * (1 - p / 0.12)) }
            if p > 0.86 { m.squash += CGFloat(0.12 * ((p - 0.86) / 0.14)) * CGFloat(1 - (p - 0.86) / 0.14) * 4 }
            if sim.spin {
                let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                m.spin = 360 * e
            }
        }

        // Щекотка — хихикает и трясётся
        if now < sim.tickleUntil {
            let k = sim.tickleUntil.timeIntervalSince(now) / 1.1
            m.dx = CGFloat(4 * sin(t * 55) * k)
            m.tilt += 7 * sin(t * 38) * k
            m.squash += CGFloat(0.05 * sin(t * 30) * k)
        }

        // Проснулся — потягивается
        let w = now.timeIntervalSince(sim.wakeAt) / 0.8
        if w >= 0 && w < 1 {
            m.squash -= CGFloat(0.12 * sin(.pi * w))
        }

        // Кормление: подпрыгивает навстречу угощению и жуёт
        if let f = sim.feedPhase(now) {
            if f > 0.12 && f < 0.32 {
                let q = (f - 0.12) / 0.2
                m.dy -= CGFloat(sin(.pi * q)) * g.charH * 0.12
            }
            for c in [0.42, 0.6, 0.78] where f > c && f < c + 0.1 {
                m.squash += CGFloat(0.14 * sin(.pi * (f - c) / 0.1))
            }
        }
        return m
    }
}

// MARK: - Тело питомца: «желе», дыхание и глянец

private struct PetBody: View {
    let config: SceneConfig
    let g: SceneGeometry
    let sim: PetSim
    let t: Double
    let now: Date
    let tilt: CGPoint
    let tint: Color
    let squashExtra: CGFloat
    let asleep: Bool

    var body: some View {
        let pad: CGFloat = 0.16
        let lw = g.charW * (1 + 2 * pad), lh = g.charH * (1 + 2 * pad)
        // Картинка с чистыми краями (см. PetArtwork). Тень радиусом 10 поверх шейдера убрана:
        // она заново размывала весь слой каждый кадр, свечение уже даёт задний круг сцены.
        let image = PetArtwork(character: config.character)
            .frame(width: g.charW, height: g.charH)

        if Motion.enabled {
            let age = min(10, max(0, now.timeIntervalSince(sim.touchTime)))
            // Период обёртки кратен периоду дыхания (2π/2.1 · 200), иначе раз в 10 минут фаза «прыгает».
            let time = t.truncatingRemainder(dividingBy: 2 * Double.pi / 2.1 * 200)
            let squash = max(-0.3, min(0.35, sim.squash + squashExtra))
            let breathe: Double = asleep ? 1.6 : (config.mood == .happy ? 1.0 : 0.7)
            let tx = pad * g.charW + sim.touch.x * g.charW
            let ty = pad * g.charH + sim.touch.y * g.charH
            image
                .colorEffect(ShaderLibrary.petGloss(.float2(g.charW, g.charH),
                                                    .float2(-tilt.x, -tilt.y),
                                                    .float(asleep ? 0.12 : 0.28)))
                .padding(.horizontal, g.charW * pad)
                .padding(.vertical, g.charH * pad)
                .distortionEffect(ShaderLibrary.petJelly(.float2(lw, lh), .float2(tx, ty),
                                                         .float(age), .float(Double(sim.touchAmp)),
                                                         .float(Double(squash)), .float(time),
                                                         .float(breathe), .float(Double(pad))),
                                  maxSampleOffset: CGSize(width: lw * 0.25, height: lh * 0.3))
                .frame(width: g.charW, height: g.charH)
        } else {
            image
        }
    }
}

// MARK: - Сердечки, угощение и крошки

private struct PlayEffects: View {
    let sim: PetSim
    let now: Date
    let g: SceneGeometry
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(sim.hearts) { h in
                let age = now.timeIntervalSince(h.born) / 1.4
                Image(systemName: "heart.fill")
                    .font(.system(size: g.W * 0.06))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "FF9AC1"), Color(hex: "FF4F8B")], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(0.6 + 0.6 * min(1, age * 3))
                    .opacity(1 - age)
                    .position(x: h.x + CGFloat(sin(age * 9 + Double(h.id))) * 8, y: h.y - CGFloat(age) * g.H * 0.35)
            }
            if let f = sim.feedPhase(now) {
                treat(f)
            }
            ForEach(sim.crumbs) { c in
                let a = now.timeIntervalSince(c.born)
                Circle()
                    .fill(Color(hex: "E8B56A"))
                    .frame(width: 4, height: 4)
                    .opacity(1 - a / 0.9)
                    .position(x: c.x + c.vx * CGFloat(a), y: mouthY + c.vy * CGFloat(a) + 700 * CGFloat(a * a))
            }
        }
        .allowsHitTesting(false)
    }

    private var mouthY: CGFloat { g.feetY - g.charH * 0.62 }

    @ViewBuilder
    private func treat(_ f: Double) -> some View {
        // Падает сверху до «рта», дальше откусывается в три приёма
        let fall = min(1, f / 0.32)
        let y = -g.H * 0.1 + (mouthY - (-g.H * 0.1)) * CGFloat(fall * fall)
        let bites = f < 0.42 ? 0 : (f < 0.6 ? 1 : (f < 0.78 ? 2 : 3))
        if bites < 3 {
            Text(sim.treatEmoji)
                .font(.system(size: g.W * 0.11))
                .scaleEffect(1 - CGFloat(bites) * 0.28)
                .rotationEffect(.degrees(f * 200))
                .position(x: g.W / 2 + sim.offset.width, y: y)
                .onChange(of: bites) { _, b in
                    if b > 0 {
                        Haptics.chomp()
                        sim.spawnCrumbs(at: g.W / 2 + sim.offset.width, now: .now)
                        sim.poke(at: CGPoint(x: 0.5, y: 0.35), strength: 0.8)
                    }
                }
        } else {
            Color.clear.onAppear {
                Haptics.success()
                sim.addHeart(x: g.W / 2 + sim.offset.width - 20, y: mouthY)
                sim.addHeart(x: g.W / 2 + sim.offset.width + 20, y: mouthY - 10)
            }
        }
    }
}

// MARK: - Жесты

private struct PetGestures: ViewModifier {
    let mode: SceneMode
    let sim: PetSim
    let charRect: () -> CGRect

    func body(content: Content) -> some View {
        switch mode {
        case .display:
            content
        case .card:
            content.gesture(
                SpatialTapGesture().onEnded { v in
                    let r = charRect()
                    sim.tap(at: CGPoint(x: (v.location.x - r.minX) / max(1, r.width),
                                        y: (v.location.y - r.minY) / max(1, r.height)), allowSpin: true)
                }
            )
        case .full:
            content.gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        if !sim.fingerActive {
                            sim.fingerActive = true
                            sim.fingerDown(v.startLocation, charRect: charRect())
                        }
                        sim.fingerMoved(v.location, charRect: charRect(), scale: .zero)
                    }
                    .onEnded { v in
                        sim.fingerUp(v.location, charRect: charRect(), allowSpin: true)
                        sim.fingerActive = false
                    }
            )
        }
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
        let charScale: CGFloat = [0.72, 0.66, 0.82, 1.0][stage.rawValue]
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
                // Верх — стеклянная площадка. Без .ultraThinMaterial: он каждый кадр заново размывал
                // «подложку» под собой, а подложка (свечение сцены) пульсирует.
                Ellipse()
                    .fill(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.26 : 0.55), tint.opacity(0.38)],
                                         startPoint: .top, endPoint: .bottom))
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
