import SwiftUI
import SceneKit
import Metal
import UIKit

/// Настоящий 3D-питомец на экране. Поза приходит из сцены каждый кадр, SceneKit только рисует:
/// касания обрабатывает SwiftUI-слой сцены, поэтому сам вид их не перехватывает.
struct Pet3DView: UIViewRepresentable {
    var characterID: String
    var tintHex: String
    var pose: Pet3DPose
    /// Доля высоты кадра, которую занимает питомец (как у яйца).
    var fill: CGFloat = 0.8

    func makeCoordinator() -> Pet3DCoordinator { Pet3DCoordinator() }

    func makeUIView(context: Context) -> Pet3DSCNView {
        let v = Pet3DSCNView(frame: .zero, options: nil)
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = Motion.enabled
        v.allowsCameraControl = false
        context.coordinator.setup(view: v, characterID: characterID, tintHex: tintHex, fill: fill)
        context.coordinator.apply(pose)
        return v
    }

    func updateUIView(_ v: Pet3DSCNView, context: Context) {
        context.coordinator.apply(pose)
    }

    static func dismantleUIView(_ v: Pet3DSCNView, coordinator: Pet3DCoordinator) {
        v.isPlaying = false
        v.scene = nil
    }
}

/// Рисует только пока вид в окне — вне экрана не тратит батарею.
final class Pet3DSCNView: SCNView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        isPlaying = window != nil
    }
}

@MainActor
final class Pet3DCoordinator {
    private var rig: PetRig?

    func setup(view: SCNView, characterID: String, tintHex: String, fill: CGFloat) {
        let built = Pet3DStage.build(characterID: characterID, tintHex: tintHex, fill: fill)
        view.scene = built.scene
        rig = built.rig
    }

    func apply(_ pose: Pet3DPose) {
        rig?.apply(pose)
    }
}

/// Сцена для питомца: камера, свет, окружение. Общая для экрана и для снимков.
@MainActor
enum Pet3DStage {
    static func build(characterID: String, tintHex: String, fill: CGFloat) -> (scene: SCNScene, rig: PetRig) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = EggArt.environment()
        scene.lightingEnvironment.intensity = 1.1

        // Камера как у яйца: питомец высотой 2 занимает `fill` кадра, основание ближе к низу
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 0.1
        cam.zFar = 100
        let half = 1.0 / Double(max(0.2, fill))
        let distance = half / tan(15 * Double.pi / 180)
        let centerY = 1 + (half - 1.0) * 0.6
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = v3(0, centerY, distance)
        camNode.look(at: v3(0, centerY, 0))
        scene.rootNode.addChildNode(camNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 800
        rim.light?.color = EggArt.color(tintHex).mixed(with: .white, 0.4)
        rim.position = SCNVector3(0.4, 2.4, -2.6)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        scene.rootNode.addChildNode(ambient)

        let rig = PetModels.rig(id: characterID, tintHex: tintHex)
        scene.rootNode.addChildNode(rig.root)
        return (scene, rig)
    }
}

/// Картинка 3D-питомца для мест, где нужна обычная иллюстрация: аватарки, виджет, список.
/// Рисуется один раз на персонажа за кадр SceneKit без окна и запоминается.
@MainActor
enum Pet3DSnapshot {
    private static var cache: [String: UIImage] = [:]

    static func image(for character: CompanionCharacter, side: CGFloat = 360) -> UIImage? {
        guard character.model3D else { return nil }
        if let hit = cache[character.id] { return hit }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let built = Pet3DStage.build(characterID: character.id, tintHex: character.tintHex, fill: 0.86)
        var pose = Pet3DPose()
        pose.time = 1
        pose.face = PetBrain.target(.happy, intensity: 1)
        // Несколько кадров подряд — лицо успевает дойти до цели
        for i in 0..<8 {
            pose.time = 1 + Double(i) * 0.05
            built.rig.apply(pose)
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = built.scene
        renderer.pointOfView = built.scene.rootNode.childNodes.first { $0.camera != nil }
        let size = CGSize(width: side, height: side)
        let image = renderer.snapshot(atTime: 1.4, with: size, antialiasingMode: .multisampling4X)
        cache[character.id] = image
        return image
    }
}
