/*
See LICENSE folder for this sample's licensing information.

Abstract:
Bridge between FloorPlanData and bimifc-writer Rust library for IFC export.
Uses UniFFI-generated Swift bindings from bimifc-ffi.
*/

import Foundation

/// Converts FloorPlanData to IFC 2x3 format using the bimifc-writer Rust library.
final class IfcExportBridge {

    /// Convert a FloorPlanElement.ElementType to the FFI enum.
    private static func convertElementKind(_ type: FloorPlanElement.ElementType) -> FfiElementKind {
        switch type {
        case .wall:
            return .wall
        case .door:
            return .door
        case .window:
            return .window
        case .opening:
            return .opening
        case .object(let category):
            return .furniture(category: category)
        }
    }

    /// Convert FloorPlanData elements to FFI room elements.
    private static func convertElements(_ data: FloorPlanData) -> [FfiRoomElement] {
        data.elements.map { element in
            FfiRoomElement(
                kind: convertElementKind(element.type),
                rect: FfiRect(
                    x: Double(element.rect.origin.x),
                    y: Double(element.rect.origin.y),
                    width: Double(element.rect.size.width),
                    height: Double(element.rect.size.height)
                ),
                rotation: Double(element.rotation),
                label: element.label,
                height: 0 // Use defaults from the Rust library
            )
        }
    }

    /// Generate IFC content string from floor plan data.
    ///
    /// - Parameters:
    ///   - data: The floor plan data from a RoomPlan scan.
    ///   - roomName: Optional name for the project (defaults to "RoomPlan Export").
    /// - Returns: IFC 2x3 STEP file content as a string.
    static func generateIFC(from data: FloorPlanData, roomName: String? = nil) -> String {
        let writer = IfcWriter()

        let elements = convertElements(data)

        let boundingBox = FfiRect(
            x: Double(data.boundingBox.origin.x),
            y: Double(data.boundingBox.origin.y),
            width: Double(data.boundingBox.size.width),
            height: Double(data.boundingBox.size.height)
        )

        let dimensions = FfiRoomDimensions(
            width: Double(data.roomDimensions.width),
            height: Double(data.roomDimensions.height),
            depth: Double(data.roomDimensions.depth)
        )

        let project = FfiProjectInfo(
            projectName: roomName ?? "RoomPlan Export",
            siteName: "Scanned Site",
            buildingName: "Scanned Building",
            storeyName: "Ground Floor",
            author: "RoomPlan User",
            organization: "RoomPlan App"
        )

        return writer.writeIfc(
            elements: elements,
            boundingBox: boundingBox,
            dimensions: dimensions,
            project: project
        )
    }

    /// Generate IFC and write directly to a file URL.
    ///
    /// - Parameters:
    ///   - data: The floor plan data from a RoomPlan scan.
    ///   - url: Destination file URL.
    ///   - roomName: Optional name for the project.
    static func writeIFC(from data: FloorPlanData, to url: URL, roomName: String? = nil) throws {
        let content = generateIFC(from: data, roomName: roomName)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
