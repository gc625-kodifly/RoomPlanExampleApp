/*
See LICENSE folder for this sample's licensing information.

Abstract:
Exports floor plan data to SVG and DXF formats.
*/

import Foundation
import UIKit

/// Exports floor plan geometry to CAD-compatible formats
final class FloorPlanExporter {

    // MARK: - Export Formats

    enum ExportFormat: String, CaseIterable {
        case svg
        case dxf

        /// Localized display name for the format
        var localizedName: String {
            switch self {
            case .svg: return L10n.Export.svg.localized
            case .dxf: return L10n.Export.dxf.localized
            }
        }

        var fileExtension: String {
            switch self {
            case .svg: return "svg"
            case .dxf: return "dxf"
            }
        }
    }

    // MARK: - SVG Export

    /// Export floor plan data to SVG format
    static func exportToSVG(data: FloorPlanData, wifiSamples: [WiFiSample] = [], includeDimensions: Bool = true) -> String {
        let padding: CGFloat = 90
        let headerHeight: CGFloat = 80
        let footerHeight: CGFloat = 60
        let scale: CGFloat = 100  // 1 meter = 100 pixels

        let width = data.boundingBox.width * scale + padding * 2
        let height = data.boundingBox.height * scale + padding * 2 + headerHeight + footerHeight

        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             width="\(Int(width))" height="\(Int(height))"
             viewBox="0 0 \(Int(width)) \(Int(height))">
        <title>Floor Plan</title>
        <style>
            .wall { fill: #242936; stroke: #242936; stroke-width: 2; }
            .door { fill: white; stroke: #666666; stroke-width: 1.5; }
            .window { fill: white; stroke: #1677FF; stroke-width: 2; }
            .opening { fill: none; stroke: #999999; stroke-width: 2; stroke-dasharray: 5,5; }
            .object { fill: #F5F5F5; stroke: #AAAAAA; stroke-width: 1; }
            .dimension { font-family: Arial, sans-serif; font-size: 12px; fill: #666666; }
            .label { font-family: Arial, sans-serif; font-size: 10px; fill: #333333; text-anchor: middle; }
            .room-name { font-family: Arial, sans-serif; font-size: 16px; font-weight: 600; fill: #252A35; text-anchor: middle; }
            .room-area { font-family: Arial, sans-serif; font-size: 12px; fill: #666666; text-anchor: middle; }
        </style>
        <defs>
          <marker id="arrow" markerWidth="7" markerHeight="7" refX="3.5" refY="3.5" orient="auto">
            <path d="M 7 0 L 0 3.5 L 7 7 z" fill="#666666"/>
          </marker>
        </defs>
        <rect width="100%" height="100%" fill="white"/>
        <text x="\(width / 2)" y="32" text-anchor="middle" font-family="Arial" font-size="22" font-weight="600" fill="#20242D">SpatialSense Floor Plan</text>
        <text x="\(width / 2)" y="54" text-anchor="middle" font-family="Arial" font-size="12" fill="#666666">\(escapeXML(data.roomName))</text>
        <g transform="translate(\(padding), \(padding + headerHeight))">

        """

        // Helper to transform coordinates
        func tx(_ x: CGFloat) -> CGFloat {
            return (x - data.boundingBox.minX) * scale
        }
        func ty(_ y: CGFloat) -> CGFloat {
            return (y - data.boundingBox.minY) * scale
        }

        func rotationTransform(_ element: FloorPlanElement) -> String {
            let x = tx(element.rect.minX)
            let y = ty(element.rect.minY)
            let width = element.rect.width * scale
            let height = element.rect.height * scale
            let rotation = element.rotation * 180 / .pi
            return "rotate(\(rotation), \(x + width / 2), \(y + height / 2))"
        }

        if data.boundary.count >= 3 {
            let points = data.boundary
                .map { "\(tx($0.x)),\(ty($0.y))" }
                .joined(separator: " ")
            svg += "<polygon points=\"\(points)\" fill=\"#F7F9FC\" stroke=\"none\"/>\n"
        }

        // Draw elements by type
        let walls = data.elements.filter { if case .wall = $0.type { return true } else { return false } }
        let doors = data.elements.filter { if case .door = $0.type { return true } else { return false } }
        let windows = data.elements.filter { if case .window = $0.type { return true } else { return false } }
        let openings = data.elements.filter { if case .opening = $0.type { return true } else { return false } }
        let objects = data.elements.filter { if case .object = $0.type { return true } else { return false } }

        // Walls
        for wall in walls {
            let x = tx(wall.rect.minX)
            let y = ty(wall.rect.minY)
            let w = wall.rect.width * scale
            let h = wall.rect.height * scale
            svg += """
                <rect class="wall" x="\(x)" y="\(y)" width="\(w)" height="\(h)"
                      transform="\(rotationTransform(wall))"/>

            """
        }

        // Doors (draw as arc)
        for door in doors {
            let x = tx(door.rect.minX)
            let y = ty(door.rect.minY)
            let w = door.rect.width * scale
            let h = door.rect.height * scale

            svg += """
                <rect class="door" x="\(x)" y="\(y)" width="\(w)" height="\(h)"
                      transform="\(rotationTransform(door))"/>

            """
        }

        // Windows
        for window in windows {
            let x = tx(window.rect.minX)
            let y = ty(window.rect.minY)
            let w = window.rect.width * scale
            let h = window.rect.height * scale

            svg += """
                <rect class="window" x="\(x)" y="\(y)" width="\(w)" height="\(h)"
                      transform="\(rotationTransform(window))"/>

            """
        }

        // Openings
        for opening in openings {
            let x = tx(opening.rect.minX)
            let y = ty(opening.rect.minY)
            let w = opening.rect.width * scale
            let h = opening.rect.height * scale

            svg += """
                <rect class="opening" x="\(x)" y="\(y)" width="\(w)" height="\(h)"
                      transform="\(rotationTransform(opening))"/>

            """
        }

        // Objects with labels
        for object in objects {
            let x = tx(object.rect.minX)
            let y = ty(object.rect.minY)
            let w = object.rect.width * scale
            let h = object.rect.height * scale

            svg += """
                <rect class="object" x="\(x)" y="\(y)" width="\(w)" height="\(h)"
                      transform="\(rotationTransform(object))"/>

            """
            if let label = object.label {
                svg += """
                    <text class="label" x="\(x + w/2)" y="\(y + h/2 + 4)">\(escapeXML(label))</text>

                """
            }
        }

        svg += """
            <text class="room-name" x="\(data.boundingBox.width * scale / 2)" y="\(data.boundingBox.height * scale / 2)">\(escapeXML(data.roomName))</text>
            <text class="room-area" x="\(data.boundingBox.width * scale / 2)" y="\(data.boundingBox.height * scale / 2 + 18)">\(String(format: "%.1f m²", data.roomArea))</text>

        """

        // Dimensions
        if includeDimensions {
            let roomWidth = String(format: "%.2fm", data.boundingBox.width)
            let roomDepth = String(format: "%.2fm", data.boundingBox.height)

            // Bottom dimension (width)
            let bottomY = data.boundingBox.height * scale + 30
            svg += """
                <line x1="0" y1="\(bottomY)" x2="\(data.boundingBox.width * scale)" y2="\(bottomY)"
                      stroke="#666" stroke-width="1" marker-start="url(#arrow)" marker-end="url(#arrow)"/>
                <text class="dimension" x="\(data.boundingBox.width * scale / 2)" y="\(bottomY + 15)" text-anchor="middle">\(roomWidth)</text>

            """

            // Right dimension (depth)
            let rightX = data.boundingBox.width * scale + 30
            svg += """
                <line x1="\(rightX)" y1="0" x2="\(rightX)" y2="\(data.boundingBox.height * scale)"
                      stroke="#666" stroke-width="1"/>
                <text class="dimension" x="\(rightX + 10)" y="\(data.boundingBox.height * scale / 2)"
                      transform="rotate(90, \(rightX + 10), \(data.boundingBox.height * scale / 2))">\(roomDepth)</text>

            """
        }

        // WiFi sample points
        if !wifiSamples.isEmpty {
            svg += """
                <!-- WiFi Samples -->

            """

            for sample in wifiSamples {
                let x = tx(CGFloat(sample.position.x))
                let y = ty(CGFloat(sample.position.z)) // Use z for 2D floor plan
                let signalStrength = sample.rssi

                // Color based on signal strength (-30 to -90 dBm)
                let normalizedSignal = (Double(signalStrength) + 90) / 60.0 // 0 (poor) to 1 (excellent)
                let color: String
                if normalizedSignal > 0.75 {
                    color = "#00FF00" // Green (excellent)
                } else if normalizedSignal > 0.5 {
                    color = "#90EE90" // Light green (good)
                } else if normalizedSignal > 0.25 {
                    color = "#FFD700" // Gold (fair)
                } else {
                    color = "#FF6347" // Tomato (poor)
                }

                svg += """
                    <circle cx="\(x)" cy="\(y)" r="3" fill="\(color)" stroke="#333" stroke-width="0.5" opacity="0.7"/>

                """
            }
        }

        svg += """
        </g>
        <line x1="35" y1="\(height - 34)" x2="\(35 + scale)" y2="\(height - 34)" stroke="#111111" stroke-width="3"/>
        <text x="35" y="\(height - 18)" font-family="Arial" font-size="10">1 m</text>
        <text x="\(width / 2)" y="\(height - 20)" text-anchor="middle" font-family="Arial" font-size="11" font-weight="700" fill="#1677FF">SPATIALSENSE</text>
        <g transform="translate(\(width - 45), 38)">
          <line x1="0" y1="13" x2="0" y2="-13" stroke="#222222" stroke-width="1.5"/>
          <path d="M 0 -18 L -5 -8 L 5 -8 z" fill="#222222"/>
          <text x="0" y="28" text-anchor="middle" font-family="Arial" font-size="10">N</text>
        </g>
        </svg>
        """

        return svg
    }

    // MARK: - DXF Export

    /// Export floor plan data to DXF format (AutoCAD compatible)
    static func exportToDXF(data: FloorPlanData, wifiSamples: [WiFiSample] = [], includeDimensions: Bool = true) -> String {
        let scale: Float = 1.0  // 1 unit = 1 meter

        var dxf = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        9
        $INSUNITS
        70
        6
        0
        ENDSEC
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        LAYER
        70
        5
        0
        LAYER
        2
        WALLS
        70
        0
        62
        7
        6
        CONTINUOUS
        0
        LAYER
        2
        DOORS
        70
        0
        62
        3
        6
        CONTINUOUS
        0
        LAYER
        2
        WINDOWS
        70
        0
        62
        5
        6
        CONTINUOUS
        0
        LAYER
        2
        OBJECTS
        70
        0
        62
        8
        6
        CONTINUOUS
        0
        LAYER
        2
        DIMENSIONS
        70
        0
        62
        1
        6
        CONTINUOUS
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES

        """

        // Helper to offset coordinates from bounding box origin
        func tx(_ x: CGFloat) -> Float {
            return Float(x - data.boundingBox.minX) * scale
        }
        func ty(_ y: CGFloat) -> Float {
            return Float(y - data.boundingBox.minY) * scale
        }

        func rotatedCorners(of element: FloorPlanElement) -> [CGPoint] {
            let center = CGPoint(x: element.rect.midX, y: element.rect.midY)
            let cosine = cos(element.rotation)
            let sine = sin(element.rotation)
            return [
                CGPoint(x: element.rect.minX, y: element.rect.minY),
                CGPoint(x: element.rect.maxX, y: element.rect.minY),
                CGPoint(x: element.rect.maxX, y: element.rect.maxY),
                CGPoint(x: element.rect.minX, y: element.rect.maxY)
            ].map { point in
                let x = point.x - center.x
                let y = point.y - center.y
                return CGPoint(
                    x: center.x + x * cosine - y * sine,
                    y: center.y + x * sine + y * cosine
                )
            }
        }

        func appendPolyline(_ element: FloorPlanElement, layer: String) {
            let corners = rotatedCorners(of: element)
            dxf += """
            0
            LWPOLYLINE
            8
            \(layer)
            90
            4
            70
            1

            """
            for corner in corners {
                dxf += """
                10
                \(tx(corner.x))
                20
                \(ty(corner.y))

                """
            }
        }

        for element in data.elements {
            let layer: String
            switch element.type {
            case .wall: layer = "WALLS"
            case .door: layer = "DOORS"
            case .window: layer = "WINDOWS"
            case .opening: layer = "DOORS"
            case .object: layer = "OBJECTS"
            }
            appendPolyline(element, layer: layer)

            if case .object = element.type, let label = element.label {
                dxf += """
                0
                TEXT
                8
                OBJECTS
                10
                \(tx(element.rect.midX))
                20
                \(ty(element.rect.midY))
                40
                0.15
                1
                \(label)

                """
            }
        }

        // Add dimension text
        if includeDimensions {
            let roomWidth = String(format: "%.2f m", data.roomDimensions.width)
            let roomDepth = String(format: "%.2f m", data.roomDimensions.depth)
            let totalWidth = Float(data.boundingBox.width) * scale
            let totalHeight = Float(data.boundingBox.height) * scale

            // Width dimension
            dxf += """
            0
            TEXT
            8
            DIMENSIONS
            10
            \(totalWidth / 2)
            20
            \(-0.3)
            40
            0.2
            1
            \(roomWidth)

            """

            // Depth dimension
            dxf += """
            0
            TEXT
            8
            DIMENSIONS
            10
            \(totalWidth + 0.3)
            20
            \(totalHeight / 2)
            40
            0.2
            1
            \(roomDepth)

            """
        }

        // WiFi sample points as CIRCLE entities
        if !wifiSamples.isEmpty {
            for sample in wifiSamples {
                let x = tx(CGFloat(sample.position.x))
                let y = ty(CGFloat(sample.position.z)) // Use z for 2D floor plan
                let signalStrength = sample.rssi

                // Determine color based on signal strength
                let colorNumber: Int
                let normalizedSignal = (Double(signalStrength) + 90) / 60.0 // 0 (poor) to 1 (excellent)
                if normalizedSignal > 0.75 {
                    colorNumber = 3 // Green (excellent)
                } else if normalizedSignal > 0.5 {
                    colorNumber = 4 // Cyan (good)
                } else if normalizedSignal > 0.25 {
                    colorNumber = 2 // Yellow (fair)
                } else {
                    colorNumber = 1 // Red (poor)
                }

                dxf += """
                0
                CIRCLE
                8
                WIFI
                62
                \(colorNumber)
                10
                \(x)
                20
                \(y)
                40
                0.1

                """
            }
        }

        dxf += """
        0
        ENDSEC
        0
        EOF
        """

        return dxf
    }

    // MARK: - Export to File

    /// Export floor plan to file and return URL
    static func export(data: FloorPlanData, format: ExportFormat, includeDimensions: Bool = true) throws -> URL {
        let content: String
        switch format {
        case .svg:
            content = exportToSVG(data: data, includeDimensions: includeDimensions)
        case .dxf:
            content = exportToDXF(data: data, includeDimensions: includeDimensions)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = "FloorPlan_\(timestamp).\(format.fileExtension)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
