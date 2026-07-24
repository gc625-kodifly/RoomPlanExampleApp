/*
See LICENSE folder for this sample's licensing information.

Abstract:
Manages saving and loading of scanned room data for later export.
*/

import Foundation
import UIKit
import RoomPlan
import ModelIO

/// Manages persistent storage of captured room scans
@MainActor
final class RoomStorageManager {

    static let shared = RoomStorageManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageDirectoryOverride: URL?

    /// Directory for saved rooms - uses iCloud if enabled, otherwise local storage
    private var savedRoomsDirectory: URL {
        if let storageDirectoryOverride {
            try? fileManager.createDirectory(
                at: storageDirectoryOverride,
                withIntermediateDirectories: true
            )
            return storageDirectoryOverride
        }
        let baseDir: URL

        // Use iCloud if enabled and available
        if AppSettings.shared.iCloudSyncEnabled {
            #if DEBUG
            print("📱 iCloud sync enabled in settings")
            print("🔑 ubiquityIdentityToken: \(fileManager.ubiquityIdentityToken != nil ? "present" : "nil")")
            #endif

            // Use iCloud container - explicitly request the app's container
            if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: "iCloud.trahe.eu.RoomPlanSimple") {
                baseDir = iCloudURL.appendingPathComponent("Documents")
                #if DEBUG
                print("✅ Using iCloud directory: \(baseDir.path)")
                print("📦 iCloud container ID: iCloud.trahe.eu.RoomPlanSimple")
                print("🔗 Full iCloud URL: \(iCloudURL.path)")
                #endif
            } else {
                #if DEBUG
                print("⚠️  iCloud not available - falling back to local storage")
                #endif
                baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            }
        } else {
            // Use Application Support (persists across app updates, not backed up by default)
            baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            #if DEBUG
            print("💾 Using local directory: \(baseDir.path)")
            #endif
        }

        // Don't use subdirectories in iCloud - save directly to base directory
        // Subdirectories can cause sync issues with iCloud
        let roomsDir: URL
        if AppSettings.shared.iCloudSyncEnabled && AppSettings.shared.isICloudAvailable {
            // For iCloud, use base directory directly
            roomsDir = baseDir
            #if DEBUG
            print("📂 Rooms directory (iCloud): \(roomsDir.path)")
            print("💡 Files saved directly in iCloud container for reliable sync")
            #endif
        } else {
            // For local storage, use subdirectory
            roomsDir = baseDir.appendingPathComponent("SavedRooms", isDirectory: true)
            if !fileManager.fileExists(atPath: roomsDir.path) {
                do {
                    try fileManager.createDirectory(at: roomsDir, withIntermediateDirectories: true)
                    #if DEBUG
                    print("📁 Created SavedRooms directory at: \(roomsDir.path)")
                    #endif
                } catch {
                    #if DEBUG
                    print("❌ Failed to create directory: \(error)")
                    #endif
                }
            }
            #if DEBUG
            print("📂 Rooms directory (local): \(roomsDir.path)")
            #endif
        }

        #if DEBUG
        print("📊 iCloud enabled: \(AppSettings.shared.iCloudSyncEnabled)")
        print("☁️  iCloud available: \(AppSettings.shared.isICloudAvailable)")
        #endif

