/*
See LICENSE folder for this sample's licensing information.

Abstract:
Loads SpatialSense ASCII PCD and colored PLY files for native viewing.
*/

import Foundation

enum PointCloudFileLoader {
    enum LoaderError: LocalizedError {
        case invalidHeader
        case unsupportedEncoding
        case malformedData

        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "The point-cloud file header is invalid."
            case .unsupportedEncoding: return "Only SpatialSense ASCII PCD and PLY files are supported."
            case .malformedData: return "The point-cloud geometry is incomplete or malformed."
            }
        }
    }

    static func loadPCD(from url: URL) throws -> [PointCloudExporter.ColoredPoint] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        guard let dataLineIndex = lines.firstIndex(where: { $0.hasPrefix("DATA ") }) else {
            throw LoaderError.invalidHeader
        }
        guard lines[dataLineIndex].lowercased().contains("ascii") else {
            throw LoaderError.unsupportedEncoding
        }

        let fields = lines.first(where: { $0.hasPrefix("FIELDS ") })?
            .split(separator: " ")
            .dropFirst()
            .map(String.init) ?? []
        guard let xIndex = fields.firstIndex(of: "x"),
              let yIndex = fields.firstIndex(of: "y"),
              let zIndex = fields.firstIndex(of: "z") else {
            throw LoaderError.invalidHeader
        }
        let rgbIndex = fields.firstIndex(of: "rgb")
        let redIndex = fields.firstIndex(of: "r")
        let greenIndex = fields.firstIndex(of: "g")
        let blueIndex = fields.firstIndex(of: "b")

        var points: [PointCloudExporter.ColoredPoint] = []
        points.reserveCapacity(max(lines.count - dataLineIndex - 1, 0))
        for line in lines.dropFirst(dataLineIndex + 1) where !line.isEmpty {
            let values = line.split(whereSeparator: \.isWhitespace)
            let minimumCount = max(xIndex, yIndex, zIndex) + 1
            guard values.count >= minimumCount,
                  let x = Float(values[xIndex]),
                  let y = Float(values[yIndex]),
                  let z = Float(values[zIndex]) else {
                continue
            }

            let color: PointCloudExporter.RGBColor
            if let rgbIndex, rgbIndex < values.count {
                color = unpackRGB(String(values[rgbIndex]))
            } else if let redIndex, let greenIndex, let blueIndex,
                      blueIndex < values.count {
                color = PointCloudExporter.RGBColor(
                    red: UInt8(values[redIndex]) ?? 190,
                    green: UInt8(values[greenIndex]) ?? 200,
                    blue: UInt8(values[blueIndex]) ?? 215
                )
            } else {
                color = .fallback
            }
            points.append(.init(position: SIMD3<Float>(x, y, z), color: color))
        }
        guard !points.isEmpty else { throw LoaderError.malformedData }
        return points
    }

    static func loadPLY(from url: URL) throws -> PointCloudExporter.ColoredMesh {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        guard lines.first == "ply",
              lines.contains("format ascii 1.0"),
              let headerEnd = lines.firstIndex(of: "end_header") else {
            throw LoaderError.unsupportedEncoding
        }

        let vertexCount = elementCount(named: "vertex", in: lines[..<headerEnd])
        let faceCount = elementCount(named: "face", in: lines[..<headerEnd])
        guard vertexCount > 0, lines.count >= headerEnd + 1 + vertexCount else {
            throw LoaderError.malformedData
        }

        var vertices: [PointCloudExporter.ColoredPoint] = []
        vertices.reserveCapacity(vertexCount)
        let vertexStart = headerEnd + 1
        for line in lines[vertexStart..<(vertexStart + vertexCount)] {
            let values = line.split(whereSeparator: \.isWhitespace)
            guard values.count >= 6,
                  let x = Float(values[0]),
                  let y = Float(values[1]),
                  let z = Float(values[2]) else {
                throw LoaderError.malformedData
            }
            vertices.append(.init(
                position: SIMD3<Float>(x, y, z),
                color: .init(
                    red: UInt8(values[3]) ?? 190,
                    green: UInt8(values[4]) ?? 200,
                    blue: UInt8(values[5]) ?? 215
                )
            ))
        }

        var faces: [SIMD3<UInt32>] = []
        faces.reserveCapacity(faceCount)
        let faceStart = vertexStart + vertexCount
        let faceEnd = min(faceStart + faceCount, lines.count)
        if faceStart < faceEnd {
            for line in lines[faceStart..<faceEnd] {
                let values = line.split(whereSeparator: \.isWhitespace)
                guard values.count >= 4,
                      values[0] == "3",
                      let a = UInt32(values[1]),
                      let b = UInt32(values[2]),
                      let c = UInt32(values[3]) else {
                    continue
                }
                faces.append(SIMD3<UInt32>(a, b, c))
            }
        }
        return .init(vertices: vertices, faces: faces)
    }

    private static func elementCount(
        named name: String,
        in lines: ArraySlice<String>
    ) -> Int {
        let prefix = "element \(name) "
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return 0 }
        return Int(line.dropFirst(prefix.count)) ?? 0
    }

    private static func unpackRGB(_ value: String) -> PointCloudExporter.RGBColor {
        let packed: UInt32
        if let integer = UInt32(value) {
            packed = integer
        } else if let float = Float(value) {
            packed = float.bitPattern
        } else {
            return .fallback
        }
        return .init(
            red: UInt8((packed >> 16) & 0xff),
            green: UInt8((packed >> 8) & 0xff),
            blue: UInt8(packed & 0xff)
        )
    }
}
