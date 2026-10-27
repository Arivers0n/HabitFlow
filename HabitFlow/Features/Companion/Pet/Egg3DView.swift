import SwiftUI
import SceneKit
import UIKit

/// Настоящее 3D-яйцо: объём, свет и блики, крутится пальцем, трескается с опытом
/// и разлетается скорлупками при вылуплении.
struct Egg3DView: UIViewRepresentable {
    var tintHex: String
    var seed: String
    /// 0…1 — прогресс до вылупления (трещины появляются на 45 %, 75 % и 92 %).
    var progress: Double
    var interactive = true
    /// Доля высоты кадра, которую занимает яйцо (для заставки вылупления — меньше, чтобы осколкам было куда лететь).
    var fill: CGFloat = 0.8
    /// Смена значения запускает вылупление.
    var hatchToken = 0
    var onHatched: (() -> Void)? = nil

    func makeCoordinator() -> EggCoordinator { EggCoordinator() }

    func makeUIView(context: Context) -> EggSCNView {
        let v = EggSCNView(frame: .zero, options: nil)
        v.backgroundColor = .clear
        v.isOpaque = false
        // Яйцо на экране — 128 pt при плотности 3×: 2× MSAA вместо 4× почти не видно, а заливки в 2 раза меньше.
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        // При «Уменьшении движения» сцена статична и перерисовывается только по событию (касание, вылупление).
        v.rendersContinuously = Motion.enabled
        v.allowsCameraControl = false
        context.coordinator.setup(view: v, tintHex: tintHex, seed: seed, progress: progress, fill: fill)
        if interactive { context.coordinator.addGestures(to: v) }
        context.coordinator.lastHatchToken = hatchToken
        return v
    }

    func updateUIView(_ v: EggSCNView, context: Context) {
        let c = context.coordinator
        c.onHatched = onHatched
        c.update(tintHex: tintHex, progress: progress)
        if hatchToken != c.lastHatchToken {
            c.lastHatchToken = hatchToken
            c.hatch()
        }
    }

    static func dismantleUIView(_ v: EggSCNView, coordinator: EggCoordinator) {
        v.isPlaying = false
        v.scene = nil
    }
}

/// Рисует только на экране: вне окна не тратит батарею.
final class EggSCNView: SCNView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        isPlaying = window != nil
    }
}

@MainActor
final class EggCoordinator: NSObject, UIGestureRecognizerDelegate {
    private let scene = SCNScene()
    private let pivot = SCNNode()      // у основания яйца — вокруг него качаемся
    private let spin = SCNNode()       // вращение вокруг вертикали
    private let egg = SCNNode()
    private let material = SCNMaterial()
    private var tintHex = ""
    private var seed = ""
    private var bucket = -1
    private var hatched = false
    var lastHatchToken = 0
    var onHatched: (() -> Void)?

    // MARK: - Сцена

    func setup(view: SCNView, tintHex: String, seed: String, progress: Double, fill: CGFloat) {
        self.tintHex = tintHex
        self.seed = seed
        view.scene = scene
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = EggArt.environment()
        scene.lightingEnvironment.intensity = 1.1
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)

