import SceneKit
import UIKit

/// Три оригинальных 3D-питомца, собранных из примитивов SceneKit: ничего не скачивается, лицензий нет.
/// У каждого — своя дополнительная анимация (желейный «кончик», хвост и уши, крылья).
@MainActor
enum PetModels {
    static func isModel(_ id: String) -> Bool { ["jelly", "kitty", "owl"].contains(id) }

    static func rig(id: String, tintHex: String) -> PetRig {
        let tint = EggArt.color(tintHex)
        switch id {
        case "kitty": return kitty(tint)
        case "owl": return owl(tint)
        default: return jelly(tint)
        }
    }

    private static func shade(_ c: UIColor, light: CGFloat) -> UIColor { c.mixed(with: .white, light) }
    private static func deep(_ c: UIColor, _ k: CGFloat) -> UIColor { c.mixed(with: .black, k) }

    // MARK: - Желейка

    private static func jelly(_ tint: UIColor) -> PetRig {
        let spec = PetFaceSpec(rx: 1.0, ry: 0.9, rz: 0.95, eyeX: 0.36, eyeY: 0.06, eyeW: 0.14, eyeH: 0.19,
                               eyeLift: 0.03, mouthY: -0.26, mouthW: 0.12, hasMouth: true,
                               browY: 0.34, blushX: 0.64, blushY: -0.15)
        let rig = PetRig(face: PetFaceRig(spec: spec))
        rig.head.position = v3(0, 0.92, 0)

        let bodyMat = PetMat.make(tint, rough: 0.16, clear: 1, emission: deep(tint, 0.55))
        let body = PetMat.sphere(bodyMat, at: SCNVector3Zero, scale: v3(spec.rx, spec.ry, spec.rz), segments: 64)
        rig.head.addChildNode(body)

        // Лужица под телом — сжимается вместе с корпусом
        let puddleMat = PetMat.make(deep(tint, 0.12), rough: 0.5)
        let puddle = PetMat.node(SCNCylinder(radius: 1.12, height: 0.05), puddleMat, at: v3(0, 0.025, 0))
        rig.squash.addChildNode(puddle)

        // Кончик-капелька на макушке качается с запаздыванием
        let tipPivot = SCNNode()
        tipPivot.position = v3(0, 0.7, 0)
        let tip = PetMat.sphere(bodyMat, at: v3(0, 0.22, 0), scale: v3(0.2, 0.34, 0.2), segments: 28)
        tipPivot.addChildNode(tip)
        rig.head.addChildNode(tipPivot)

        // Блик-«окошко» и пузырьки внутри желе
        let shine = SCNMaterial()
        shine.lightingModel = .constant
        shine.diffuse.contents = UIColor(white: 1, alpha: 1)
        let sp = spec.surface(-0.5, 0.52, lift: 0.01)
        let window = PetMat.sphere(shine, at: sp.pos, scale: v3(0.17, 0.09, 0.02), segments: 16)
        window.eulerAngles = v3(Double(sp.euler.x), Double(sp.euler.y), 0.55)
        window.opacity = 0.85
        rig.head.addChildNode(window)

        let bubbleMat = PetMat.make(shade(tint, light: 0.55), rough: 0.1, clear: 1)
        let spots: [(Double, Double, Double)] = [(0.62, -0.5, 0.09), (-0.7, -0.32, 0.065), (0.2, 0.62, 0.05)]
        var bubbles: [SCNNode] = []
        for s in spots {
            let place = spec.surface(s.0, s.1, lift: 0.0)
            let b = PetMat.sphere(bubbleMat, at: place.pos, scale: v3(s.2, s.2, s.2 * 0.6), segments: 16)
            b.eulerAngles = place.euler
            rig.head.addChildNode(b)
            bubbles.append(b)
        }

        rig.extras = { pose, _, excitement, _ in
            // Кончик отстаёт от тела: крен и покачивание
            let lag = -pose.roll * Double.pi / 180 * 0.8
            tipPivot.eulerAngles = v3(0, 0, lag + sin(pose.time * 3.4) * (0.08 + 0.2 * excitement))
            for (i, b) in bubbles.enumerated() {
                let s = spots[i].2
                let pulse = 1 + 0.08 * sin(pose.time * 2.0 + Double(i) * 2.1)
                b.scale = v3(s * pulse, s * pulse, s * 0.6)
            }
        }
        return rig
    }

    // MARK: - Мурка

