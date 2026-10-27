import SceneKit
import UIKit

func v3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
    SCNVector3(Float(x), Float(y), Float(z))
}

private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

/// Материалы питомцев: общие настройки, чтобы модели выглядели одним семейством.
enum PetMat {
    static func make(_ color: UIColor, rough: Double = 0.45, clear: Double = 0, emission: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = 0.0
        if clear > 0 {
            m.clearCoat.contents = clear
            m.clearCoatRoughness.contents = 0.1
        }
        if let emission { m.emission.contents = emission }
        m.isDoubleSided = false
        return m
    }

    static func node(_ geometry: SCNGeometry, _ material: SCNMaterial, at p: SCNVector3 = SCNVector3Zero,
                     scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
        geometry.firstMaterial = material
        let n = SCNNode(geometry: geometry)
        n.position = p
        n.scale = scale
        return n
    }

    static func sphere(_ material: SCNMaterial, at p: SCNVector3, scale: SCNVector3, segments: Int = 40) -> SCNNode {
        let g = SCNSphere(radius: 1)
        g.segmentCount = segments
        return node(g, material, at: p, scale: scale)
    }
}

/// Размеры и раскладка лица на эллипсоиде головы (центр — в начале координат головы).
struct PetFaceSpec {
    var rx = 1.0, ry = 0.9, rz = 0.95
    var eyeX = 0.36, eyeY = 0.06
    var eyeW = 0.14, eyeH = 0.19
    var eyeLift = 0.02
    var mouthY = -0.24, mouthW = 0.12
    var hasMouth = true
    var browY = 0.34
    var blushX = 0.66, blushY = -0.14
    var ink = UIColor(red: 0.10, green: 0.10, blue: 0.20, alpha: 1)
    var browColor = UIColor(red: 0.16, green: 0.14, blue: 0.24, alpha: 1)

    /// Точка на поверхности эллипсоида над (x, y) и поворот по нормали.
    func surface(_ x: Double, _ y: Double, lift: Double = 0) -> (pos: SCNVector3, euler: SCNVector3) {
        let nx = max(-0.95, min(0.95, x / rx))
        let ny = max(-0.95, min(0.95, y / ry))
        let rest = max(0.02, 1 - nx * nx - ny * ny)
        let z = rz * rest.squareRoot() + lift
        return (v3(x, y, z), v3(-asin(ny), asin(nx), 0))
    }

    func place(_ node: SCNNode, _ x: Double, _ y: Double, lift: Double = 0) {
        let s = surface(x, y, lift: lift)
        node.position = s.pos
        node.eulerAngles = s.euler
    }
}

/// Лицо питомца: глаза (шар, дуга радости, сердечко), брови, румянец и рот.
@MainActor
final class PetFaceRig {
    let spec: PetFaceSpec
    let group = SCNNode()

    private struct Eye {
        let root: SCNNode
        let group: SCNNode
        let ball: SCNNode
        let joy: SCNNode
        let heart: SCNNode
    }
    private var eyes: [Eye] = []
    private var brows: [SCNNode] = []
    private var browRoots: [SCNNode] = []
    private var blushes: [SCNNode] = []
    private let mouth = SCNNode()
    private var mouthCache: [Int: SCNGeometry] = [:]
    private var mouthKey = -1
    private let mouthMaterial: SCNMaterial