        // Камера: яйцо занимает `fill` высоты кадра, основание ближе к низу
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 0.1
        cam.zFar = 100
        let half = 1.0 / Double(max(0.2, fill))
        let distance = half / tan(15 * Double.pi / 180)
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 1 + Float(half - 1.0) * 0.6, Float(distance))
        camNode.look(at: SCNVector3(0, Float(1 + (half - 1.0) * 0.6), 0))
        scene.rootNode.addChildNode(camNode)

        // Свет: основной сверху слева, контровой сзади цветом напарника, мягкий заполняющий
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 900
        rim.light?.color = EggArt.color(tintHex).mixed(with: .white, 0.4)
        rim.position = SCNVector3(0.4, 2.4, -2.6)
        scene.rootNode.addChildNode(rim)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .ambient
        fillLight.light?.intensity = 220
        scene.rootNode.addChildNode(fillLight)

        // Яйцо: основание в точке (0, 0, 0)
        egg.geometry = EggArt.eggGeometry()
        egg.position = SCNVector3(0, 1, 0)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.32
        material.metalness.contents = 0.0
        material.clearCoat.contents = 0.75
        material.clearCoatRoughness.contents = 0.08
        material.isDoubleSided = true
        egg.geometry?.firstMaterial = material
        spin.addChildNode(egg)
        pivot.addChildNode(spin)
        scene.rootNode.addChildNode(pivot)

        update(tintHex: tintHex, progress: progress)
        startIdle()
    }

    func update(tintHex: String, progress: Double) {
        let b = progress >= 0.92 ? 3 : progress >= 0.75 ? 2 : progress >= 0.45 ? 1 : 0
        guard b != bucket || tintHex != self.tintHex else { return }
        let tintChanged = tintHex != self.tintHex
        self.tintHex = tintHex
        bucket = b
        let art = EggArt.textures(tintHex: tintHex, seed: seed, cracks: b)
        material.diffuse.contents = art.diffuse
        material.emission.contents = art.emission
        material.emission.intensity = b >= 2 ? 1.0 : 0.6
        if tintChanged { startIdle() } else if b >= 2 { startIdle() }
    }

    // MARK: - Покачивание

    private func startIdle() {
        guard !hatched, Motion.enabled else { return }
        spin.removeAction(forKey: "spin")
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 26)), forKey: "spin")

        let strong = bucket >= 2
        let a: CGFloat = strong ? 0.2 : 0.11
        func r(_ z: CGFloat, _ d: TimeInterval) -> SCNAction {
            let act = SCNAction.rotateTo(x: 0, y: 0, z: z, duration: d, usesShortestUnitArc: true)
            act.timingMode = .easeInEaseOut
            return act
        }
        let wobble = SCNAction.sequence([r(a, 0.13), r(-a * 1.4, 0.2), r(a * 0.8, 0.16), r(-a * 0.4, 0.13), r(0, 0.12)])
        let wait = SCNAction.wait(duration: strong ? 1.6 : 3.2, withRange: 1.6)
        pivot.removeAction(forKey: "idle")
        pivot.runAction(.repeatForever(.sequence([wait, wobble])), forKey: "idle")

        let up = SCNAction.scale(to: 1.018, duration: 1.4)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.scale(to: 1.0, duration: 1.4)
        down.timingMode = .easeInEaseOut
        egg.removeAction(forKey: "breath")
        egg.runAction(.repeatForever(.sequence([up, down])), forKey: "breath")
    }

    // MARK: - Касания

    func addGestures(to v: UIView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        v.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.delegate = self
        v.addGestureRecognizer(pan)
    }

    /// Крутим только горизонтальным движением — вертикальное оставляем прокрутке экрана.
    nonisolated func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard !hatched else { return }
        Haptics.tap()
        let jumpUp = SCNAction.moveBy(x: 0, y: 0.32, z: 0, duration: 0.16)
        jumpUp.timingMode = .easeOut
        let jumpDown = SCNAction.moveBy(x: 0, y: -0.32, z: 0, duration: 0.18)
        jumpDown.timingMode = .easeIn
        pivot.runAction(.sequence([jumpUp, jumpDown]), forKey: "jump")

        func s(_ x: CGFloat, _ y: CGFloat, _ d: TimeInterval) -> SCNAction {
            let a = SCNAction.customAction(duration: d) { node, t in
                let k = Float(t / CGFloat(d))
                let from = node.scale
                node.scale = SCNVector3(from.x + (Float(x) - from.x) * k, from.y + (Float(y) - from.y) * k, from.z + (Float(x) - from.z) * k)
            }
            return a
        }
        egg.removeAction(forKey: "breath")
        egg.runAction(.sequence([s(1.1, 0.88, 0.08), .wait(duration: 0.26), s(0.94, 1.08, 0.08), s(1, 1, 0.12)])) { [weak self] in
            DispatchQueue.main.async { self?.startIdle() }
        }
        let a: CGFloat = 0.24
        func r(_ z: CGFloat, _ d: TimeInterval) -> SCNAction {
            let act = SCNAction.rotateTo(x: 0, y: 0, z: z, duration: d, usesShortestUnitArc: true)
            act.timingMode = .easeInEaseOut
            return act
        }
        pivot.runAction(.sequence([r(a, 0.1), r(-a, 0.16), r(a * 0.5, 0.12), r(0, 0.1)]), forKey: "tapWobble")
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard !hatched else { return }
        switch g.state {
        case .began:
            spin.removeAction(forKey: "spin")
            spin.removeAction(forKey: "inertia")
        case .changed:
            let dx = g.translation(in: g.view).x
            g.setTranslation(.zero, in: g.view)
            spin.eulerAngles.y += Float(dx) * 0.012
        case .ended, .cancelled:
            let v = Float(g.velocity(in: g.view).x) * 0.012
            let duration: TimeInterval = 1.4
            let inertia = SCNAction.customAction(duration: duration) { node, t in
                let k = 1 - Float(t) / Float(duration)
                node.eulerAngles.y += v * k * k / 60
            }
            spin.runAction(inertia, forKey: "inertia") { [weak self] in
                DispatchQueue.main.async { self?.startIdle() }
            }
            Haptics.soft()
        default:
            break
        }
    }

    // MARK: - Вылупление

    func hatch() {
        guard !hatched else { return }
        hatched = true
        pivot.removeAllActions()
        spin.removeAllActions()
        egg.removeAllActions()
        material.emission.contents = EggArt.textures(tintHex: tintHex, seed: seed, cracks: 3).emission

        // Дрожь нарастает
        var shakes: [SCNAction] = []
        for i in 0..<12 {
            let amp = CGFloat(0.06 + Double(i) * 0.02) * (i.isMultiple(of: 2) ? 1 : -1)
            shakes.append(.rotateTo(x: 0, y: 0, z: amp, duration: 0.07, usesShortestUnitArc: true))
        }
        let glowUp = SCNAction.customAction(duration: 0.85) { [weak self] _, t in
            DispatchQueue.main.async { self?.material.emission.intensity = 1 + t * 2.5 }
        }
        Haptics.tap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Haptics.soft() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { Haptics.tap() }
        pivot.runAction(.group([.sequence(shakes), glowUp])) { [weak self] in
            DispatchQueue.main.async { self?.burst() }
        }
    }

    private func burst() {
        Haptics.celebrate()
        // Вспышка
        let flash = SCNNode()
        flash.light = SCNLight()
        flash.light?.type = .omni
        flash.light?.intensity = 4000
        flash.light?.color = EggArt.color(tintHex).mixed(with: .white, 0.6)
        flash.position = SCNVector3(0, 1, 0.6)
        scene.rootNode.addChildNode(flash)
        flash.runAction(.sequence([.customAction(duration: 0.6) { node, t in
            node.light?.intensity = 4000 * (1 - t / 0.6)
        }, .removeFromParentNode()]))

        // Скорлупки из той же «ткани», что и яйцо
        let worldBase = spin.convertPosition(SCNVector3(0, 0, 0), to: scene.rootNode)
        egg.isHidden = true
        var rng = SeededRandom(seed: EggArt.stableHash(seed))
        for i in 0..<18 {
            let yy = Double(i % 6) / 5.0 * 1.6 - 0.7
            let th = Double(i) * 2.4 + rng.next() * 0.6
            let r = 0.74 * sqrt(max(0.05, 1 - yy * yy))
            let piece = SCNBox(width: CGFloat(0.28 + rng.next() * 0.18), height: CGFloat(0.3 + rng.next() * 0.18),
                               length: 0.05, chamferRadius: 0.025)
            let m = material.copy() as! SCNMaterial
            piece.firstMaterial = m
            let n = SCNNode(geometry: piece)
            n.position = SCNVector3(Float(r * cos(th)) + worldBase.x, Float(yy + 1) + worldBase.y, Float(r * sin(th)) + worldBase.z)
            n.look(at: SCNVector3(worldBase.x, Float(yy + 1) + worldBase.y, worldBase.z))
            let body = SCNPhysicsBody(type: .dynamic, shape: nil)
            body.mass = 0.08
            body.restitution = 0.4
            body.damping = 0.05
            n.physicsBody = body
            scene.rootNode.addChildNode(n)
            let out = SCNVector3(Float(cos(th)) * Float(0.5 + rng.next()), Float(1.4 + rng.next() * 1.4), Float(sin(th)) * Float(0.5 + rng.next()))
            body.applyForce(out, asImpulse: true)
            body.applyTorque(SCNVector4(Float(rng.next()), Float(rng.next()), Float(rng.next()), Float(0.02 + rng.next() * 0.03)), asImpulse: true)
            n.runAction(.sequence([.wait(duration: 1.1), .fadeOut(duration: 0.6), .removeFromParentNode()]))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.onHatched?() }
    }
}

