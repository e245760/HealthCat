import SwiftUI
import SceneKit

struct CatSceneView: UIViewRepresentable {

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = UIColor.clear
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.autoresizingMask = []

        let scene: SCNScene
        if let loadedScene = SCNScene(named: "cat.usdz") {
            scene = loadedScene
        } else {
            scene = makePlaceholderScene()
        }

        scnView.scene = scene
        disableExistingCameras(in: scene)
        setupCamera(in: scene, scnView: scnView)
        setupLighting(in: scene)
        playAllAnimations(in: scene)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - カメラ

    private func disableExistingCameras(in scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            node.camera = nil
        }
    }

    private func setupCamera(in scene: SCNScene, scnView: SCNView) {
        let cameraNode = SCNNode()
        cameraNode.name = "mainCamera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 30  // 望遠気味にして全身を映す

        let (minVec, maxVec) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minVec.x + maxVec.x) / 2,
            (minVec.y + maxVec.y) / 2,
            (minVec.z + maxVec.z) / 2
        )
        let size = SCNVector3(
            maxVec.x - minVec.x,
            maxVec.y - minVec.y,
            maxVec.z - minVec.z
        )
        let maxDim = max(size.x, size.y, size.z)

        // 距離を3.5倍に広げて全身が入るようにする
        let distance = Float(maxDim) * 3.5

        // カメラを少し上から見下ろす角度に
        cameraNode.position = SCNVector3(
            center.x,
            center.y + Float(maxDim) * 0.2,
            center.z + distance
        )
        cameraNode.look(at: SCNVector3(center.x, center.y - Float(maxDim) * 0.1, center.z))

        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }

    // MARK: - ライティング

    private func setupLighting(in scene: SCNScene) {
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 700
        scene.rootNode.addChildNode(ambientNode)

        let keyNode = SCNNode()
        keyNode.light = SCNLight()
        keyNode.light?.type = .directional
        keyNode.light?.intensity = 800
        keyNode.light?.castsShadow = true
        keyNode.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)

        let fillNode = SCNNode()
        fillNode.light = SCNLight()
        fillNode.light?.type = .directional
        fillNode.light?.intensity = 300
        fillNode.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: - アニメーション

    private func playAllAnimations(in scene: SCNScene) {
        playAnimations(in: scene.rootNode)
    }

    private func playAnimations(in node: SCNNode) {
        node.animationKeys.forEach { key in
            node.animationPlayer(forKey: key)?.play()
        }
        node.childNodes.forEach { playAnimations(in: $0) }
    }

    // MARK: - プレースホルダー

    private func makePlaceholderScene() -> SCNScene {
        let scene = SCNScene()
        let sphere = SCNNode(geometry: SCNSphere(radius: 0.5))
        sphere.geometry?.firstMaterial?.diffuse.contents = UIColor.systemOrange
        scene.rootNode.addChildNode(sphere)

        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 3
        rotation.repeatCount = .infinity
        sphere.addAnimation(rotation, forKey: "spin")

        return scene
    }
}
