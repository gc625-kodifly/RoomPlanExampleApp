/*
See LICENSE folder for this sample's licensing information.

Abstract:
Extracts world-space vertices from ARKit scene meshes and writes PCD files.
*/

import Foundation
import ARKit

/// Converts ARKit's reconstructed scene mesh into a voxel-filtered point cloud.
enum PointCloudExporter {

    struct RGBColor: Codable, Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        static let fallback = RGBColor(red: 190, green: 200, blue: 215)

        var packedRGB: UInt32 {
            (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
        }
    }

    struct ColoredPoint {
        let position: SIMD3<Float>
        let color: RGBColor
    }

    struct ColoredMesh {
        let vertices: [ColoredPoint]
        let faces: [SIMD3<UInt32>]
    }

    struct ExportResult {
        let points: [ColoredPoint]
        let mesh: ColoredMesh
    }

    struct VoxelKey: Hashable, Comparable {
        let x: Int
        let y: Int
        let z: Int

        static func < (lhs: VoxelKey, rhs: VoxelKey) -> Bool {
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.z < rhs.z
        }
    }

    enum ExportError: LocalizedError {
        case invalidVoxelSize
        case noMeshVertices

        var errorDescription: String? {
            switch self {
            case .invalidVoxelSize:
                return "The point-cloud voxel size must be greater than zero."
            case .noMeshVertices:
                return "No reconstructed mesh vertices are available. Scan more of the room and try again."
            }
        }
    }

    private struct VoxelAccumulator {
        var positionSum = SIMD3<Float>(repeating: 0)
        var redSum = 0
        var greenSum = 0
        var blueSum = 0
        var count = 0

        mutating func add(position: SIMD3<Float>, color: RGBColor) {
            positionSum += position
            redSum += Int(color.red)
            greenSum += Int(color.green)
            blueSum += Int(color.blue)
            count += 1
        }

        var point: ColoredPoint {
            let divisor = Float(max(count, 1))
            return ColoredPoint(
                position: positionSum / divisor,
                color: RGBColor(
                    red: UInt8(redSum / max(count, 1)),
                    green: UInt8(greenSum / max(count, 1)),
                    blue: UInt8(blueSum / max(count, 1))
                )
            )
        }
    }

    /// Builds a voxel-filtered colored point cloud and an unfiltered triangle mesh.
    static func makeExportResult(
        from anchors: [ARMeshAnchor],
        colorsByAnchor: [UUID: [RGBColor]],
        voxelSize: Float = 0.02
    ) throws -> ExportResult {
        guard voxelSize > 0 else { throw ExportError.invalidVoxelSize }

        var meshVertices: [ColoredPoint] = []
        var meshFaces: [SIMD3<UInt32>] = []
        meshVertices.reserveCapacity(anchors.reduce(0) { $0 + $1.geometry.vertices.count })

        for anchor in anchors {
            let vertexOffset = UInt32(meshVertices.count)
            let vertices = anchor.geometry.vertices
            let bufferStart = vertices.buffer.contents().advanced(by: vertices.offset)
            let sampledColors = colorsByAnchor[anchor.identifier] ?? []

            for index in 0..<vertices.count {
                let vertexPointer = bufferStart
                    .advanced(by: index * vertices.stride)
                    .assumingMemoryBound(to: Float.self)
                let localPoint = SIMD4<Float>(
                    vertexPointer[0],
                    vertexPointer[1],
                    vertexPointer[2],
                    1
                )
                let transformed = anchor.transform * localPoint
                let worldPoint = SIMD3<Float>(transformed.x, transformed.y, transformed.z)
                let color = index < sampledColors.count ? sampledColors[index] : .fallback
                meshVertices.append(ColoredPoint(position: worldPoint, color: color))
            }

            appendFaces(
                from: anchor.geometry.faces,
                vertexOffset: vertexOffset,
                to: &meshFaces
            )
        }

        let points = try voxelFiltered(meshVertices, voxelSize: voxelSize)
        return ExportResult(
            points: points,
            mesh: ColoredMesh(vertices: meshVertices, faces: meshFaces)
        )
    }

