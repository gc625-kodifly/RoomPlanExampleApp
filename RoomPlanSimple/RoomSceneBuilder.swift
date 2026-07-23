import SceneKit
import UIKit

/// Reconstructs and validates simple room footprints independently of wall array order.
enum FloorFootprint {
    private enum Tolerance {
        static let minimumWallLength: CGFloat = 0.02
        static let duplicatePointDistance: CGFloat = 0.02
        static let minimumPolygonArea: CGFloat = 0.01
        static let collinearityArea: CGFloat = 0.0005
        static let geometricEpsilon: CGFloat = 0.000001
    }

    private struct Segment {
        let id: Int
        let start: CGPoint
        let end: CGPoint
    }

    static func validatedComponentsForReconstruction(
        from data: FloorPlanData
    ) -> [FloorComponent]? {
        guard data.schemaVersion == FloorPlanData.currentSchemaVersion else {
            return nil
        }

        if !data.floorComponents.isEmpty {
            guard data.floorComponents.count == data.floorPolygons.count else {
                return nil
            }
            var validated: [FloorComponent] = []
            validated.reserveCapacity(data.floorComponents.count)
            for (component, compatibilityPolygon) in zip(
                data.floorComponents,
                data.floorPolygons
            ) {
                guard
                    component.elevation.isFinite,
                    let polygon = validatedPersistedPolygon(component.polygon),
                    let compatibility = validatedPersistedPolygon(compatibilityPolygon),
                    equivalentPolygon(polygon, compatibility)
                else {
                    return nil
                }
                validated.append(
                    FloorComponent(polygon: polygon, elevation: component.elevation)
                )
            }
            return validated
        }

        // Schema v3 permits no-floor captures only when no captured component set was
        // declared. Their validated wall boundary remains the reconstruction footprint.
        guard data.floorPolygons.isEmpty else { return nil }
        let wallDerived = boundary(from: data.elements)
        if let polygon = sanitizedPolygon(wallDerived), triangulate(polygon) != nil {
            return [FloorComponent(polygon: polygon, elevation: 0)]
        }
        if let legacy = sanitizedPolygon(data.boundary), triangulate(legacy) != nil {
            return [FloorComponent(polygon: legacy, elevation: 0)]
        }
        return nil
    }

    private static func validatedPersistedPolygon(_ input: [CGPoint]) -> [CGPoint]? {
        guard
            input.count >= 3,
            input.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
            let polygon = sanitizedPolygon(input),
            polygon.count == input.count,
            triangulate(polygon) != nil
        else {
            return nil
        }
        return polygon
    }

    static func resolvedComponents(from data: FloorPlanData) -> [FloorComponent] {
        if data.schemaVersion == FloorPlanData.currentSchemaVersion {
            return validatedComponentsForReconstruction(from: data) ?? []
        }
        let captured = data.floorComponents.compactMap { component -> FloorComponent? in
            guard
                component.elevation.isFinite,
                let polygon = sanitizedPolygon(component.polygon)
            else {
                return nil
            }
            return FloorComponent(polygon: polygon, elevation: component.elevation)
        }
        if !captured.isEmpty {
            return captured
        }
        let wallDerived = boundary(from: data.elements)
        if wallDerived.count >= 3 {
            return [FloorComponent(polygon: wallDerived, elevation: 0)]
        }
        if let legacy = sanitizedPolygon(data.boundary) {
            return [FloorComponent(polygon: legacy, elevation: 0)]
        }
        return []
    }