    private static func kitty(_ tint: UIColor) -> PetRig {
        let spec = PetFaceSpec(rx: 0.98, ry: 0.88, rz: 0.92, eyeX: 0.37, eyeY: 0.08, eyeW: 0.125, eyeH: 0.175,
                               eyeLift: 0.03, mouthY: -0.27, mouthW: 0.10, hasMouth: true,
                               browY: 0.36, blushX: 0.66, blushY: -0.14)
        let rig = PetRig(face: PetFaceRig(spec: spec))
        rig.head.position = v3(0, 0.88, 0)

        let fur = PetMat.make(tint, rough: 0.82)
        let light = PetMat.make(shade(tint, light: 0.55), rough: 0.9)
        let dark = PetMat.make(deep(tint, 0.3), rough: 0.8)
        let pink = PetMat.make(UIColor(red: 1, green: 0.62, blue: 0.70, alpha: 1), rough: 0.6)

        rig.head.addChildNode(PetMat.sphere(fur, at: SCNVector3Zero, scale: v3(spec.rx, spec.ry, spec.rz), segments: 56))

        // Мордочка и носик
        let muzzleP = spec.surface(0, -0.2, lift: -0.02)
        let muzzle = PetMat.sphere(light, at: muzzleP.pos, scale: v3(0.36, 0.23, 0.12), segments: 28)
        muzzle.eulerAngles = muzzleP.euler
        rig.head.addChildNode(muzzle)
        let noseP = spec.surface(0, -0.1, lift: 0.07)
        let nose = PetMat.sphere(pink, at: noseP.pos, scale: v3(0.06, 0.045, 0.04), segments: 16)
        nose.eulerAngles = noseP.euler
        rig.head.addChildNode(nose)

        // Полоски на лбу
        for dx in [-0.12, 0.0, 0.12] {
            let p = spec.surface(dx, 0.62, lift: 0.0)
            let stripe = PetMat.node(SCNCapsule(capRadius: 0.025, height: dx == 0 ? 0.2 : 0.15), dark, at: p.pos)
            stripe.eulerAngles = v3(Double(p.euler.x), Double(p.euler.y), -dx * 1.6)
            rig.head.addChildNode(stripe)
        }

        // Уши: наружная и внутренняя часть
        var ears: [SCNNode] = []
        for side in [-1.0, 1.0] {
            let pivot = SCNNode()
            pivot.position = v3(side * 0.6, 0.62, 0.02)
            let outer = PetMat.node(SCNCone(topRadius: 0.03, bottomRadius: 0.3, height: 0.5), fur, at: v3(0, 0.2, 0))
            let inner = PetMat.node(SCNCone(topRadius: 0.01, bottomRadius: 0.17, height: 0.34), pink, at: v3(0, 0.15, 0.07))
            pivot.addChildNode(outer)
            pivot.addChildNode(inner)
            pivot.eulerAngles = v3(0, 0, -side * 0.42)
            rig.head.addChildNode(pivot)
            ears.append(pivot)
        }

        // Усы
        for side in [-1.0, 1.0] {
            for (i, ang) in [0.22, 0.0, -0.22].enumerated() {
                let w = PetMat.node(SCNCylinder(radius: 0.007, height: 0.5), light,
                                    at: v3(side * 0.74, -0.2 - Double(i) * 0.045, 0.62))
                w.eulerAngles = v3(0, 0.0, Double.pi / 2 + side * ang)
                w.eulerAngles.y = Float(-side * 0.5)
                rig.head.addChildNode(w)
            }
        }

        // Лапки и хвост
        for side in [-1.0, 1.0] {
            rig.squash.addChildNode(PetMat.sphere(light, at: v3(side * 0.42, 0.1, 0.62), scale: v3(0.22, 0.14, 0.27)))
        }
        let tailBase = SCNNode()
        tailBase.position = v3(0.0, 0.34, -0.72)
        tailBase.eulerAngles = v3(-0.6, 0, 0)
        rig.squash.addChildNode(tailBase)
        var segments: [SCNNode] = []
        var parent = tailBase
        for i in 0..<6 {
            let r = 0.15 - Double(i) * 0.012
            let seg = SCNNode()
            seg.position = v3(0, i == 0 ? 0 : 0.2, 0)
            seg.addChildNode(PetMat.sphere(i == 5 ? dark : fur, at: SCNVector3Zero, scale: v3(r, r * 1.15, r)))
            parent.addChildNode(seg)
            segments.append(seg)
            parent = seg
        }

        rig.extras = { pose, face, excitement, _ in
            let speed = 2.4 + excitement * 5
            let amp = 0.07 + excitement * 0.2
            for (i, seg) in segments.enumerated() {
                let k = Double(i + 1) / Double(segments.count)
                seg.eulerAngles = v3(0, 0, 0.18 + sin(pose.time * speed - Double(i) * 0.6) * amp * k)
            }
            // Грусть — ушки опускаются; радость — торчат бодрее
            let droop = max(0, -face.brow) * 0.4
            let perk = max(0, face.brow) * 0.08
            let twitch = max(0, sin(pose.time * 0.7 + 1.3) - 0.96) * 6
            for (i, ear) in ears.enumerated() {
                let side = i == 0 ? -1.0 : 1.0
                ear.eulerAngles = v3(twitch * 0.2 * side, 0, -side * (0.42 + droop - perk))
            }
        }
        return rig
    }

    // MARK: - Хуху