    init(spec: PetFaceSpec) {
        self.spec = spec
        mouthMaterial = PetMat.make(UIColor(red: 0.30, green: 0.08, blue: 0.14, alpha: 1), rough: 0.6)
        mouthMaterial.isDoubleSided = true
        let ink = PetMat.make(spec.ink, rough: 0.12, clear: 1)
        let white = SCNMaterial()
        white.lightingModel = .constant
        white.diffuse.contents = UIColor.white
        let heartMat = PetMat.make(UIColor(red: 1, green: 0.30, blue: 0.48, alpha: 1), rough: 0.3,
                                   emission: UIColor(red: 0.6, green: 0.08, blue: 0.2, alpha: 1))
        heartMat.isDoubleSided = true
        let inkFlat = PetMat.make(spec.ink, rough: 0.5)
        inkFlat.isDoubleSided = true

        for side in [-1.0, 1.0] {
            let root = SCNNode()
            spec.place(root, side * spec.eyeX, spec.eyeY, lift: spec.eyeLift)
            let g = SCNNode()
            root.addChildNode(g)

            let ball = PetMat.sphere(ink, at: SCNVector3Zero, scale: v3(spec.eyeW, spec.eyeH, spec.eyeW * 0.5), segments: 28)
            // Блики живут внутри глаза: уменьшается глаз — исчезают и они.
            let big = PetMat.sphere(white, at: v3(0.34, 0.38, 0.78), scale: v3(0.30, 0.30, 0.30), segments: 12)
            let small = PetMat.sphere(white, at: v3(-0.30, -0.34, 0.80), scale: v3(0.15, 0.15, 0.15), segments: 10)
            ball.addChildNode(big)
            ball.addChildNode(small)
            g.addChildNode(ball)

            let joy = SCNNode(geometry: PetFaceRig.joyShape())
            joy.geometry?.firstMaterial = inkFlat
            joy.scale = v3(0.001, 0.001, 0.001)
            g.addChildNode(joy)

            let heart = SCNNode(geometry: PetFaceRig.heartShape())
            heart.geometry?.firstMaterial = heartMat
            heart.scale = v3(0.001, 0.001, 0.001)
            g.addChildNode(heart)

            group.addChildNode(root)
            eyes.append(Eye(root: root, group: g, ball: ball, joy: joy, heart: heart))

            // Бровь: корень лежит на поверхности, сама бровь — капсула, повёрнутая горизонтально.
            let browRoot = SCNNode()
            spec.place(browRoot, side * spec.eyeX, spec.browY, lift: 0.015)
            let capsule = SCNCapsule(capRadius: 0.02, height: spec.eyeW * 2.1)
            let brow = PetMat.node(capsule, PetMat.make(spec.browColor, rough: 0.6))
            brow.eulerAngles = v3(0, 0, Double.pi / 2)
            brow.opacity = 0
            browRoot.addChildNode(brow)
            group.addChildNode(browRoot)
            brows.append(brow)
            browRoots.append(browRoot)

            // Румянец
            let blushMat = SCNMaterial()
            blushMat.lightingModel = .constant
            blushMat.diffuse.contents = UIColor(red: 1, green: 0.50, blue: 0.58, alpha: 1)
            let blush = PetMat.sphere(blushMat, at: SCNVector3Zero, scale: v3(0.12, 0.075, 0.02), segments: 16)
            spec.place(blush, side * spec.blushX, spec.blushY, lift: 0.0)
            blush.opacity = 0.2
            group.addChildNode(blush)
            blushes.append(blush)
        }

        if spec.hasMouth {
            spec.place(mouth, 0, spec.mouthY, lift: 0.02)
            group.addChildNode(mouth)
        }
    }

    // MARK: - Формы

    private static func joyShape() -> SCNGeometry {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -1, y: -0.35))
        p.addQuadCurve(to: CGPoint(x: 1, y: -0.35), controlPoint: CGPoint(x: 0, y: 1.25))
        p.addLine(to: CGPoint(x: 0.78, y: -0.35))
        p.addQuadCurve(to: CGPoint(x: -0.78, y: -0.35), controlPoint: CGPoint(x: 0, y: 0.62))
        p.close()
        let s = SCNShape(path: p, extrusionDepth: 0.3)
        return s
    }

    private static func heartShape() -> SCNGeometry {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: -0.9))
        p.addCurve(to: CGPoint(x: -1, y: 0.2), controlPoint1: CGPoint(x: -0.6, y: -0.5), controlPoint2: CGPoint(x: -1, y: -0.2))
        p.addCurve(to: CGPoint(x: 0, y: 0.5), controlPoint1: CGPoint(x: -1, y: 0.8), controlPoint2: CGPoint(x: -0.2, y: 0.9))
        p.addCurve(to: CGPoint(x: 1, y: 0.2), controlPoint1: CGPoint(x: 0.2, y: 0.9), controlPoint2: CGPoint(x: 1, y: 0.8))
        p.addCurve(to: CGPoint(x: 0, y: -0.9), controlPoint1: CGPoint(x: 1, y: -0.2), controlPoint2: CGPoint(x: 0.6, y: -0.5))
        p.close()
        let s = SCNShape(path: p, extrusionDepth: 0.3)
        return s
    }

    /// Рот: полоска-улыбка, которая раскрывается в овал. Формы кэшируются по шагам, чтобы не строить заново каждый кадр.
    private func mouthGeometry(smile: Double, open: Double) -> SCNGeometry {
        let sq = Int(((max(-1, min(1, smile)) + 1) * 8).rounded())
        let oq = Int((clamp01(open) * 10).rounded())
        let key = sq * 100 + oq
        if let g = mouthCache[key] { return g }
        let s = Double(sq) / 8 - 1
        let o = Double(oq) / 10
        let top = -s * 0.16
        let bottom = top - 0.12 - o * 0.95
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0.5, y: 0), controlPoint: CGPoint(x: 0, y: top))
        p.addQuadCurve(to: CGPoint(x: -0.5, y: 0), controlPoint: CGPoint(x: 0, y: bottom))
        p.close()
        let g = SCNShape(path: p, extrusionDepth: 0.2)
        g.firstMaterial = mouthMaterial
        mouthCache[key] = g
        return g
    }

    // MARK: - Кадр

    func apply(_ f: PetFace) {
        let joy = clamp01(f.joyEyes)
        let heart = clamp01(f.heartEyes)
        let ballK = max(0.001, 1 - max(joy, heart))
        let w = spec.eyeW, h = spec.eyeH
        let open = max(0.10, f.eyeOpen)
        for e in eyes {
            e.ball.scale = v3(w * ballK, h * ballK * open, w * 0.5 * ballK)
            e.group.position = v3(f.gazeX * w * 0.45, -f.gazeY * h * 0.35, 0)
            let j = max(0.001, joy)
            e.joy.scale = v3(w * 1.15 * j, w * 1.15 * j, w * 0.6 * j)
            let hk = max(0.001, heart)
            e.heart.scale = v3(w * 1.2 * hk, w * 1.2 * hk, w * 0.5 * hk)
        }
        // Брови: при тревоге внутренние концы поднимаются, при бодрости — приподняты целиком.
        let tilt = f.brow < 0 ? -f.brow * 0.45 : -f.brow * 0.08
        for (i, brow) in brows.enumerated() {
            let side = i == 0 ? 1.0 : -1.0
            brow.eulerAngles = v3(0, 0, Double.pi / 2 + side * tilt)
            brow.position = v3(0, f.brow * 0.05, 0)
            brow.opacity = CGFloat(clamp01(abs(f.brow) * 1.6))
        }
        for b in blushes { b.opacity = CGFloat(clamp01(f.blush * 1.1)) }
        if spec.hasMouth {
            let k = spec.mouthW
            mouth.geometry = mouthGeometry(smile: f.smile, open: f.mouthOpen)
            mouth.scale = v3(k * 2, k * 2, k * 2)
        }
    }
}

