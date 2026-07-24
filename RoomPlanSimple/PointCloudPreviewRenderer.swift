/*
See LICENSE folder for this sample's licensing information.

Abstract:
Renders a library thumbnail preview for a saved point cloud / mesh.
*/

import UIKit
import SceneKit

enum PointCloudPreviewRenderer {

    static func image(
        points: [PointCloudExporter.ColoredPoint],
        mesh: PointCloudExporter.ColoredMesh?,
        size: CGSize = CGSize(width: 512, height: 512)
    ) -> UIImage? {
        let sceneView = SCNView(frame: CGRect(origin: .zero, size: size))
        sceneView.backgroundColor = SpatialSenseTheme.Color.studioBackground
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = true
        let scene = SCNScene()
        sceneView.scene = scene

        let root = SCNNode()
        scene.rootNode.addChildNode(root)

        if let mesh, !mesh.faces.isEmpty {
            let node = SCNNode(geometry: makeMeshGeometry(mesh))
            root.addChildNode(node)
        } else if !points.isEmpty {
            let node = SCNNode(geometry: makePointGeometry(points))
            root.addChildNode(node)
        } else {
            return nil
        }

        let framing = mesh?.vertices ?? points
        guard let first = framing.first else { return nil }
        var minimum = first.position
        var maximum = first.position
        for point in framing.dropFirst() {
            minimum = simd_min(minimum, point.position)
            maximum = simd_max(maximum, point.position)
        }
        let center = (minimum + maximum) / 2
        root.position = SCNVector3(-center.x, -center.y, -center.z)

        let extent = maximum - minimum
        let radius = max(extent.x, max(extent.y, extent.z)) * 0.85
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = SCNVector3(radius * 0.75, radius * 0.55, radius * 1.15)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        sceneView.pointOfView = camera

        sceneView.setNeedsDisplay()
        sceneView.layoutIfNeeded()
        return sceneView.snapshot()
    }

    private static func makePointGeometry(
        _ points: [PointCloudExporter.ColoredPoint]
    ) -> SCNGeometry {
        let vertices = points.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        var colors: [Float] = []
        colors.reserveCapacity(points.count * 4)
        for point in points {
            colors.append(Float(point.color.red) / 255)
            colors.append(Float(point.color.green) / 255)
            colors.append(Float(point.color.blue) / 255)
            colors.append(1)
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: 0
        )
        element.pointSize = 0.01
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 6
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]
        return geometry
    }

    private static func makeMeshGeometry(
        _ mesh: PointCloudExporter.ColoredMesh
    ) -> SCNGeometry {
        let indices = mesh.faces.flatMap { [$0.x, $0.y, $0.z] }
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: mesh.faces.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let vertices = mesh.vertices.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        var colors: [Float] = []
        colors.reserveCapacity(mesh.vertices.count * 4)
        for point in mesh.vertices {
            colors.append(Float(point.color.red) / 255)
            colors.append(Float(point.color.green) / 255)
            colors.append(Float(point.color.blue) / 255)
            colors.append(1)
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: mesh.vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.roughness.contents = 0.92
        material.metalness.contents = 0
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }
}