        return roomsDir
    }

    init(storageDirectory: URL? = nil) {
        storageDirectoryOverride = storageDirectory
    }

    // MARK: - Public API

    /// Save a captured room with metadata and floor plan image
    func saveRoom(_ room: CapturedRoom, name: String? = nil, photoManager: PhotoCaptureManager? = nil) throws -> SavedRoom {
        let id = UUID()
        let timestamp = Date()
        let roomName = {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? Self.suggestedName(for: room, date: timestamp) : trimmed
        }()
        let packageURL = savedRoomsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let stagingURL = savedRoomsDirectory.appendingPathComponent(".\(id.uuidString).staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        var committed = false
        defer {
            if !committed {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let usdzURL = stagingURL.appendingPathComponent("\(id.uuidString).usdz")
        try room.export(to: usdzURL, exportOptions: .parametric)

        let floorPlanFileName = "\(id.uuidString)_floorplan.png"
        let floorPlanURL = stagingURL.appendingPathComponent(floorPlanFileName)
        var floorPlanData = FloorPlanData.from(room)
        floorPlanData.roomName = roomName
        try saveFloorPlanImage(data: floorPlanData, to: floorPlanURL)

        let floorPlanDataFileName = "\(id.uuidString)_floorplan.json"
        let floorPlanDataURL = stagingURL.appendingPathComponent(floorPlanDataFileName)
        let encodedFloorPlan = try encoder.encode(floorPlanData)
        try encodedFloorPlan.write(to: floorPlanDataURL, options: .atomic)
        _ = try decoder.decode(FloorPlanData.self, from: Data(contentsOf: floorPlanDataURL))

        // Detect room type
        let roomTypeResult = RoomTypeDetector.detectRoomType(from: room)

        // Save photos if photo manager provided
        if let photoManager = photoManager, photoManager.photoCount > 0 {
            _ = try photoManager.copyPhotos(to: stagingURL)
        }

        // Create metadata
        let metadata = SavedRoom(
            id: id,
            name: roomName,
            date: timestamp,
            wallCount: room.walls.count,
            doorCount: room.doors.count,
            windowCount: room.windows.count,
            objectCount: room.objects.count,
            floorArea: floorPlanData.roomArea,
            roomWidth: floorPlanData.roomDimensions.width,
            roomHeight: floorPlanData.roomDimensions.height,
            roomDepth: floorPlanData.roomDimensions.depth,
            usdzFileName: "\(id.uuidString).usdz",
            floorPlanFileName: floorPlanFileName,
            roomType: roomTypeResult.roomType,
            roomTypeConfidence: roomTypeResult.confidence
        )

        // Save metadata
        let metadataURL = stagingURL.appendingPathComponent("\(id.uuidString).json")
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
        _ = try decoder.decode(SavedRoom.self, from: Data(contentsOf: metadataURL))

        try fileManager.moveItem(at: stagingURL, to: packageURL)
        committed = true

        // Trigger iCloud sync if using iCloud
        if AppSettings.shared.iCloudSyncEnabled {
            let committedURLs = [usdzURL, floorPlanURL, floorPlanDataURL, metadataURL]
                .map { packageURL.appendingPathComponent($0.lastPathComponent) }
            triggerICloudSync(for: committedURLs)
        }

        return metadata
    }

    private func saveFloorPlanImage(data: FloorPlanData, to url: URL) throws {
        let image = FloorPlanDocumentRenderer.image(
            data: data,
            size: CGSize(width: 1600, height: 2000)
        )

        guard let pngData = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: url, options: .atomic)
    }

    /// Get all saved rooms
    func getSavedRooms() -> [SavedRoom] {
        let directory = savedRoomsDirectory

        #if DEBUG
        print("📁 Loading saved rooms from: \(directory.path)")
        #endif

        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            #if DEBUG
            print("⚠️  Could not read directory contents")
            #endif
            return []
        }

        #if DEBUG
        print("📄 Found \(files.count) files in directory")
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        print("📋 Found \(jsonFiles.count) JSON files")
        #endif

        let metadataFiles = files.filter { $0.pathExtension == "json" } + files.compactMap { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            let metadata = url.appendingPathComponent("\(url.lastPathComponent).json")
            return fileManager.fileExists(atPath: metadata.path) ? metadata : nil
        }
        return metadataFiles
            .compactMap { url -> SavedRoom? in
                guard let data = try? Data(contentsOf: url),
                      let room = try? decoder.decode(SavedRoom.self, from: data) else {
                    #if DEBUG
                    print("⚠️  Failed to decode room from: \(url.lastPathComponent)")
                    #endif
                    return nil
                }
                return room
            }
            .sorted { $0.date > $1.date }
    }

    /// Note: CapturedRoom cannot be reloaded from USDZ files.
    /// This is a limitation of the RoomPlan API - CapturedRoom is only available during live scanning.
    /// To view saved rooms, use the USDZ file directly with SceneKit.

    /// Get the URL for a specific room file
    func getRoomFileURL(for room: SavedRoom, filename: String) -> URL {
        artifactURL(for: room, filename: filename)
    }

    /// Get USDZ file URL for a saved room
    func getUsdzURL(for room: SavedRoom) -> URL {
        artifactURL(for: room, filename: room.usdzFileName)
    }

    /// Get floor plan image URL for a saved room
    func getFloorPlanURL(for room: SavedRoom) -> URL? {
        guard let fileName = room.floorPlanFileName else { return nil }
        let url = artifactURL(for: room, filename: fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Get floor plan image for a saved room
    func getFloorPlanImage(for room: SavedRoom) -> UIImage? {
        guard let url = getFloorPlanURL(for: room),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Load photos for a saved room
    func getPhotos(for room: SavedRoom) -> [UIImage] {
        let roomDirectory = savedRoomsDirectory.appendingPathComponent(room.id.uuidString, isDirectory: true)
        let photosDirectory = roomDirectory.appendingPathComponent("photos", isDirectory: true)

        // Check photos subdirectory first (new structure)
        let directoryToScan: URL
        if fileManager.fileExists(atPath: photosDirectory.path) {
            directoryToScan = photosDirectory
        } else if fileManager.fileExists(atPath: roomDirectory.path) {
            directoryToScan = roomDirectory
        } else {
            return []
        }

        do {
            let contents = try fileManager.contentsOfDirectory(at: directoryToScan,
                                                               includingPropertiesForKeys: nil)

            let imageURLs = contents.filter {
                $0.pathExtension.lowercased() == "jpg" ||
                $0.pathExtension.lowercased() == "jpeg" ||
                $0.pathExtension.lowercased() == "png"
            }.sorted { $0.path < $1.path }  // Sort alphabetically

            return imageURLs.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }
        } catch {
            #if DEBUG
            print("⚠️  Failed to load photos: \(error)")
            #endif
            return []
        }
    }

    /// Export saved room to OBJ format
    func exportToOBJ(for room: SavedRoom) throws -> URL {
        let usdzURL = getUsdzURL(for: room)
        guard fileManager.fileExists(atPath: usdzURL.path) else {
            throw NSError(domain: "RoomStorageManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "USDZ file not found"])
        }

        let objFileName = "\(room.id.uuidString).obj"
        let objURL = fileManager.temporaryDirectory.appendingPathComponent(objFileName)

        // Clean up any existing file
        try? fileManager.removeItem(at: objURL)

        // Load USDZ with ModelIO
        let asset = MDLAsset(url: usdzURL)

        // Export to OBJ
        try asset.export(to: objURL)

        return objURL
    }

    /// Export saved room to STL format
    func exportToSTL(for room: SavedRoom) throws -> URL {
        let usdzURL = getUsdzURL(for: room)
        guard fileManager.fileExists(atPath: usdzURL.path) else {
            throw NSError(domain: "RoomStorageManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "USDZ file not found"])
        }

        let stlFileName = "\(room.id.uuidString).stl"
        let stlURL = fileManager.temporaryDirectory.appendingPathComponent(stlFileName)

        // Clean up any existing file
        try? fileManager.removeItem(at: stlURL)

        // Load USDZ with ModelIO
        let asset = MDLAsset(url: usdzURL)

        // Export to STL
        try asset.export(to: stlURL)

        return stlURL
    }

    /// Load floor plan data for a saved room
    func loadFloorPlanData(for room: SavedRoom) -> FloorPlanData? {
        let dataURL = artifactURL(for: room, filename: "\(room.id.uuidString)_floorplan.json")
        guard let data = try? Data(contentsOf: dataURL),
              let floorPlanData = try? decoder.decode(FloorPlanData.self, from: data) else {
            return nil
        }
        return floorPlanData
    }

    /// Export saved room floor plan to SVG format
    func exportToSVG(for room: SavedRoom) throws -> URL {
        guard let floorPlanData = loadFloorPlanData(for: room) else {
            throw NSError(domain: "RoomStorageManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Floor plan data not found"])
        }

        let svgFileName = "\(room.id.uuidString).svg"
        let svgURL = fileManager.temporaryDirectory.appendingPathComponent(svgFileName)

        // Clean up any existing file
        try? fileManager.removeItem(at: svgURL)

        let svgContent = FloorPlanExporter.exportToSVG(data: floorPlanData, includeDimensions: true)
        try svgContent.write(to: svgURL, atomically: true, encoding: .utf8)

        return svgURL
    }

    /// Export saved room floor plan to DXF format
    func exportToDXF(for room: SavedRoom) throws -> URL {
        guard let floorPlanData = loadFloorPlanData(for: room) else {
            throw NSError(domain: "RoomStorageManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Floor plan data not found"])
        }

        let dxfFileName = "\(room.id.uuidString).dxf"
        let dxfURL = fileManager.temporaryDirectory.appendingPathComponent(dxfFileName)

        // Clean up any existing file
        try? fileManager.removeItem(at: dxfURL)

        let dxfContent = FloorPlanExporter.exportToDXF(data: floorPlanData, includeDimensions: true)
        try dxfContent.write(to: dxfURL, atomically: true, encoding: .utf8)

        return dxfURL
    }

    /// Export saved room floor plan to IFC format (BIM)
    func exportToIFC(for room: SavedRoom) throws -> URL {
        let floorPlanData = loadFloorPlanData(for: room) ?? generateFloorPlanFromMetadata(room)

        let ifcFileName = "\(room.id.uuidString).ifc"
        let ifcURL = fileManager.temporaryDirectory.appendingPathComponent(ifcFileName)

        // Clean up any existing file
        try? fileManager.removeItem(at: ifcURL)

        // Generate IFC via Rust bimifc-writer
        try IfcExportBridge.writeIFC(from: floorPlanData, to: ifcURL, roomName: room.name)

        return ifcURL
    }

    /// Generate basic FloorPlanData from SavedRoom metadata (for rooms saved before floor plan JSON was added)
    private func generateFloorPlanFromMetadata(_ room: SavedRoom) -> FloorPlanData {
        let w = CGFloat(room.roomWidth > 0 ? room.roomWidth : 4.0)
        let d = CGFloat(room.roomDepth > 0 ? room.roomDepth : 3.0)
        let wallThickness: CGFloat = 0.15

        // Generate 4 walls forming a rectangle
        let walls: [FloorPlanElement] = [
            // Bottom wall (along X axis)
            FloorPlanElement(rect: CGRect(x: 0, y: 0, width: w, height: wallThickness), rotation: 0, type: .wall, label: nil),
            // Top wall
            FloorPlanElement(rect: CGRect(x: 0, y: d - wallThickness, width: w, height: wallThickness), rotation: 0, type: .wall, label: nil),
            // Left wall (along Z axis)
            FloorPlanElement(rect: CGRect(x: 0, y: 0, width: wallThickness, height: d), rotation: 0, type: .wall, label: nil),
            // Right wall
            FloorPlanElement(rect: CGRect(x: w - wallThickness, y: 0, width: wallThickness, height: d), rotation: 0, type: .wall, label: nil),
        ]

        let boundingBox = CGRect(x: 0, y: 0, width: w, height: d)
        let dimensions = (width: room.roomWidth, height: room.roomHeight > 0 ? room.roomHeight : 2.8, depth: room.roomDepth)

        return FloorPlanData(elements: walls, boundingBox: boundingBox, roomDimensions: dimensions)
    }

    /// Delete a saved room
    func deleteRoom(_ room: SavedRoom) throws {
        let packageURL = savedRoomsDirectory.appendingPathComponent(room.id.uuidString, isDirectory: true)
        let packagedMetadata = packageURL.appendingPathComponent("\(room.id.uuidString).json")
        if fileManager.fileExists(atPath: packagedMetadata.path) {
            try fileManager.removeItem(at: packageURL)
            return
        }
        let filenames = [
            room.usdzFileName,
            "\(room.id.uuidString).json",
            room.floorPlanFileName,
            "\(room.id.uuidString)_floorplan.json",
            "\(room.id.uuidString)_wifi.json"
        ].compactMap { $0 }
        for filename in filenames {
            let url = savedRoomsDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        let legacyPhotoDirectory = savedRoomsDirectory.appendingPathComponent(room.id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: legacyPhotoDirectory.path) {
            try fileManager.removeItem(at: legacyPhotoDirectory)
        }
    }

    /// Delete all saved rooms
    func deleteAllRooms() throws {
        let rooms = getSavedRooms()
        for room in rooms {
            try deleteRoom(room)
        }
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Print detailed information about storage locations and contents
    func debugStorageInfo() {
        print("\n" + String(repeating: "=", count: 60))
        print("📊 STORAGE DEBUG INFO")
        print(String(repeating: "=", count: 60))

        // iCloud availability
        print("\n☁️  iCloud Status:")
        print("   - iCloud available: \(AppSettings.shared.isICloudAvailable)")
        print("   - iCloud enabled in app: \(AppSettings.shared.iCloudSyncEnabled)")
        if let token = fileManager.ubiquityIdentityToken {
            print("   - iCloud identity token: \(token)")
        } else {
            print("   - ⚠️  No iCloud identity token (not signed in)")
        }

        // Current directory
        print("\n📂 Current SavedRooms Directory:")
        print("   \(savedRoomsDirectory.path)")

        // Directory contents
        if let files = try? fileManager.contentsOfDirectory(at: savedRoomsDirectory, includingPropertiesForKeys: nil) {
            print("\n📄 Files in directory: \(files.count)")
            for file in files {
                let fileSize = (try? fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
                let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                print("   - \(file.lastPathComponent) (\(sizeStr))")
            }
        } else {
            print("\n⚠️  Could not read directory")
        }

        // Alternative directories
        print("\n📁 Other Storage Locations:")
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appSupportRooms = appSupport.appendingPathComponent("SavedRooms")
        print("   Local (App Support): \(appSupportRooms.path)")
        if fileManager.fileExists(atPath: appSupportRooms.path) {
            if let localFiles = try? fileManager.contentsOfDirectory(at: appSupportRooms, includingPropertiesForKeys: nil) {
                print("   → Contains \(localFiles.count) files")
            }
        } else {
            print("   → Does not exist")
        }

        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil) {
            let iCloudRooms = iCloudURL.appendingPathComponent("Documents/SavedRooms")
            print("   iCloud: \(iCloudRooms.path)")
            if fileManager.fileExists(atPath: iCloudRooms.path) {
                if let iCloudFiles = try? fileManager.contentsOfDirectory(at: iCloudRooms, includingPropertiesForKeys: nil) {
                    print("   → Contains \(iCloudFiles.count) files")
                }
            } else {
                print("   → Does not exist yet")
            }
        } else {
            print("   iCloud: Not available")
        }

        print(String(repeating: "=", count: 60) + "\n")
    }
    #endif

    /// Export complete room data as folder with all files
    func exportRoomAsZIP(for room: SavedRoom) throws -> URL {
        let exportFolderName = "\(room.name.replacingOccurrences(of: " ", with: "_"))_Complete"
        let exportDir = fileManager.temporaryDirectory.appendingPathComponent(exportFolderName, isDirectory: true)

        // Remove existing export folder if present
        try? fileManager.removeItem(at: exportDir)

        // Create export directory
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Copy USDZ file
        let usdzURL = getUsdzURL(for: room)
        if fileManager.fileExists(atPath: usdzURL.path) {
            let destUSDZ = exportDir.appendingPathComponent("\(room.name).usdz")
            try fileManager.copyItem(at: usdzURL, to: destUSDZ)
        }

        // Export floor plan as SVG (if floor plan data exists)
        do {
            let svgURL = try exportToSVG(for: room)
            let destSVG = exportDir.appendingPathComponent("\(room.name)_floorplan.svg")
            try fileManager.copyItem(at: svgURL, to: destSVG)
        } catch {
            #if DEBUG
            print("⚠️  Could not export SVG: \(error)")
            #endif
        }

        // Also copy original PNG floor plan image
        if let floorPlanURL = getFloorPlanURL(for: room),
           fileManager.fileExists(atPath: floorPlanURL.path) {
            let destFloorPlan = exportDir.appendingPathComponent("\(room.name)_floorplan.png")
            try fileManager.copyItem(at: floorPlanURL, to: destFloorPlan)
        }

        // Copy floor plan data JSON
        let floorPlanDataURL = artifactURL(for: room, filename: "\(room.id.uuidString)_floorplan.json")
        if fileManager.fileExists(atPath: floorPlanDataURL.path) {
            let destFloorPlanData = exportDir.appendingPathComponent("\(room.name)_floorplan.json")
            try fileManager.copyItem(at: floorPlanDataURL, to: destFloorPlanData)
        }

        // Copy metadata JSON
        let metadataURL = artifactURL(for: room, filename: "\(room.id.uuidString).json")
        if fileManager.fileExists(atPath: metadataURL.path) {
            let destMetadata = exportDir.appendingPathComponent("\(room.name)_metadata.json")
            try fileManager.copyItem(at: metadataURL, to: destMetadata)
        }

        // Copy photos
        let photos = getPhotos(for: room)
        if !photos.isEmpty {
            let photosDir = exportDir.appendingPathComponent("photos", isDirectory: true)
            try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)

            let roomDirectory = savedRoomsDirectory.appendingPathComponent(room.id.uuidString, isDirectory: true)
            let photosDirectory = roomDirectory.appendingPathComponent("photos", isDirectory: true)

            // Check photos subdirectory first (new structure), fallback to room directory
            let sourceDirectory: URL
            if fileManager.fileExists(atPath: photosDirectory.path) {
                sourceDirectory = photosDirectory
            } else {
                sourceDirectory = roomDirectory
            }

            if let photoFiles = try? fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil) {
                for (index, photoFile) in photoFiles.filter({ $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "png" }).enumerated() {
                    let destPhoto = photosDir.appendingPathComponent("photo_\(String(format: "%03d", index + 1)).\(photoFile.pathExtension)")
                    try? fileManager.copyItem(at: photoFile, to: destPhoto)
                }
            }
        }

        // iOS doesn't have Process for zip command, so we'll share the folder directly
        // The folder will be exported with all contents
        #if DEBUG
        print("📦 Created export folder at: \(exportDir.path)")
        print("   Contents: USDZ, floor plan, metadata, photos")
        #endif

        // Return the temp directory - UIActivityViewController can share folders on iOS 13+
        return exportDir
    }

    // MARK: - Private

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func suggestedName(for room: CapturedRoom, date: Date = Date()) -> String {
        let detected = RoomTypeDetector.detectRoomType(from: room).roomType
        if detected != .unknown {
            return detected.rawValue
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Room \(formatter.string(from: date))"
    }

    private func artifactURL(for room: SavedRoom, filename: String) -> URL {
        let packaged = savedRoomsDirectory
            .appendingPathComponent(room.id.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
        if fileManager.fileExists(atPath: packaged.path) {
            return packaged
        }
        return savedRoomsDirectory.appendingPathComponent(filename)
    }

    /// Update room metadata (name, notes)
    func updateRoom(_ room: SavedRoom) throws {
        var updatedRoom = room
        updatedRoom.lastModified = Date()

        // Save updated metadata
        let metadataURL = artifactURL(for: room, filename: "\(room.id.uuidString).json")
        let temporaryURL = metadataURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(room.id.uuidString).metadata-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        let data = try encoder.encode(updatedRoom)
        try data.write(to: temporaryURL, options: .atomic)
        _ = try decoder.decode(SavedRoom.self, from: Data(contentsOf: temporaryURL))
        _ = try fileManager.replaceItemAt(
            metadataURL,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
        )

        #if DEBUG
        print("📝 Updated room: \(updatedRoom.name)")
        print("🕒 Last modified: \(updatedRoom.lastModified)")
        #endif

        // Trigger iCloud sync if enabled
        if AppSettings.shared.iCloudSyncEnabled {
            triggerICloudSync(for: [metadataURL])
        }
    }

    /// Migrate existing rooms to iCloud Drive
    func migrateToICloud() throws -> Int {
        guard AppSettings.shared.iCloudSyncEnabled else {
            return 0
        }

        var migratedCount = 0
        let iCloudDir = savedRoomsDirectory

        #if DEBUG
        print("🔄 Starting migration to iCloud Drive")
        #endif

        // Source 1: Local Application Support directory
        let localBaseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let localRoomsDir = localBaseDir.appendingPathComponent("SavedRooms", isDirectory: true)

        // Source 2: Old iCloud container with SavedRooms subdirectory
        let oldContainerID = "iCloud.trahe.eu.RoomPlanSimple"
        if let oldICloudBaseDir = fileManager.url(forUbiquityContainerIdentifier: oldContainerID)?.appendingPathComponent("Documents") {
            let oldICloudSubdir = oldICloudBaseDir.appendingPathComponent("SavedRooms")

            // Migrate from old iCloud SavedRooms subdirectory to Documents root
            if fileManager.fileExists(atPath: oldICloudSubdir.path) {
                #if DEBUG
                print("📂 Migrating from iCloud subdirectory: \(oldICloudSubdir.path)")
                print("📁 Destination: \(iCloudDir.path)")
                #endif
                migratedCount += try migrateFiles(from: oldICloudSubdir, to: iCloudDir)
            }
        }

        // Migrate from local storage
        if fileManager.fileExists(atPath: localRoomsDir.path) {
            #if DEBUG
            print("📂 Migrating from local: \(localRoomsDir.path)")
            #endif
            migratedCount += try migrateFiles(from: localRoomsDir, to: iCloudDir)
        }

        #if DEBUG
        print("🎉 Migration complete: \(migratedCount) files migrated to iCloud Drive")
        print("📁 New location: \(iCloudDir.path)")
        #endif

        // Trigger iCloud sync for all migrated files
        if migratedCount > 0 {
            let migratedFiles = try fileManager.contentsOfDirectory(at: iCloudDir, includingPropertiesForKeys: nil)
            triggerICloudSync(for: migratedFiles)
        }

        return migratedCount
    }

    /// Helper to migrate files from one directory to another
    private func migrateFiles(from sourceDir: URL, to destDir: URL) throws -> Int {
        var count = 0
        let contents = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)

        for sourceURL in contents {
            let filename = sourceURL.lastPathComponent
            let destinationURL = destDir.appendingPathComponent(filename)

            // Skip if already exists in destination
            if fileManager.fileExists(atPath: destinationURL.path) {
                #if DEBUG
                print("⏭️  Skipping \(filename) - already exists")
                #endif
                continue
            }

            // Copy file to destination
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                count += 1
                #if DEBUG
                print("✅ Migrated: \(filename)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️  Failed to migrate \(filename): \(error)")
                #endif
            }
        }

        return count
    }

    /// Export multiple rooms as a single ZIP/folder
    func exportMultipleRooms(_ rooms: [SavedRoom]) throws -> URL {
        let exportFolderName = "RoomPlanExport_\(Int(Date().timeIntervalSince1970))"
        let exportDir = fileManager.temporaryDirectory.appendingPathComponent(exportFolderName, isDirectory: true)

        // Remove existing export folder if present
        try? fileManager.removeItem(at: exportDir)

        // Create export directory
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        #if DEBUG
        print("📦 Exporting \(rooms.count) rooms to: \(exportDir.path)")
        #endif

        // Export each room to its own subfolder
        for room in rooms {
            let roomFolder = exportDir.appendingPathComponent(room.name.replacingOccurrences(of: " ", with: "_"), isDirectory: true)
            try fileManager.createDirectory(at: roomFolder, withIntermediateDirectories: true)

            // Copy USDZ
            let usdzURL = getUsdzURL(for: room)
            if fileManager.fileExists(atPath: usdzURL.path) {
                try? fileManager.copyItem(at: usdzURL, to: roomFolder.appendingPathComponent("\(room.name).usdz"))
            }

            // Export SVG floor plan
            do {
                let svgURL = try exportToSVG(for: room)
                try? fileManager.copyItem(at: svgURL, to: roomFolder.appendingPathComponent("\(room.name)_floorplan.svg"))
            } catch {
                #if DEBUG
                print("⚠️  Could not export SVG for \(room.name): \(error)")
                #endif
            }

            // Copy PNG floor plan
            if let floorPlanURL = getFloorPlanURL(for: room), fileManager.fileExists(atPath: floorPlanURL.path) {
                try? fileManager.copyItem(at: floorPlanURL, to: roomFolder.appendingPathComponent("\(room.name)_floorplan.png"))
            }

            // Copy metadata
            let metadataURL = artifactURL(for: room, filename: "\(room.id.uuidString).json")
            if fileManager.fileExists(atPath: metadataURL.path) {
                try? fileManager.copyItem(at: metadataURL, to: roomFolder.appendingPathComponent("\(room.name)_metadata.json"))
            }

            // Copy photos
            let photos = getPhotos(for: room)
            if !photos.isEmpty {
                let photosDir = roomFolder.appendingPathComponent("photos", isDirectory: true)
                try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)

                let roomDirectory = savedRoomsDirectory.appendingPathComponent(room.id.uuidString, isDirectory: true)
                let photosDirectory = roomDirectory.appendingPathComponent("photos", isDirectory: true)

                let sourceDirectory = fileManager.fileExists(atPath: photosDirectory.path) ? photosDirectory : roomDirectory

                if let photoFiles = try? fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil) {
                    for (index, photoFile) in photoFiles.filter({ $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "png" }).enumerated() {
                        let destPhoto = photosDir.appendingPathComponent("photo_\(String(format: "%03d", index + 1)).\(photoFile.pathExtension)")
                        try? fileManager.copyItem(at: photoFile, to: destPhoto)
                    }
                }
            }
        }

        #if DEBUG
        print("✅ Exported \(rooms.count) rooms successfully")
        #endif

        return exportDir
    }

    /// Trigger iCloud to upload files by setting metadata attributes
    private func triggerICloudSync(for urls: [URL]) {
        #if DEBUG
        print("☁️  Triggering iCloud sync for \(urls.count) files")
        #endif

        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
                #if DEBUG
                print("⚠️  File doesn't exist for iCloud sync: \(url.lastPathComponent)")
                #endif
                continue
            }

            do {
                // Set file attributes to trigger iCloud upload
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = false

                var mutableURL = url
                try mutableURL.setResourceValues(resourceValues)

                #if DEBUG
                print("✅ Set iCloud attributes for: \(url.lastPathComponent)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️  Failed to set iCloud attributes for \(url.lastPathComponent): \(error)")
                #endif
            }
        }
    }
}