/// Одна 3D-модель питомца: корпус от основания, голова на «шарнире» и своя дополнительная анимация.
@MainActor
final class PetRig {
    /// Корень у ног: крен, оборот.
    let root = SCNNode()
    /// Сжатие/растяжение от основания.
    let squash = SCNNode()
    /// Голова: поворачивается за взглядом; её центр — начало координат узла.
    let head = SCNNode()
    let face: PetFaceRig
    /// Дополнительная анимация модели: поза, сглаженное лицо, «возбуждённость» 0…1, секунд с прошлого кадра.
    var extras: (Pet3DPose, PetFace, Double, Double) -> Void = { _, _, _, _ in }

    private var current = PetFace()
    private var lastTime = -1.0
    private var sleep = 0.0
    private var yawSway = 0.0

    init(face: PetFaceRig) {
        self.face = face
        root.addChildNode(squash)
        squash.addChildNode(head)
        head.addChildNode(face.group)
    }

    private func approach(_ a: Double, _ b: Double, _ rate: Double, _ dt: Double) -> Double {
        a + (b - a) * (1 - exp(-rate * dt))
    }

    func apply(_ pose: Pet3DPose) {
        let dt = lastTime < 0 ? 1.0 / 60 : min(0.1, max(0, pose.time - lastTime))
        lastTime = pose.time
        let t = pose.face
        current = PetFace(
            eyeOpen: approach(current.eyeOpen, t.eyeOpen, 38, dt),
            joyEyes: approach(current.joyEyes, t.joyEyes, 16, dt),
            heartEyes: approach(current.heartEyes, t.heartEyes, 16, dt),
            smile: approach(current.smile, t.smile, 12, dt),
            mouthOpen: approach(current.mouthOpen, t.mouthOpen, 16, dt),
            brow: approach(current.brow, t.brow, 12, dt),
            blush: approach(current.blush, t.blush, 6, dt),
            gazeX: approach(current.gazeX, t.gazeX, 11, dt),
            gazeY: approach(current.gazeY, t.gazeY, 11, dt))
        sleep = approach(sleep, pose.sleepiness, 4, dt)
        face.apply(current)

        let excitement = clamp01(current.smile * 0.45 + current.joyEyes * 0.4 + current.mouthOpen * 0.25)
        let sz = (pose.sx + 1) / 2
        squash.scale = v3(pose.sx * (1 + 0.10 * pose.wobble), pose.sy * (1 - 0.10 * pose.wobble), sz)

        let sway = sin(pose.time * 0.6) * 0.08 * (1 - sleep)
        let yaw = pose.spin * Double.pi / 180 + pose.turn * 0.5 + sway
        let roll = -pose.roll * Double.pi / 180 + pose.wobbleSide * pose.wobble * 0.14
        root.eulerAngles = v3(0, yaw, roll)

        head.eulerAngles = v3(current.gazeY * 0.20 + sleep * 0.32,
                              current.gazeX * 0.38,
                              sin(pose.time * 3.1) * 0.045 * excitement)
        extras(pose, current, excitement, dt)
    }
}