    private static func equivalentPolygon(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> Bool {
        guard lhs.count == rhs.count, let first = lhs.first else { return false }
        let matchingStarts = rhs.indices.filter {
            distance(first, rhs[$0]) <= Tolerance.geometricEpsilon
        }
        for start in matchingStarts {
            let forwardMatches = lhs.indices.allSatisfy {
                distance(lhs[$0], rhs[(start + $0) % rhs.count])
                    <= Tolerance.geometricEpsilon
            }
            if forwardMatches { return true }
            let reverseMatches = lhs.indices.allSatisfy {
                let rhsIndex = (start - $0 + rhs.count) % rhs.count
                return distance(lhs[$0], rhs[rhsIndex]) <= Tolerance.geometricEpsilon
            }
            if reverseMatches { return true }
        }
        return false
    }

    static func resolvedPolygons(from data: FloorPlanData) -> [[CGPoint]] {
        resolvedComponents(from: data).map(\.polygon)
    }

    static func boundary(from elements: [FloorPlanElement]) -> [CGPoint] {
        let walls = elements.filter {
            if case .wall = $0.type { return $0.rect.width > Tolerance.minimumWallLength }
            return false
        }
        guard walls.count >= 3 else { return [] }

        var segments = walls.map { wall -> Segment in
            let center = CGPoint(x: wall.rect.midX, y: wall.rect.midY)
            let offset = CGPoint(
                x: cos(wall.rotation) * wall.rect.width / 2,
                y: sin(wall.rotation) * wall.rect.width / 2
            )
            return Segment(
                id: 0,
                start: CGPoint(x: center.x - offset.x, y: center.y - offset.y),
                end: CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            )
        }
        segments.sort {
            let lhs = minPoint($0.start, $0.end)
            let rhs = minPoint($1.start, $1.end)
            return lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
        segments = segments.enumerated().map {
            Segment(id: $0.offset, start: $0.element.start, end: $0.element.end)
        }

        let lengths = segments.map { distance($0.start, $0.end) }.sorted()
        let median = lengths[lengths.count / 2]
        let tolerance = min(max(0.12, median * 0.08), 0.35)
        var vertices: [CGPoint] = []
        var vertexSampleCounts: [CGFloat] = []
        func vertexIndex(for point: CGPoint) -> Int {
            if let index = vertices.firstIndex(where: { distance($0, point) <= tolerance }) {
                let count = vertexSampleCounts[index]
                vertices[index] = CGPoint(
                    x: (vertices[index].x * count + point.x) / (count + 1),
                    y: (vertices[index].y * count + point.y) / (count + 1)
                )
                vertexSampleCounts[index] += 1
                return index
            }
            vertices.append(point)
            vertexSampleCounts.append(1)
            return vertices.count - 1
        }

        var edges: [(Int, Int)] = []
        for segment in segments {
            let start = vertexIndex(for: segment.start)
            let end = vertexIndex(for: segment.end)
            if start != end && !edges.contains(where: { ($0 == (start, end)) || ($0 == (end, start)) }) {
                edges.append((start, end))
            }
        }

        var neighbors = Array(repeating: [Int](), count: vertices.count)
        for edge in edges {
            neighbors[edge.0].append(edge.1)
            neighbors[edge.1].append(edge.0)
        }
        for vertex in vertices.indices {
            neighbors[vertex].sort {
                atan2(vertices[$0].y - vertices[vertex].y, vertices[$0].x - vertices[vertex].x)
                    < atan2(vertices[$1].y - vertices[vertex].y, vertices[$1].x - vertices[vertex].x)
            }
        }

        struct HalfEdge: Hashable {
            let from: Int
            let to: Int
        }
        var visited = Set<HalfEdge>()
        var polygons: [[CGPoint]] = []
        for edge in edges {
            for start in [HalfEdge(from: edge.0, to: edge.1), HalfEdge(from: edge.1, to: edge.0)] {
                guard !visited.contains(start) else { continue }
                var current = start
                var indices: [Int] = []
                repeat {
                    guard !visited.contains(current), indices.count <= edges.count else {
                        indices.removeAll()
                        break
                    }
                    visited.insert(current)
                    indices.append(current.from)
                    guard
                        let reverseIndex = neighbors[current.to].firstIndex(of: current.from),
                        !neighbors[current.to].isEmpty
                    else {
                        indices.removeAll()
                        break
                    }
                    let nextIndex = (reverseIndex - 1 + neighbors[current.to].count) % neighbors[current.to].count
                    current = HalfEdge(from: current.to, to: neighbors[current.to][nextIndex])
                } while current != start

                if current == start,
                   let polygon = sanitizedPolygon(indices.map { vertices[$0] }) {
                    polygons.append(polygon)
                }
            }
        }
        return polygons.max { area(of: $0) < area(of: $1) } ?? []
    }

    static func sanitizedPolygon(_ input: [CGPoint]) -> [CGPoint]? {
        var points: [CGPoint] = []
        for point in input where point.x.isFinite && point.y.isFinite {
            if points.last.map({ distance($0, point) > Tolerance.duplicatePointDistance }) ?? true {
                points.append(point)
            }
        }
        if points.count > 2, distance(points[0], points[points.count - 1]) <= Tolerance.duplicatePointDistance {
            points.removeLast()
        }

        var changed = true
        while changed, points.count >= 3 {
            changed = false
            for index in points.indices {
                let previous = points[(index - 1 + points.count) % points.count]
                let current = points[index]
                let next = points[(index + 1) % points.count]
                if abs(cross(previous, current, next)) <= Tolerance.collinearityArea,
                   dot(current, previous, next) <= 0 {
                    points.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        guard points.count >= 3, area(of: points) > Tolerance.minimumPolygonArea, isSimple(points) else { return nil }
        if signedArea(points) < 0 {
            points.reverse()
        }
        return points
    }

    static func area(of points: [CGPoint]) -> CGFloat {
        abs(signedArea(points))
    }

    static func triangulate(_ input: [CGPoint]) -> [Int]? {
        guard let points = sanitizedPolygon(input) else { return nil }
        var remaining = Array(points.indices)
        var result: [Int] = []
        var attempts = 0

        while remaining.count > 3, attempts < points.count * points.count {
            var clipped = false
            for position in remaining.indices {
                let previous = remaining[(position - 1 + remaining.count) % remaining.count]
                let current = remaining[position]
                let next = remaining[(position + 1) % remaining.count]
                guard cross(points[previous], points[current], points[next]) > Tolerance.geometricEpsilon else {
                    continue
                }
                let containsVertex = remaining.contains { candidate in
                    candidate != previous && candidate != current && candidate != next
                        && point(points[candidate], inTriangle: points[previous], points[current], points[next])
                }
                if !containsVertex {
                    result.append(contentsOf: [previous, current, next])
                    remaining.remove(at: position)
                    clipped = true
                    break
                }
            }
            guard clipped else { return nil }
            attempts += 1
        }
        guard remaining.count == 3 else { return nil }
        result.append(contentsOf: remaining)
        return result
    }

    private static func isSimple(_ points: [CGPoint]) -> Bool {
        for first in points.indices {
            let firstNext = (first + 1) % points.count
            for second in points.indices where second > first {
                let secondNext = (second + 1) % points.count
                if first == second || firstNext == second || secondNext == first {
                    continue
                }
                if segmentsIntersect(points[first], points[firstNext], points[second], points[secondNext]) {
                    return false
                }
            }
        }
        return true
    }

    private static func segmentsIntersect(
        _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint
    ) -> Bool {
        let abC = cross(a, b, c)
        let abD = cross(a, b, d)
        let cdA = cross(c, d, a)
        let cdB = cross(c, d, b)
        return abC * abD < -Tolerance.geometricEpsilon && cdA * cdB < -Tolerance.geometricEpsilon
    }

    private static func point(
        _ point: CGPoint, inTriangle a: CGPoint, _ b: CGPoint, _ c: CGPoint
    ) -> Bool {
        let c1 = cross(a, b, point)
        let c2 = cross(b, c, point)
        let c3 = cross(c, a, point)
        return c1 >= -Tolerance.geometricEpsilon
            && c2 >= -Tolerance.geometricEpsilon
            && c3 >= -Tolerance.geometricEpsilon
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        return points.indices.reduce(0) { sum, index in
            let next = points[(index + 1) % points.count]
            return sum + points[index].x * next.y - next.x * points[index].y
        } / 2
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func dot(_ center: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - center.x) * (b.x - center.x) + (a.y - center.y) * (b.y - center.y)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func minPoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        lhs.x == rhs.x ? (lhs.y < rhs.y ? lhs : rhs) : (lhs.x < rhs.x ? lhs : rhs)
    }
}

enum SceneCameraFit {
    static func distance(
        toFit extent: SIMD3<Float>,
        verticalFieldOfViewDegrees: Float = 48,
        aspectRatio: Float,
        padding: Float = 1.15
    ) -> Float {
        let radius = max(simd_length(extent) / 2, 0.01)
        let verticalHalfFOV = verticalFieldOfViewDegrees * .pi / 360
        let safeAspect = max(aspectRatio.isFinite ? aspectRatio : 1, 0.01)
        let horizontalHalfFOV = atan(tan(verticalHalfFOV) * safeAspect)
        let limitingHalfFOV = max(min(verticalHalfFOV, horizontalHalfFOV), 0.01)
        return radius / sin(limitingHalfFOV) * max(padding, 1)
    }
}

/// Builds an offline SceneKit representation from RoomPlan's measured primitives.
/// Furniture comes from bundled Kenney models and stays inside the captured volume.
enum RoomSceneBuilder {
    static func canBuildScene(from data: FloorPlanData) -> Bool {
        guard
            FloorPlanData.supportedReconstructionSchemaVersions.contains(data.schemaVersion),
            let datum = data.verticalDatum,
            datum.isFinite
        else {
            return false
        }
        guard let components = FloorFootprint.validatedComponentsForReconstruction(
            from: data
        ) else {
            return false
        }
        return !components.isEmpty
    }

    static func makeScene(
        from data: FloorPlanData,
        viewportSize: CGSize = CGSize(width: 1, height: 1)
    ) -> SCNScene {
        let scene = SCNScene()
        guard let components = FloorFootprint.validatedComponentsForReconstruction(
            from: data
        ) else {
            return scene
        }
        let content = SCNNode()
        content.name = "Measured room"
        scene.rootNode.addChildNode(content)

        addFloor(components: components, to: content)
        for element in data.elements {
            switch element.type {
            case .wall:
                addSurface(element, material: Materials.wall, to: content)
            case .door:
                addSurface(element, material: Materials.door, inset: 0.012, to: content)
            case .window:
                addSurface(element, material: Materials.glass, inset: 0.018, to: content)
            case .opening:
                continue
            case .object(let category):
                addFurniture(element, category: category, to: content)
            }
        }

        addEnvironment(to: scene, content: content, viewportSize: viewportSize)
        return scene
    }

    static func refitCamera(in scene: SCNScene, viewportSize: CGSize) {
        guard
            let content = scene.rootNode.childNode(withName: "Measured room", recursively: false),
            let target = scene.rootNode.childNode(withName: "Camera target", recursively: false),
            let cameraNode = scene.rootNode.childNode(withName: "Camera", recursively: false),
            let camera = cameraNode.camera
        else {
            return
        }
        fit(
            cameraNode: cameraNode,
            camera: camera,
            target: target,
            bounds: content.boundingBox,
            viewportSize: viewportSize
        )
    }

    private static func addFloor(
        components: [FloorComponent],
        to parent: SCNNode
    ) {
        for (index, component) in components.enumerated() {
            guard let geometry = floorGeometry(for: component.polygon) else { continue }
            let node = SCNNode(geometry: geometry)
            node.name = index == 0 ? "Floor" : "Floor \(index + 1)"
            node.position.y = Float(component.elevation)
            parent.addChildNode(node)
        }
    }

    private static func floorGeometry(for input: [CGPoint]) -> SCNGeometry? {
        guard
            let points = FloorFootprint.sanitizedPolygon(input),
            let triangles = FloorFootprint.triangulate(points)
        else {
            return nil
        }
        let thickness: Float = 0.025
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []

        func appendTriangle(
            _ first: SCNVector3,
            _ second: SCNVector3,
            _ third: SCNVector3,
            normal: SCNVector3
        ) {
            let base = UInt32(vertices.count)
            vertices.append(contentsOf: [first, second, third])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        for triangle in stride(from: 0, to: triangles.count, by: 3) {
            let a = points[triangles[triangle]]
            let b = points[triangles[triangle + 1]]
            let c = points[triangles[triangle + 2]]
            let topA = SCNVector3(Float(a.x), 0, Float(a.y))
            let topB = SCNVector3(Float(b.x), 0, Float(b.y))
            let topC = SCNVector3(Float(c.x), 0, Float(c.y))
            let bottomA = SCNVector3(Float(a.x), -thickness, Float(a.y))
            let bottomB = SCNVector3(Float(b.x), -thickness, Float(b.y))
            let bottomC = SCNVector3(Float(c.x), -thickness, Float(c.y))
            appendTriangle(topA, topC, topB, normal: SCNVector3(0, 1, 0))
            appendTriangle(bottomA, bottomB, bottomC, normal: SCNVector3(0, -1, 0))
        }

        for index in points.indices {
            let next = (index + 1) % points.count
            let a = points[index]
            let b = points[next]
            let dx = Float(b.x - a.x)
            let dz = Float(b.y - a.y)
            let length = max(sqrt(dx * dx + dz * dz), 0.0001)
            let normal = SCNVector3(dz / length, 0, -dx / length)
            let topA = SCNVector3(Float(a.x), 0, Float(a.y))
            let topB = SCNVector3(Float(b.x), 0, Float(b.y))
            let bottomA = SCNVector3(Float(a.x), -thickness, Float(a.y))
            let bottomB = SCNVector3(Float(b.x), -thickness, Float(b.y))
            appendTriangle(topA, bottomB, bottomA, normal: normal)
            appendTriangle(topA, topB, bottomB, normal: normal)
        }

        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals)
            ],
            elements: [element]
        )
        geometry.materials = [Materials.floor]
        return geometry
    }

    private static func addSurface(
        _ element: FloorPlanElement,
        material: SCNMaterial,
        inset: CGFloat = 0,
        to parent: SCNNode
    ) {
        guard let height = element.verticalExtent, let elevation = element.elevation, height > 0 else {
            return
        }
        let width = max(element.rect.width - inset * 2, 0.02)
        let thickness = max(element.rect.height + inset, 0.035)
        let box = SCNBox(width: width, height: height, length: thickness, chamferRadius: 0.006)
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.name = element.label ?? surfaceName(element.type)
        node.position = SCNVector3(Float(element.rect.midX), Float(elevation), Float(element.rect.midY))
        node.eulerAngles.y = -Float(element.rotation)
        parent.addChildNode(node)
    }

    private static func surfaceName(_ type: FloorPlanElement.ElementType) -> String {
        switch type {
        case .wall: return "Wall"
        case .door: return "Door"
        case .window: return "Window"
        case .opening: return "Opening"
        case .object(let category): return category
        }
    }

    private static func addFurniture(
        _ element: FloorPlanElement,
        category: String,
        to parent: SCNNode
    ) {
        guard let height = element.verticalExtent, let elevation = element.elevation, height > 0 else {
            return
        }
        let dimensions = SIMD3<Float>(
            Float(max(element.rect.width, 0.05)),
            Float(max(height, 0.05)),
            Float(max(element.rect.height, 0.05))
        )
        let kind = FurnitureAssetKind(category)
        let asset = FurnitureNodeFactory.make(
            kind: kind,
            size: dimensions
        )
        asset.name = element.label ?? category
        asset.position = SCNVector3(Float(element.rect.midX), Float(elevation), Float(element.rect.midY))
        var yaw = -Float(element.rotation)
        if kind == .chair {
            yaw += Float.pi
        }
        asset.eulerAngles.y = yaw
        parent.addChildNode(asset)
    }

    private static func addEnvironment(
        to scene: SCNScene,
        content: SCNNode,
        viewportSize: CGSize
    ) {
        scene.background.contents = UIColor(red: 0.055, green: 0.065, blue: 0.085, alpha: 1)
        scene.lightingEnvironment.contents = UIColor(white: 0.72, alpha: 1)
        scene.lightingEnvironment.intensity = 0.65

        let (minimum, maximum) = content.boundingBox
        let center = SCNVector3(
            (minimum.x + maximum.x) / 2,
            (minimum.y + maximum.y) / 2,
            (minimum.z + maximum.z) / 2
        )
        let target = SCNNode()
        target.name = "Camera target"
        target.position = center
        scene.rootNode.addChildNode(target)

        let camera = SCNCamera()
        camera.fieldOfView = 48
        camera.zNear = 0.02
        camera.wantsHDR = true
        let cameraNode = SCNNode()
        cameraNode.name = "Camera"
        cameraNode.camera = camera
        let lookAt = SCNLookAtConstraint(target: target)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]
        scene.rootNode.addChildNode(cameraNode)
        fit(
            cameraNode: cameraNode,
            camera: camera,
            target: target,
            bounds: (minimum, maximum),
            viewportSize: viewportSize
        )

        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.castsShadow = false
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.9, 0.65, 0)
        scene.rootNode.addChildNode(keyNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 380
        ambient.color = UIColor(red: 0.72, green: 0.78, blue: 0.9, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private static func fit(
        cameraNode: SCNNode,
        camera: SCNCamera,
        target: SCNNode,
        bounds: (SCNVector3, SCNVector3),
        viewportSize: CGSize
    ) {
        let minimum = bounds.0
        let maximum = bounds.1
        let center = SCNVector3(
            (minimum.x + maximum.x) / 2,
            (minimum.y + maximum.y) / 2,
            (minimum.z + maximum.z) / 2
        )
        let extent = SIMD3<Float>(
            maximum.x - minimum.x,
            maximum.y - minimum.y,
            maximum.z - minimum.z
        )
        let aspect = Float(viewportSize.width / max(viewportSize.height, 1))
        let distance = SceneCameraFit.distance(
            toFit: extent,
            verticalFieldOfViewDegrees: Float(camera.fieldOfView),
            aspectRatio: aspect
        )
        let direction = simd_normalize(SIMD3<Float>(0.55, 0.45, 0.72))
        target.position = center
        camera.zFar = Double(max(distance + simd_length(extent) * 2, 40))
        cameraNode.position = SCNVector3(
            center.x + direction.x * distance,
            center.y + direction.y * distance,
            center.z + direction.z * distance
        )
    }
}

enum FurnitureAssetKind: String, CaseIterable, Equatable {
    case bed, storage, refrigerator, stove, oven, dishwasher, washerDryer
    case table, sofa, chair
    case sink, toilet, bathtub, television, fireplace, stairs, unknown

    static let currentRoomPlanCategories = allCases.filter { $0 != .unknown }

    var assetResourceName: String? {
        self == .unknown ? nil : rawValue
    }

    var isSemanticProxy: Bool {
        switch self {
        case .oven, .dishwasher, .fireplace: return true
        default: return false
        }
    }

    var proxySourceDescription: String? {
        switch self {
        case .oven: return "Kenney electric stove proxy"
        case .dishwasher: return "Kenney kitchen cabinet proxy"
        case .fireplace: return "Kenney kitchen stove proxy"
        default: return nil
        }
    }

    init(_ category: String) {
        let value = category.lowercased()
        switch value {
        case let s where s.contains("bed"): self = .bed
        case let s where s.contains("storage"): self = .storage
        case let s where s.contains("refrigerator"): self = .refrigerator
        case let s where s.contains("stove"): self = .stove
        case let s where s.contains("dishwasher"): self = .dishwasher
        case let s where s.contains("washer"): self = .washerDryer
        case let s where s.contains("oven"): self = .oven
        case let s where s.contains("table"): self = .table
        case let s where s.contains("sofa"): self = .sofa
        case let s where s.contains("chair"): self = .chair
        case let s where s.contains("sink"): self = .sink
        case let s where s.contains("toilet"): self = .toilet
        case let s where s.contains("bathtub"): self = .bathtub
        case let s where s.contains("television"): self = .television
        case let s where s.contains("fireplace"): self = .fireplace
        case let s where s.contains("stairs"): self = .stairs
        default: self = .unknown
        }
    }
}

enum FurnitureAssetCatalog {
    static let resourceDirectory = "FurnitureAssets"

    static func assetURL(for kind: FurnitureAssetKind, bundle: Bundle = .main) -> URL? {
        guard let resourceName = kind.assetResourceName else { return nil }
        return bundle.url(
            forResource: resourceName,
            withExtension: "usdz",
            subdirectory: resourceDirectory
        )
    }

    static func makeNode(
        kind: FurnitureAssetKind,
        fitting measuredSize: SIMD3<Float>,
        bundle: Bundle = .main
    ) -> SCNNode? {
        guard
            let url = assetURL(for: kind, bundle: bundle),
            let scene = try? SCNScene(url: url, options: nil)
        else {
            return nil
        }

        let model = SCNNode()
        scene.rootNode.childNodes.forEach { model.addChildNode($0.clone()) }
        guard !model.childNodes.isEmpty else { return nil }

        let (minimum, maximum) = model.boundingBox

        let sourceSize = SIMD3<Float>(
            maximum.x - minimum.x,
            maximum.y - minimum.y,
            maximum.z - minimum.z
        )
        guard sourceSize.x > 0, sourceSize.y > 0, sourceSize.z > 0 else { return nil }

        // One uniform scale preserves the artist's proportions. The small inset avoids
        // z-fighting with measured walls while keeping the model inside its RoomPlan box.
        let available = measuredSize * SIMD3<Float>(repeating: 0.94)
        let scale = min(
            available.x / sourceSize.x,
            available.y / sourceSize.y,
            available.z / sourceSize.z
        )
        guard scale.isFinite, scale > 0 else { return nil }

        model.scale = SCNVector3(scale, scale, scale)
        model.position = SCNVector3(
            -(minimum.x + maximum.x) * 0.5 * scale,
            -measuredSize.y * 0.5 - minimum.y * scale,
            -(minimum.z + maximum.z) * 0.5 * scale
        )
        model.enumerateChildNodes { node, _ in
            node.geometry?.materials.forEach {
                $0.lightingModel = .physicallyBased
                $0.roughness.contents = 0.72
            }
        }

        let root = SCNNode()
        root.name = "Kenney \(kind.rawValue)"
        root.addChildNode(model)
        return root
    }
}

private enum FurnitureNodeFactory {
    static func make(kind: FurnitureAssetKind, size: SIMD3<Float>) -> SCNNode {
        if let asset = FurnitureAssetCatalog.makeNode(kind: kind, fitting: size) {
            return asset
        }

        // A neutral measured box is intentionally the only missing/future fallback.
        let root = SCNNode()
        root.name = "Neutral furniture fallback"
        let fittedSize = size * SIMD3<Float>(0.94, 0.94, 0.94)
        let geometry = SCNBox(
            width: CGFloat(max(fittedSize.x, 0.005)),
            height: CGFloat(max(fittedSize.y, 0.005)),
            length: CGFloat(max(fittedSize.z, 0.005)),
            chamferRadius: 0
        )
        geometry.materials = [Materials.unknown]
        let node = SCNNode(geometry: geometry)
        node.name = "Neutral furniture fallback"
        root.addChildNode(node)
        return root
    }
}

private enum Materials {
    static let wall = material(UIColor(red: 0.77, green: 0.79, blue: 0.83, alpha: 1), roughness: 0.82)
    static let floor = material(UIColor(red: 0.34, green: 0.28, blue: 0.22, alpha: 1), roughness: 0.72)
    static let door = material(UIColor(red: 0.48, green: 0.30, blue: 0.18, alpha: 1), roughness: 0.68)
    static let glass = material(UIColor(red: 0.35, green: 0.72, blue: 0.94, alpha: 0.42), roughness: 0.16, metalness: 0.05)
    static let unknown = material(UIColor(red: 0.48, green: 0.50, blue: 0.54, alpha: 1), roughness: 0.78)

    private static func material(
        _ color: UIColor,
        roughness: CGFloat,
        metalness: CGFloat = 0
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        material.isDoubleSided = color.cgColor.alpha < 1
        material.transparency = color.cgColor.alpha
        return material
    }
}