    static func voxelFiltered(
        _ points: [ColoredPoint],
        voxelSize: Float
    ) throws -> [ColoredPoint] {
        guard voxelSize > 0 else { throw ExportError.invalidVoxelSize }
        guard !points.isEmpty else { throw ExportError.noMeshVertices }

        var voxels: [VoxelKey: VoxelAccumulator] = [:]
        voxels.reserveCapacity(points.count)
        for point in points {
            let key = VoxelKey(
                x: Int(floor(point.position.x / voxelSize)),
                y: Int(floor(point.position.y / voxelSize)),
                z: Int(floor(point.position.z / voxelSize))
            )
            var accumulator = voxels[key] ?? VoxelAccumulator()
            accumulator.add(position: point.position, color: point.color)
            voxels[key] = accumulator
        }
        return voxels.keys.sorted().compactMap { voxels[$0]?.point }
    }

    private static func appendFaces(
        from faces: ARGeometryElement,
        vertexOffset: UInt32,
        to output: inout [SIMD3<UInt32>]
    ) {
        let buffer = faces.buffer.contents()
        for faceIndex in 0..<faces.count {
            let primitiveStart = faceIndex * faces.indexCountPerPrimitive
            var indices = SIMD3<UInt32>(repeating: 0)
            for corner in 0..<min(faces.indexCountPerPrimitive, 3) {
                let indexOffset = (primitiveStart + corner) * faces.bytesPerIndex
                let localIndex: UInt32
                if faces.bytesPerIndex == MemoryLayout<UInt16>.size {
                    localIndex = UInt32(
                        buffer.advanced(by: indexOffset).assumingMemoryBound(to: UInt16.self).pointee
                    )
                } else {
                    localIndex = buffer
                        .advanced(by: indexOffset)
                        .assumingMemoryBound(to: UInt32.self)
                        .pointee
                }
                indices[corner] = vertexOffset + localIndex
            }
            output.append(indices)
        }
    }

    /// Writes an ASCII PCD v0.7 file containing XYZ and packed RGB fields.
    static func writePCD(_ points: [ColoredPoint], to url: URL) throws {
        guard !points.isEmpty else { throw ExportError.noMeshVertices }

        var contents = """
        # .PCD v0.7 - Point Cloud Data file format
        VERSION 0.7
        FIELDS x y z rgb
        SIZE 4 4 4 4
        TYPE F F F F
        COUNT 1 1 1 1
        WIDTH \(points.count)
        HEIGHT 1
        VIEWPOINT 0 0 0 1 0 0 0
        POINTS \(points.count)
        DATA ascii

        """
        contents.reserveCapacity(contents.count + points.count * 36)

        for point in points {
            let packedColor = Float(bitPattern: point.color.packedRGB)
            contents += "\(point.position.x) \(point.position.y) \(point.position.z) \(packedColor)\n"
        }

        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes an ASCII PLY file with per-vertex RGB and triangle faces.
    static func writePLY(_ mesh: ColoredMesh, to url: URL) throws {
        guard !mesh.vertices.isEmpty else { throw ExportError.noMeshVertices }

        var contents = """
        ply
        format ascii 1.0
        comment SpatialSense colored ARKit mesh
        element vertex \(mesh.vertices.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face \(mesh.faces.count)
        property list uchar uint vertex_indices
        end_header

        """
        contents.reserveCapacity(contents.count + mesh.vertices.count * 48 + mesh.faces.count * 32)

        for vertex in mesh.vertices {
            contents += "\(vertex.position.x) \(vertex.position.y) \(vertex.position.z) "
            contents += "\(vertex.color.red) \(vertex.color.green) \(vertex.color.blue)\n"
        }
        for face in mesh.faces {
            contents += "3 \(face.x) \(face.y) \(face.z)\n"
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func export(
        anchors: [ARMeshAnchor],
        to url: URL,
        voxelSize: Float = 0.02
    ) throws -> Int {
        let result = try makeExportResult(
            from: anchors,
            colorsByAnchor: [:],
            voxelSize: voxelSize
        )
        try writePCD(result.points, to: url)
        return result.points.count
    }
}
