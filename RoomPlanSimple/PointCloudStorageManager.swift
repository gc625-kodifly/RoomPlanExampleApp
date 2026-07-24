/*
See LICENSE folder for this sample's licensing information.

Abstract:
Persists PCD captures, previews, and metadata for the capture library.
*/

import Foundation
import UIKit
import ARKit

struct SavedPointCloud: Codable, Identifiable {
    let id: UUID
    var name: String
    let date: Date
    let pointCount: Int
    let fileName: String
    let meshFileName: String?
    let previewFileName: String?
    let triangleCount: Int
    let hasColor: Bool

    init(
        id: UUID,
        name: String,
        date: Date,
        pointCount: Int,
        fileName: String,
        meshFileName: String? = nil,
        previewFileName: String? = nil,
        triangleCount: Int = 0,
        hasColor: Bool = false
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.pointCount = pointCount
        self.fileName = fileName
        self.meshFileName = meshFileName
        self.previewFileName = previewFileName
        self.triangleCount = triangleCount
        self.hasColor = hasColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        pointCount = try container.decode(Int.self, forKey: .pointCount)
        fileName = try container.decode(String.self, forKey: .fileName)
        meshFileName = try container.decodeIfPresent(String.self, forKey: .meshFileName)
        previewFileName = try container.decodeIfPresent(String.self, forKey: .previewFileName)
        triangleCount = try container.decodeIfPresent(Int.self, forKey: .triangleCount) ?? 0
        hasColor = try container.decodeIfPresent(Bool.self, forKey: .hasColor) ?? false
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

final class PointCloudStorageManager {
    static let shared = PointCloudStorageManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var directory: URL {
        get throws {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documents.appendingPathComponent("PointClouds", isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    private init() {}

    func save(
        anchors: [ARMeshAnchor],
        colorsByAnchor: [UUID: [PointCloudExporter.RGBColor]] = [:],
        voxelSize: Float = 0.02,
        previewImage: UIImage? = nil
    ) throws -> SavedPointCloud {
        let id = UUID()
        let date = Date()
        let stamp = "\(timestamp(date))_\(id.uuidString.prefix(8))"
        let fileName = "SpatialSense_\(stamp).pcd"
        let meshFileName = "SpatialSense_\(stamp).ply"
        let previewFileName = "SpatialSense_\(stamp)_preview.png"
        let storageDirectory = try directory
        let pcdURL = storageDirectory.appendingPathComponent(fileName)
        let plyURL = storageDirectory.appendingPathComponent(meshFileName)
        let previewURL = storageDirectory.appendingPathComponent(previewFileName)
        let result = try PointCloudExporter.makeExportResult(
            from: anchors,
            colorsByAnchor: colorsByAnchor,
            voxelSize: voxelSize
        )
        try PointCloudExporter.writePCD(result.points, to: pcdURL)
        do {
            try PointCloudExporter.writePLY(result.mesh, to: plyURL)
        } catch {
            try? fileManager.removeItem(at: pcdURL)
            throw error
        }

        let resolvedPreview = previewImage ?? PointCloudPreviewRenderer.image(
            points: result.points,
            mesh: result.mesh
        )
        var storedPreviewName: String?
        if let resolvedPreview, let data = resolvedPreview.pngData() {
            try? data.write(to: previewURL, options: .atomic)
            storedPreviewName = previewFileName
        }

        let capture = SavedPointCloud(
            id: id,
            name: "Point Cloud \(displayTimestamp(date))",
            date: date,
            pointCount: result.points.count,
            fileName: fileName,
            meshFileName: meshFileName,
            previewFileName: storedPreviewName,
            triangleCount: result.mesh.faces.count,
            hasColor: !colorsByAnchor.isEmpty
        )

        let metadataURL = storageDirectory.appendingPathComponent("\(id.uuidString).pointcloud.json")
        do {
            try encoder.encode(capture).write(to: metadataURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: pcdURL)
            try? fileManager.removeItem(at: plyURL)
            if let storedPreviewName {
                try? fileManager.removeItem(at: storageDirectory.appendingPathComponent(storedPreviewName))
            }
            throw error
        }
        return capture
    }

    func save(
        exportResult result: PointCloudExporter.ExportResult,
        hasColor: Bool,
        previewImage: UIImage? = nil,
        name: String? = nil
    ) throws -> SavedPointCloud {
        let id = UUID()
        let date = Date()
        let stamp = "\(timestamp(date))_\(id.uuidString.prefix(8))"
        let fileName = "SpatialSense_\(stamp).pcd"
        let meshFileName = "SpatialSense_\(stamp).ply"
        let previewFileName = "SpatialSense_\(stamp)_preview.png"
        let storageDirectory = try directory
        let pcdURL = storageDirectory.appendingPathComponent(fileName)
        let plyURL = storageDirectory.appendingPathComponent(meshFileName)
        let previewURL = storageDirectory.appendingPathComponent(previewFileName)

        try PointCloudExporter.writePCD(result.points, to: pcdURL)
        try PointCloudExporter.writePLY(result.mesh, to: plyURL)

        let resolvedPreview = previewImage ?? PointCloudPreviewRenderer.image(
            points: result.points,
            mesh: result.mesh
        )
        var storedPreviewName: String?
        if let resolvedPreview, let data = resolvedPreview.pngData() {
            try? data.write(to: previewURL, options: .atomic)
            storedPreviewName = previewFileName
        }

        let resolvedName = {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? Self.suggestedName(date: date) : trimmed
        }()

        let capture = SavedPointCloud(
            id: id,
            name: resolvedName,
            date: date,
            pointCount: result.points.count,
            fileName: fileName,
            meshFileName: meshFileName,
            previewFileName: storedPreviewName,
            triangleCount: result.mesh.faces.count,
            hasColor: hasColor
        )
        let metadataURL = storageDirectory.appendingPathComponent("\(id.uuidString).pointcloud.json")
        try encoder.encode(capture).write(to: metadataURL, options: .atomic)
        return capture
    }

    static func suggestedName(date: Date = Date()) -> String {
        "Point Cloud \(sharedDisplayTimestamp(date))"
    }

    private static func sharedDisplayTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func update(_ capture: SavedPointCloud) throws {
        let metadataURL = try directory.appendingPathComponent("\(capture.id.uuidString).pointcloud.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try encoder.encode(capture).write(to: metadataURL, options: .atomic)
    }

    func getSavedPointClouds() -> [SavedPointCloud] {
        guard let directory = try? directory,
              let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var captures = files
            .filter { $0.lastPathComponent.hasSuffix(".pointcloud.json") }
            .compactMap { url -> SavedPointCloud? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SavedPointCloud.self, from: data)
            }

        let indexedFiles = Set(captures.map(\.fileName))
        let unindexed = files
            .filter { $0.pathExtension.lowercased() == "pcd" && !indexedFiles.contains($0.lastPathComponent) }
            .map { url -> SavedPointCloud in
                let values = try? url.resourceValues(forKeys: [.creationDateKey])
                let date = values?.creationDate ?? Date()
                return SavedPointCloud(
                    id: UUID(),
                    name: url.deletingPathExtension().lastPathComponent,
                    date: date,
                    pointCount: Self.readPointCount(from: url),
                    fileName: url.lastPathComponent,
                    meshFileName: nil,
                    previewFileName: nil,
                    triangleCount: 0,
                    hasColor: Self.hasRGBField(in: url)
                )
            }
        captures.append(contentsOf: unindexed)
        return captures.sorted { $0.date > $1.date }
    }

    func fileURL(for capture: SavedPointCloud) throws -> URL {
        try directory.appendingPathComponent(capture.fileName)
    }

    func meshFileURL(for capture: SavedPointCloud) throws -> URL? {
        guard let meshFileName = capture.meshFileName else { return nil }
        let url = try directory.appendingPathComponent(meshFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func previewImage(for capture: SavedPointCloud) -> UIImage? {
        guard let previewFileName = capture.previewFileName,
              let directory = try? directory else { return nil }
        let url = directory.appendingPathComponent(previewFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func delete(_ capture: SavedPointCloud) throws {
        let directory = try directory
        try? fileManager.removeItem(at: directory.appendingPathComponent(capture.fileName))
        if let meshFileName = capture.meshFileName {
            try? fileManager.removeItem(at: directory.appendingPathComponent(meshFileName))
        }
        if let previewFileName = capture.previewFileName {
            try? fileManager.removeItem(at: directory.appendingPathComponent(previewFileName))
        }
        try? fileManager.removeItem(
            at: directory.appendingPathComponent("\(capture.id.uuidString).pointcloud.json")
        )
    }

    private static func readPointCount(from url: URL) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 1024),
              let header = String(data: data, encoding: .utf8) else {
            return 0
        }
        for line in header.components(separatedBy: .newlines) where line.hasPrefix("POINTS ") {
            return Int(line.dropFirst("POINTS ".count)) ?? 0
        }
        return 0
    }

    private static func hasRGBField(in url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 1024),
              let header = String(data: data, encoding: .utf8) else {
            return false
        }
        return header.components(separatedBy: .newlines)
            .contains { $0.hasPrefix("FIELDS ") && $0.contains("rgb") }
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    private func displayTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