    private static func owl(_ tint: UIColor) -> PetRig {
        let spec = PetFaceSpec(rx: 0.88, ry: 1.0, rz: 0.86, eyeX: 0.33, eyeY: 0.18, eyeW: 0.12, eyeH: 0.14,
                               eyeLift: 0.07, mouthY: -0.2, mouthW: 0.1, hasMouth: false,
                               browY: 0.42, blushX: 0.6, blushY: -0.05)
        let rig = PetRig(face: PetFaceRig(spec: spec))
        rig.head.position = v3(0, 1.0, 0)

        let feather = PetMat.make(tint, rough: 0.78)
        let cream = PetMat.make(shade(tint, light: 0.82), rough: 0.8)
        let belly = PetMat.make(shade(tint, light: 0.62), rough: 0.85)
        let dark = PetMat.make(deep(tint, 0.35), rough: 0.8)
        let amber = PetMat.make(UIColor(red: 1.0, green: 0.68, blue: 0.20, alpha: 1), rough: 0.5)
        let wingMat = PetMat.make(deep(tint, 0.15), rough: 0.8)

        rig.head.addChildNode(PetMat.sphere(feather, at: SCNVector3Zero, scale: v3(spec.rx, spec.ry, spec.rz), segments: 56))

        // Светлый животик с «перышками»
        let bellyP = spec.surface(0, -0.42, lift: -0.04)
        let bellyNode = PetMat.sphere(belly, at: bellyP.pos, scale: v3(0.58, 0.5, 0.14), segments: 32)
        bellyNode.eulerAngles = bellyP.euler
        rig.head.addChildNode(bellyNode)
        for (x, y) in [(-0.2, -0.3), (0.2, -0.3), (0.0, -0.46), (-0.3, -0.52), (0.3, -0.52), (0.0, -0.64)] {
            let p = spec.surface(x, y, lift: 0.07)
            let f = PetMat.sphere(cream, at: p.pos, scale: v3(0.09, 0.05, 0.02), segments: 12)
            f.eulerAngles = p.euler
            rig.head.addChildNode(f)
        }

        // Лицевые диски вокруг глаз
        for side in [-1.0, 1.0] {
            let p = spec.surface(side * 0.33, 0.18, lift: 0.0)
            let disc = PetMat.sphere(cream, at: p.pos, scale: v3(0.27, 0.27, 0.07), segments: 32)
            disc.eulerAngles = p.euler
            rig.head.addChildNode(disc)
        }

        // Клюв: верх неподвижен, низ приоткрывается
        let beakP = spec.surface(0, -0.04, lift: 0.1)
        let beakTop = PetMat.node(SCNCone(topRadius: 0, bottomRadius: 0.12, height: 0.24), amber)
        beakTop.eulerAngles = v3(Double.pi / 2, 0, 0)
        let beakTopHolder = SCNNode()
        beakTopHolder.position = beakP.pos
        beakTopHolder.addChildNode(beakTop)
        rig.head.addChildNode(beakTopHolder)
        let jawHolder = SCNNode()
        jawHolder.position = v3(0, -0.06, Double(beakP.pos.z) - 0.02)
        let jaw = PetMat.node(SCNCone(topRadius: 0, bottomRadius: 0.085, height: 0.16), amber)
        jaw.eulerAngles = v3(Double.pi / 2, 0, 0)
        jaw.position = v3(0, 0, 0.07)
        jawHolder.addChildNode(jaw)
        jawHolder.position = SCNVector3(Float(jawHolder.position.x), Float(beakP.pos.y) - 0.07, jawHolder.position.z)
        rig.head.addChildNode(jawHolder)

        // Ушки-кисточки
        for side in [-1.0, 1.0] {
            let tuft = PetMat.node(SCNCone(topRadius: 0.0, bottomRadius: 0.17, height: 0.4), dark,
                                   at: v3(side * 0.5, 0.88, 0.0))
            tuft.eulerAngles = v3(0, 0, -side * 0.5)
            rig.head.addChildNode(tuft)
        }

        // Крылья на «плечах»
        var wings: [SCNNode] = []
        for side in [-1.0, 1.0] {
            let shoulder = SCNNode()
            shoulder.position = v3(side * 0.76, 0.3, -0.02)
            shoulder.addChildNode(PetMat.sphere(wingMat, at: v3(side * 0.03, -0.34, 0), scale: v3(0.15, 0.5, 0.34), segments: 32))
            rig.head.addChildNode(shoulder)
            wings.append(shoulder)
        }

        // Лапки
        for side in [-1.0, 1.0] {
            rig.squash.addChildNode(PetMat.sphere(amber, at: v3(side * 0.3, 0.07, 0.46), scale: v3(0.2, 0.09, 0.28)))
        }

        rig.extras = { pose, face, excitement, _ in
            let flap = excitement * (0.35 + 0.35 * sin(pose.time * 15))
            let rest = 0.05 + sin(pose.time * 1.1) * 0.02
            for (i, w) in wings.enumerated() {
                let side = i == 0 ? -1.0 : 1.0
                w.eulerAngles = v3(0, 0, side * (rest + max(0, flap)))
            }
            jawHolder.eulerAngles = v3(face.mouthOpen * 0.55, 0, 0)
        }
        return rig
    }
}