// MARK: - Генерация формы и текстур

enum EggArt {
    static func color(_ hex: String) -> UIColor { UIColor(Color(hex: hex)) }

    /// Поверхность вращения по профилю яйца (основание в −1, верх в +1, верх чуть уже).
    static func eggGeometry(rings: Int = 56, segments: Int = 72) -> SCNGeometry {
        func profile(_ t: Double) -> (r: Double, y: Double) {
            let a = Double.pi * t
            let y = -cos(a)
            let r = 0.74 * sin(a) * (1 - 0.13 * y)
            return (r, y)
        }
        var verts: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        verts.reserveCapacity((rings + 1) * (segments + 1))
        for i in 0...rings {
            let t = Double(i) / Double(rings)
            let p = profile(t)
            let e = 0.002
            let p0 = profile(max(0, t - e)), p1 = profile(min(1, t + e))
            var nr = p1.y - p0.y, ny = -(p1.r - p0.r)
            let len = sqrt(nr * nr + ny * ny)
            if len > 1e-9 { nr /= len; ny /= len } else { nr = 0; ny = t < 0.5 ? -1 : 1 }
            for j in 0...segments {
                let th = Double(j) / Double(segments) * 2 * Double.pi
                verts.append(SCNVector3(Float(p.r * cos(th)), Float(p.y), Float(p.r * sin(th))))
                normals.append(SCNVector3(Float(nr * cos(th)), Float(ny), Float(nr * sin(th))))
                uvs.append(CGPoint(x: Double(j) / Double(segments), y: 1 - t))
            }
        }
        var idx: [Int32] = []
        let row = segments + 1
        for i in 0..<rings {
            for j in 0..<segments {
                let a = Int32(i * row + j), b = Int32((i + 1) * row + j)
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts),
                                        SCNGeometrySource(normals: normals),
                                        SCNGeometrySource(textureCoordinates: uvs)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return geo
    }

    /// Мягкое окружение для отражений: светлый «потолок», тёмный «пол».
    static func environment() -> UIImage {
        let size = CGSize(width: 256, height: 128)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 0.55, alpha: 1).cgColor,
                          UIColor(white: 0.12, alpha: 1).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Окно-софтбокс для блика
            UIColor(white: 1, alpha: 0.9).setFill()
            UIBezierPath(roundedRect: CGRect(x: 40, y: 18, width: 60, height: 26), cornerRadius: 10).fill()
        }
    }

    @MainActor private static var cache: [String: (diffuse: UIImage, emission: UIImage)] = [:]

    /// Хэш строки, одинаковый между запусками (в отличие от hashValue).
    static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 1_469_598_103_934_665_603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return Int(truncatingIfNeeded: h)
    }

    /// Где низ яйца в кадре (доля высоты от нижнего края) — чтобы поставить его на островок.
    static func bottomFraction(fill: CGFloat) -> CGFloat {
        let half = 1.0 / Double(max(0.2, fill))
        let cy = 1 + (half - 1.0) * 0.6
        return CGFloat((half - cy) / (2 * half))
    }

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f)
    }

    @MainActor
    static func textures(tintHex: String, seed: String, cracks: Int) -> (diffuse: UIImage, emission: UIImage) {
        let key = "\(tintHex)-\(seed)-\(cracks)"
        if let c = cache[key] { return c }
        let W: CGFloat = 1024, H: CGFloat = 512
        let tint = color(tintHex)
        let light = tint.mixed(with: .white, 0.62)
        let dark = tint.mixed(with: .black, 0.18)
        var rng = SeededRandom(seed: EggArt.stableHash(seed))

        let diffuse = renderer(CGSize(width: W, height: H)).image { ctx in
            let cg = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [light.cgColor, tint.mixed(with: .white, 0.3).cgColor, dark.cgColor] as CFArray,
                                  locations: [0, 0.55, 1])!
            cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])
            // Пятнышки, как у настоящего яйца
            for i in 0..<34 {
                let x = CGFloat(rng.next()) * W
                let y = H * CGFloat(0.22 + rng.next() * 0.62)
                let r = CGFloat(10 + rng.next() * 34)
                let c = i.isMultiple(of: 3) ? dark.withAlphaComponent(0.35) : UIColor.white.withAlphaComponent(0.42)
                c.setFill()
                // по ширине растягиваем, чтобы на сфере пятно было круглым
                let stretch = 1 / max(0.35, sin(Double(y / H) * Double.pi))
                for dx in [-W, 0, W] {
                    cg.fillEllipse(in: CGRect(x: x - r * CGFloat(stretch) + dx, y: y - r, width: 2 * r * CGFloat(stretch), height: 2 * r))
                }
            }
            drawCracks(cg, W: W, H: H, level: cracks, color: UIColor.black.withAlphaComponent(0.55), width: 5)
            drawCracks(cg, W: W, H: H, level: cracks, color: UIColor.white.withAlphaComponent(0.35), width: 1.5, shift: 2)
        }
        let emission = renderer(CGSize(width: W, height: H)).image { ctx in
            let cg = ctx.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let glow = UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 1)
            cg.setShadow(offset: .zero, blur: 14, color: glow.cgColor)
            drawCracks(cg, W: W, H: H, level: cracks, color: glow, width: 3)
        }
        let out = (diffuse, emission)
        cache[key] = out
        return out
    }

    /// Трещины: первая — спереди, вторая — сбоку, третья — почти кольцом.
    private static func drawCracks(_ cg: CGContext, W: CGFloat, H: CGFloat, level: Int, color: UIColor,
                                   width: CGFloat, shift: CGFloat = 0) {
        guard level > 0 else { return }
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(width)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        func zigzag(from u0: CGFloat, to u1: CGFloat, v: CGFloat, amp: CGFloat, steps: Int) {
            let p = CGMutablePath()
            for k in 0...steps {
                let u = u0 + (u1 - u0) * CGFloat(k) / CGFloat(steps)
                let y = H * v + (k.isMultiple(of: 2) ? -amp : amp) + shift
                let pt = CGPoint(x: W * u + shift, y: y)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            cg.addPath(p)
            cg.strokePath()
        }
        // Камера смотрит на u ≈ 0.25
        zigzag(from: 0.17, to: 0.33, v: 0.4, amp: 9, steps: 7)
        if level >= 2 { zigzag(from: 0.42, to: 0.62, v: 0.47, amp: 11, steps: 9) }
        if level >= 3 {
            zigzag(from: 0.62, to: 1.0, v: 0.43, amp: 10, steps: 14)
            zigzag(from: 0.0, to: 0.17, v: 0.42, amp: 10, steps: 7)
            zigzag(from: 0.33, to: 0.42, v: 0.44, amp: 8, steps: 4)
        }
    }
}

/// Предсказуемые «случайные» числа: у каждого персонажа своё яйцо.
struct SeededRandom {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

extension UIColor {
    func mixed(with other: UIColor, _ k: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }
}