// MARK: - SavedRoom Model

struct SavedRoom: Codable, Identifiable {
    let id: UUID
    var name: String
    let date: Date
    var lastModified: Date
    var notes: String?
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let objectCount: Int
    let floorArea: Float
    let roomWidth: Float
    let roomHeight: Float
    let roomDepth: Float
    let usdzFileName: String
    let floorPlanFileName: String?
    let roomType: RoomTypeDetector.RoomType
    let roomTypeConfidence: Float

    // Support loading older saves without new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decode(Date.self, forKey: .date)
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? date
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        wallCount = try container.decode(Int.self, forKey: .wallCount)
        doorCount = try container.decode(Int.self, forKey: .doorCount)
        windowCount = try container.decode(Int.self, forKey: .windowCount)
        objectCount = try container.decode(Int.self, forKey: .objectCount)
        floorArea = try container.decode(Float.self, forKey: .floorArea)
        roomWidth = try container.decodeIfPresent(Float.self, forKey: .roomWidth) ?? 0
        roomHeight = try container.decodeIfPresent(Float.self, forKey: .roomHeight) ?? 0
        roomDepth = try container.decodeIfPresent(Float.self, forKey: .roomDepth) ?? 0
        usdzFileName = try container.decode(String.self, forKey: .usdzFileName)
        floorPlanFileName = try container.decodeIfPresent(String.self, forKey: .floorPlanFileName)
        roomType = try container.decodeIfPresent(RoomTypeDetector.RoomType.self, forKey: .roomType) ?? .unknown
        roomTypeConfidence = try container.decodeIfPresent(Float.self, forKey: .roomTypeConfidence) ?? 0.0
    }

    init(id: UUID, name: String, date: Date, wallCount: Int, doorCount: Int, windowCount: Int,
         objectCount: Int, floorArea: Float, roomWidth: Float, roomHeight: Float, roomDepth: Float,
         usdzFileName: String, floorPlanFileName: String?,
         roomType: RoomTypeDetector.RoomType, roomTypeConfidence: Float, notes: String? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.lastModified = date
        self.notes = notes
        self.wallCount = wallCount
        self.doorCount = doorCount
        self.windowCount = windowCount
        self.objectCount = objectCount
        self.floorArea = floorArea
        self.roomWidth = roomWidth
        self.roomHeight = roomHeight
        self.roomDepth = roomDepth
        self.usdzFileName = usdzFileName
        self.floorPlanFileName = floorPlanFileName
        self.roomType = roomType
        self.roomTypeConfidence = roomTypeConfidence
    }

    var summary: String {
        var parts: [String] = []
        if wallCount > 0 { parts.append(L10n.SavedRooms.walls.localized(wallCount)) }
        if doorCount > 0 { parts.append(L10n.SavedRooms.doors.localized(doorCount)) }
        if windowCount > 0 { parts.append(L10n.SavedRooms.windows.localized(windowCount)) }
        if objectCount > 0 { parts.append(L10n.SavedRooms.objects.localized(objectCount)) }
        if floorArea > 0 { parts.append(L10n.SavedRooms.area.localized(floorArea)) }
        return parts.isEmpty ? L10n.Stats.empty.localized : parts.joined(separator: ", ")
    }

    var dimensionsSummary: String {
        if roomWidth > 0 && roomDepth > 0 {
            return L10n.SavedRooms.dimensions.localized(roomWidth, roomDepth)
        }
        return ""
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var hasFloorPlan: Bool {
        floorPlanFileName != nil
    }
}
