/*
See LICENSE folder for this sample's licensing information.

Abstract:
A view that renders a 2D floor plan from CapturedRoom data (Issues #7, #9, #10).
*/

import UIKit
import RoomPlan
import simd

// MARK: - Floor Plan Configuration

enum FloorPlanConfig {
    static let wallColor = UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
    static let doorColor = UIColor(red: 0.55, green: 0.35, blue: 0.18, alpha: 1)
    static let windowColor = SpatialSenseTheme.Color.primary
    static let objectColor = UIColor(red: 0.95, green: 0.55, blue: 0.18, alpha: 1)
    static let openingColor = UIColor(white: 0.75, alpha: 1)
    static let backgroundColor = SpatialSenseTheme.Color.canvas
    static let dimensionColor = SpatialSenseTheme.Color.textSecondary

    static let wallThickness: CGFloat = 4.0
    static let doorThickness: CGFloat = 2.0
    static let windowThickness: CGFloat = 3.0
    static let objectCornerRadius: CGFloat = SpatialSenseTheme.Radius.sm

    static let padding: CGFloat = 40.0
    static let dimensionFontSize: CGFloat = 10.0
    static let labelFontSize: CGFloat = 12.0

    static let metersToPoints: CGFloat = 100.0 // Base scale: 1 meter = 100 points
}

// MARK: - Floor Plan Element

struct FloorPlanElement: Codable {
    let rect: CGRect
    let rotation: CGFloat
    let type: ElementType
    let label: String?
    /// World-space center height and measured height, used by the native 3D viewer.
    /// Optional so floor plans saved by earlier app versions remain decodable.
    let elevation: CGFloat?
    let verticalExtent: CGFloat?

    init(
        rect: CGRect,
        rotation: CGFloat,
        type: ElementType,
        label: String?,
        elevation: CGFloat? = nil,
        verticalExtent: CGFloat? = nil
    ) {
        self.rect = rect
        self.rotation = rotation
        self.type = type
        self.label = label
        self.elevation = elevation
        self.verticalExtent = verticalExtent
    }

    enum ElementType: Codable {
        case wall
        case door
        case window
        case opening
        case object(category: String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            switch value {
            case "wall": self = .wall
            case "door": self = .door
            case "window": self = .window
            case "opening": self = .opening
            default:
                if value.starts(with: "object:") {
                    let category = String(value.dropFirst(7))
                    self = .object(category: category)
                } else {
                    self = .object(category: value)
                }
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .wall: try container.encode("wall")
            case .door: try container.encode("door")
            case .window: try container.encode("window")
            case .opening: try container.encode("opening")
            case .object(let category): try container.encode("object:\(category)")
            }
        }
    }
}

// MARK: - Floor Plan Data

struct FloorComponent: Codable, Equatable {
    let polygon: [CGPoint]
    /// Elevation relative to the room's persisted vertical datum.
    let elevation: CGFloat
}

struct RawFloorComponent {
    let polygon: [CGPoint]
    let elevation: CGFloat
}

struct RawVerticalElement {
    let center: CGFloat
    let extent: CGFloat
    let isFloorStandingDatumCandidate: Bool
}

struct FloorPlanVerticalNormalization {
    let datum: CGFloat?
    let floorComponents: [FloorComponent]
    let elementCenters: [CGFloat?]
}

enum FloorPlanVerticalNormalizer {
    static func normalize(
        floors: [RawFloorComponent],
        elements: [RawVerticalElement]
    ) -> FloorPlanVerticalNormalization {
        let floorElevations = floors.map(\.elevation).filter(\.isFinite)
        let fallbackBottoms = elements.compactMap { element -> CGFloat? in
            guard
                element.isFloorStandingDatumCandidate,
                element.center.isFinite,
                element.extent.isFinite
            else {
                return nil
            }
            return element.center - element.extent / 2
        }
        let datum = median(floorElevations) ?? median(fallbackBottoms)
        let normalizedFloors = floors.compactMap { floor -> FloorComponent? in
            guard let datum, datum.isFinite, floor.elevation.isFinite else { return nil }
            return FloorComponent(
                polygon: floor.polygon,
                elevation: floor.elevation - datum
            )
        }
        let normalizedCenters = elements.map { element -> CGFloat? in
            guard
                let datum,
                datum.isFinite,
                element.center.isFinite
            else {
                return nil
            }
            return element.center - datum
        }
        return FloorPlanVerticalNormalization(
            datum: datum,
            floorComponents: normalizedFloors,
            elementCenters: normalizedCenters
        )
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

struct FloorPlanData: Codable {
    static let currentSchemaVersion = 3
    static let supportedReconstructionSchemaVersions: Set<Int> = [currentSchemaVersion]

    let schemaVersion: Int
    let elements: [FloorPlanElement]
    let boundingBox: CGRect
    let roomDimensions: (width: Float, height: Float, depth: Float)
    let boundary: [CGPoint]
    /// Floor outlines reported directly by RoomPlan. Empty in legacy saves that predate this field.
    let floorPolygons: [[CGPoint]]
    /// Version 3 floor surfaces with elevation relative to `verticalDatum`.
    let floorComponents: [FloorComponent]
    let roomArea: Float
    var roomName: String
    let createdAt: Date
    /// Rigid rotation from capture coordinates into the presentation coordinate system.
    let presentationRotation: CGFloat
    /// RoomPlan world-space floor elevation used to normalize all vertical geometry.
    /// Nil identifies legacy/intermediate data that is unsafe for native reconstruction.
    let verticalDatum: CGFloat?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, elements, boundingBox, roomWidth, roomHeight, roomDepth
        case boundary, floorPolygons, floorComponents
        case roomArea, roomName, createdAt, presentationRotation, verticalDatum
    }

    init(
        schemaVersion: Int = FloorPlanData.currentSchemaVersion,
        elements: [FloorPlanElement],
        boundingBox: CGRect,
        roomDimensions: (width: Float, height: Float, depth: Float),
        boundary: [CGPoint] = [],
        floorPolygons: [[CGPoint]] = [],
        floorComponents: [FloorComponent] = [],
        roomArea: Float = 0,
        roomName: String = "Room",
        createdAt: Date = Date(),
        presentationRotation: CGFloat = 0,
        verticalDatum: CGFloat? = 0
    ) {
        self.schemaVersion = schemaVersion
        self.elements = elements
        self.boundingBox = boundingBox
        self.roomDimensions = roomDimensions
        self.boundary = boundary
        self.floorPolygons = floorPolygons
        self.floorComponents = floorComponents.isEmpty
            ? floorPolygons.map { FloorComponent(polygon: $0, elevation: 0) }
            : floorComponents
        self.roomArea = roomArea
        self.roomName = roomName
        self.createdAt = createdAt
        self.presentationRotation = presentationRotation
        self.verticalDatum = verticalDatum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        elements = try container.decode([FloorPlanElement].self, forKey: .elements)
        boundingBox = try container.decode(CGRect.self, forKey: .boundingBox)
        let width = try container.decode(Float.self, forKey: .roomWidth)
        let height = try container.decode(Float.self, forKey: .roomHeight)
        let depth = try container.decode(Float.self, forKey: .roomDepth)
        roomDimensions = (width, height, depth)
        boundary = try container.decodeIfPresent([CGPoint].self, forKey: .boundary) ?? []
        floorPolygons = try container.decodeIfPresent([[CGPoint]].self, forKey: .floorPolygons) ?? []
        floorComponents = try container.decodeIfPresent(
            [FloorComponent].self,
            forKey: .floorComponents
        ) ?? []
        roomArea = try container.decodeIfPresent(Float.self, forKey: .roomArea) ?? width * depth
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName) ?? "Room"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        presentationRotation = try container.decodeIfPresent(CGFloat.self, forKey: .presentationRotation) ?? 0
        verticalDatum = try container.decodeIfPresent(CGFloat.self, forKey: .verticalDatum)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(elements, forKey: .elements)
        try container.encode(boundingBox, forKey: .boundingBox)
        try container.encode(roomDimensions.width, forKey: .roomWidth)
        try container.encode(roomDimensions.height, forKey: .roomHeight)
        try container.encode(roomDimensions.depth, forKey: .roomDepth)
        try container.encode(boundary, forKey: .boundary)
        try container.encode(floorPolygons, forKey: .floorPolygons)
        try container.encode(floorComponents, forKey: .floorComponents)
        try container.encode(roomArea, forKey: .roomArea)
        try container.encode(roomName, forKey: .roomName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(presentationRotation, forKey: .presentationRotation)
        try container.encodeIfPresent(verticalDatum, forKey: .verticalDatum)
    }

    static func from(_ room: CapturedRoom) -> FloorPlanData {
        var elements: [FloorPlanElement] = []
        let rawFloors: [RawFloorComponent] = room.floors.compactMap { floor in
            let points = floor.polygonCorners.map { corner -> CGPoint in
                let world = floor.transform * SIMD4<Float>(corner.x, corner.y, corner.z, 1)
                return CGPoint(x: CGFloat(world.x), y: CGFloat(world.z))
            }
            guard let polygon = FloorFootprint.sanitizedPolygon(points) else { return nil }
            return RawFloorComponent(
                polygon: polygon,
                elevation: CGFloat(floor.transform.columns.3.y)
            )
        }
        let rawVerticalElements =
            room.walls.map {
                RawVerticalElement(
                    center: CGFloat($0.transform.columns.3.y),
                    extent: CGFloat($0.dimensions.y),
                    isFloorStandingDatumCandidate: true
                )
            }
            + room.doors.map {
                RawVerticalElement(
                    center: CGFloat($0.transform.columns.3.y),
                    extent: CGFloat($0.dimensions.y),
                    isFloorStandingDatumCandidate: false
                )
            }
            + room.windows.map {
                RawVerticalElement(
                    center: CGFloat($0.transform.columns.3.y),
                    extent: CGFloat($0.dimensions.y),
                    isFloorStandingDatumCandidate: false
                )
            }
            + room.openings.map {
                RawVerticalElement(
                    center: CGFloat($0.transform.columns.3.y),
                    extent: CGFloat($0.dimensions.y),
                    isFloorStandingDatumCandidate: false
                )
            }
            + room.objects.map {
                RawVerticalElement(
                    center: CGFloat($0.transform.columns.3.y),
                    extent: CGFloat($0.dimensions.y),
                    isFloorStandingDatumCandidate: true
                )
            }
        let vertical = FloorPlanVerticalNormalizer.normalize(
            floors: rawFloors,
            elements: rawVerticalElements
        )
        var verticalIndex = 0
        func nextElevation() -> CGFloat? {
            defer { verticalIndex += 1 }
            return vertical.elementCenters[verticalIndex]
        }

        // Process walls
        for wall in room.walls {
            let element = FloorPlanElement(
                rect: rectFrom(surface: wall),
                rotation: rotationFrom(transform: wall.transform),
                type: .wall,
                label: nil,
                elevation: nextElevation(),
                verticalExtent: CGFloat(wall.dimensions.y)
            )
            elements.append(element)
        }

        // Process doors
        for door in room.doors {
            let element = FloorPlanElement(
                rect: rectFrom(surface: door),
                rotation: rotationFrom(transform: door.transform),
                type: .door,
                label: nil,
                elevation: nextElevation(),
                verticalExtent: CGFloat(door.dimensions.y)
            )
            elements.append(element)
        }

        // Process windows
        for window in room.windows {
            let element = FloorPlanElement(
                rect: rectFrom(surface: window),
                rotation: rotationFrom(transform: window.transform),
                type: .window,
                label: nil,
                elevation: nextElevation(),
                verticalExtent: CGFloat(window.dimensions.y)
            )
            elements.append(element)
        }

        // Process openings
        for opening in room.openings {
            let element = FloorPlanElement(
                rect: rectFrom(surface: opening),
                rotation: rotationFrom(transform: opening.transform),
                type: .opening,
                label: nil,
                elevation: nextElevation(),
                verticalExtent: CGFloat(opening.dimensions.y)
            )
            elements.append(element)
        }

        // Process objects
        for object in room.objects {
            let element = FloorPlanElement(
                rect: rectFrom(object: object),
                rotation: rotationFrom(transform: object.transform),
                type: .object(category: String(describing: object.category)),
                label: labelFor(category: object.category),
                elevation: nextElevation(),
                verticalExtent: CGFloat(object.dimensions.y)
            )
            elements.append(element)
        }

        let rawFloorPolygons = rawFloors.map(\.polygon)
        let wallBoundary = FloorFootprint.boundary(from: elements)
        let rawBoundary = rawFloorPolygons.max {
            FloorFootprint.area(of: $0) < FloorFootprint.area(of: $1)
        } ?? wallBoundary
        let presentation = FloorPlanPresentation.normalize(elements: elements, boundary: rawBoundary)
        let normalizedFloorComponents = vertical.floorComponents.map { component in
            FloorComponent(
                polygon: component.polygon.map {
                    FloorPlanPresentation.point($0, rotatedBy: presentation.rotation)
                },
                elevation: component.elevation
            )
        }
        let normalizedFloorPolygons = normalizedFloorComponents.map(\.polygon)
        let sceneBoundingBox = boundingBox(
            elements: presentation.elements,
            polygons: normalizedFloorPolygons.isEmpty ? [presentation.boundary] : normalizedFloorPolygons
        )
        let capturedDimensions = RoomGeometry.getBoundingBox(from: room)
        let dimensions = (
            width: Float(sceneBoundingBox.width),
            height: capturedDimensions.height,
            depth: Float(sceneBoundingBox.height)
        )
        let area = normalizedFloorPolygons.isEmpty
            ? polygonArea(presentation.boundary)
            : normalizedFloorPolygons.reduce(0) { $0 + polygonArea($1) }
        let detectedType = RoomTypeDetector.detectRoomType(from: room).roomType
        let roomName = detectedType == .unknown ? "Room" : detectedType.rawValue

        return FloorPlanData(
            elements: presentation.elements,
            boundingBox: sceneBoundingBox,
            roomDimensions: dimensions,
            boundary: presentation.boundary,
            floorPolygons: normalizedFloorPolygons,
            floorComponents: normalizedFloorComponents,
            roomArea: area > 0 ? Float(area) : RoomGeometry.calculateApproximateFloorArea(from: room),
            roomName: roomName,
            presentationRotation: presentation.rotation,
            verticalDatum: vertical.datum
        )
    }

    private static func rectFrom(surface: any RoomPlanSurface) -> CGRect {
        let position = surface.transform.columns.3
        let dimensions = surface.dimensions
        // RoomPlan surfaces are vertical planes. Their Z dimension is normally zero,
        // so using it directly produces zero-height rectangles and invisible walls.
        let planThickness = normalizedWallThickness(CGFloat(dimensions.z))

        // Build the surface in its local X/Z plane, then rotate it around its center.
        return CGRect(
            x: CGFloat(position.x - dimensions.x / 2),
            y: CGFloat(position.z) - planThickness / 2,
            width: CGFloat(dimensions.x),
            height: planThickness
        )
    }

    private static func rectFrom(object: CapturedRoom.Object) -> CGRect {
        let position = object.transform.columns.3
        let dimensions = object.dimensions

        return CGRect(
            x: CGFloat(position.x - dimensions.x / 2),
            y: CGFloat(position.z - dimensions.z / 2),
            width: CGFloat(dimensions.x),
            height: CGFloat(dimensions.z)
        )
    }

    private static func rotationFrom(transform: simd_float4x4) -> CGFloat {
        // Extract Y-axis rotation from transform matrix
        let rotation = atan2(transform.columns.0.z, transform.columns.0.x)
        return CGFloat(rotation)
    }

    static func calculateBoundingBox(elements: [FloorPlanElement]) -> CGRect {
        guard !elements.isEmpty else { return .zero }

        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        for element in elements {
            let rotatedBounds = boundingRect(of: element.rect, rotatedBy: element.rotation)
            minX = min(minX, rotatedBounds.minX)
            maxX = max(maxX, rotatedBounds.maxX)
            minY = min(minY, rotatedBounds.minY)
            maxY = max(maxY, rotatedBounds.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func boundingBox(elements: [FloorPlanElement], polygons: [[CGPoint]]) -> CGRect {
        var bounds: CGRect?
        let elementBounds = calculateBoundingBox(elements: elements)
        if !elementBounds.isNull && elementBounds != .zero {
            bounds = elementBounds
        }
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            let polygonBounds = polygon.dropFirst().reduce(
                CGRect(origin: first, size: .zero)
            ) { $0.union(CGRect(origin: $1, size: .zero)) }
            bounds = bounds.map { $0.union(polygonBounds) } ?? polygonBounds
        }
        return bounds ?? .zero
    }

    static func boundingRect(of rect: CGRect, rotatedBy angle: CGFloat) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cosine = cos(angle)
        let sine = sin(angle)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { point -> CGPoint in
            let x = point.x - center.x
            let y = point.y - center.y
            return CGPoint(
                x: center.x + x * cosine - y * sine,
                y: center.y + x * sine + y * cosine
            )
        }

        let minX = corners.map(\.x).min() ?? rect.minX
        let maxX = corners.map(\.x).max() ?? rect.maxX
        let minY = corners.map(\.y).min() ?? rect.minY
        let maxY = corners.map(\.y).max() ?? rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func normalizedWallThickness(_ measuredThickness: CGFloat) -> CGFloat {
        // Ignore noisy RoomPlan Z. Plan walls always use one visual thickness.
        _ = measuredThickness
        return FloorPlanStyle.wallThicknessMeters
    }

    private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return abs(sum) / 2
    }

    private static func labelFor(category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: return L10n.ObjectType.storage.localized
        case .refrigerator: return L10n.ObjectType.fridge.localized
        case .stove: return L10n.ObjectType.stove.localized
        case .bed: return L10n.ObjectType.bed.localized
        case .sink: return L10n.ObjectType.sink.localized
        case .washerDryer: return L10n.ObjectType.washer.localized
        case .toilet: return L10n.ObjectType.toilet.localized
        case .bathtub: return L10n.ObjectType.bathtub.localized
        case .oven: return L10n.ObjectType.oven.localized
        case .dishwasher: return L10n.ObjectType.dishwasher.localized
        case .table: return L10n.ObjectType.table.localized
        case .sofa: return L10n.ObjectType.sofa.localized
        case .chair: return L10n.ObjectType.chair.localized
        case .fireplace: return L10n.ObjectType.fireplace.localized
        case .television: return L10n.ObjectType.tv.localized
        case .stairs: return L10n.ObjectType.stairs.localized
        @unknown default: return L10n.ObjectType.unknown.localized
        }
    }
}

// MARK: - Presentation Normalization

/// Produces an axis-aligned presentation without snapping or otherwise changing measured geometry.
/// A single weighted rigid rotation is applied to every wall, opening, object, and boundary point.
enum FloorPlanPresentation {
    struct Result {
        let elements: [FloorPlanElement]
        let boundary: [CGPoint]
        let boundingBox: CGRect
        let rotation: CGFloat
    }

    static func normalize(elements: [FloorPlanElement], boundary: [CGPoint]) -> Result {
        let walls = elements.filter {
            if case .wall = $0.type { return true }
            return false
        }
        let correction = dominantAxisCorrection(for: walls)
        let cosine = cos(correction)
        let sine = sin(correction)

        func rotate(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x * cosine - point.y * sine,
                y: point.x * sine + point.y * cosine
            )
        }

        let normalizedElements = elements.map { element -> FloorPlanElement in
            let center = rotate(CGPoint(x: element.rect.midX, y: element.rect.midY))
            return FloorPlanElement(
                rect: CGRect(
                    x: center.x - element.rect.width / 2,
                    y: center.y - element.rect.height / 2,
                    width: element.rect.width,
                    height: element.rect.height
                ),
                rotation: normalizedAngle(element.rotation + correction),
                type: element.type,
                label: element.label,
                elevation: element.elevation,
                verticalExtent: element.verticalExtent
            )
        }
        let normalizedBoundary = boundary.map(rotate)
        let boundingBox = FloorPlanData.calculateBoundingBox(elements: normalizedElements)

        return Result(
            elements: normalizedElements,
            boundary: normalizedBoundary,
            boundingBox: boundingBox,
            rotation: correction
        )
    }

    /// Converts a point recorded in the original RoomPlan world coordinates into plan coordinates.
    static func point(_ point: CGPoint, rotatedBy angle: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x * cos(angle) - point.y * sin(angle),
            y: point.x * sin(angle) + point.y * cos(angle)
        )
    }

    private static func dominantAxisCorrection(for walls: [FloorPlanElement]) -> CGFloat {
        guard !walls.isEmpty else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for wall in walls {
            let weight = max(wall.rect.width, 0.01)
            x += weight * cos(4 * wall.rotation)
            y += weight * sin(4 * wall.rotation)
        }
        guard hypot(x, y) > 0.0001 else { return 0 }
        return -atan2(y, x) / 4
    }

    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        atan2(sin(angle), cos(angle))
    }
}

// MARK: - RoomPlan Surface Protocol

private protocol RoomPlanSurface {
    var transform: simd_float4x4 { get }
    var dimensions: simd_float3 { get }
}

extension CapturedRoom.Surface: RoomPlanSurface {}

// MARK: - Floor Plan View

class FloorPlanView: UIView, UIGestureRecognizerDelegate {

    private var floorPlanData: FloorPlanData?
    private var scale: CGFloat = 1.0
    private var offset: CGPoint = .zero

    // Zoom, pan, and rotation
    private var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var rotationAngle: CGFloat = 0.0
    private var minZoom: CGFloat = 0.5
    private var maxZoom: CGFloat = 4.0

    var showDimensions: Bool = true {
        didSet { setNeedsDisplay() }
    }

    var showLabels: Bool = true {
        didSet { setNeedsDisplay() }
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = FloorPlanConfig.backgroundColor
        contentMode = .redraw
        isUserInteractionEnabled = true

        // Add zoom gesture
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)

        // Add pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        addGestureRecognizer(panGesture)

        // Add rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        addGestureRecognizer(rotationGesture)

        // Add double-tap to reset zoom
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        // Enable simultaneous gestures
        pinchGesture.delegate = self
        panGesture.delegate = self
        rotationGesture.delegate = self
    }

    // MARK: - Gesture Handlers

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let newZoom = zoomScale * gesture.scale
            zoomScale = min(max(newZoom, minZoom), maxZoom)
            gesture.scale = 1.0
            setNeedsDisplay()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .changed {
            let translation = gesture.translation(in: self)
            panOffset.x += translation.x
            panOffset.y += translation.y
            gesture.setTranslation(.zero, in: self)
            setNeedsDisplay()
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .changed:
            rotationAngle += gesture.rotation
            gesture.rotation = 0.0
            setNeedsDisplay()
        case .began, .ended:
            #if DEBUG
            print("Rotation: \(rotationAngle * 180 / .pi)°")
            #endif
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // Reset zoom, pan, and rotation
        UIView.animate(withDuration: 0.3) {
            self.zoomScale = 1.0
            self.panOffset = .zero
            self.rotationAngle = 0.0
            self.setNeedsDisplay()
        }
    }

    // MARK: - Public Methods

    func configure(with room: CapturedRoom) {
        floorPlanData = FloorPlanData.from(room)
        calculateTransform()
        setNeedsDisplay()
    }

    func configure(with data: FloorPlanData) {
        floorPlanData = data
        calculateTransform()
        setNeedsDisplay()
    }

    func clear() {
        floorPlanData = nil
        zoomScale = 1.0
        panOffset = .zero
        setNeedsDisplay()
    }

    func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
        rotationAngle = 0.0
        setNeedsDisplay()
    }

    // MARK: - Transform Calculation

    private func calculateTransform() {
        guard let data = floorPlanData else { return }

        let availableWidth = bounds.width - FloorPlanConfig.padding * 2
        let availableHeight = bounds.height - FloorPlanConfig.padding * 2

        guard availableWidth > 0, availableHeight > 0 else { return }

        let boundingBox = data.boundingBox
        guard boundingBox.width > 0, boundingBox.height > 0 else { return }

        // Calculate scale to fit room in view
        let scaleX = availableWidth / (boundingBox.width * FloorPlanConfig.metersToPoints)
        let scaleY = availableHeight / (boundingBox.height * FloorPlanConfig.metersToPoints)
        scale = min(scaleX, scaleY)

        // Calculate offset to center room in view
        let scaledWidth = boundingBox.width * FloorPlanConfig.metersToPoints * scale
        let scaledHeight = boundingBox.height * FloorPlanConfig.metersToPoints * scale

        offset = CGPoint(
            x: FloorPlanConfig.padding + (availableWidth - scaledWidth) / 2 - boundingBox.minX * FloorPlanConfig.metersToPoints * scale,
            y: FloorPlanConfig.padding + (availableHeight - scaledHeight) / 2 - boundingBox.minY * FloorPlanConfig.metersToPoints * scale
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        calculateTransform()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let data = floorPlanData else { return }

        context.saveGState()

        // Apply zoom, pan, and rotation transformations
        context.translateBy(x: bounds.midX + panOffset.x, y: bounds.midY + panOffset.y)
        context.rotate(by: rotationAngle)
        context.scaleBy(x: zoomScale, y: zoomScale)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)

        FloorPlanDocumentRenderer.draw(
            data: data,
            in: bounds,
            context: context,
            options: FloorPlanRenderOptions(
                showDimensions: showDimensions,
                showLabels: showLabels,
                presentation: FloorPlanRenderPresentation.viewer
            )
        )

        context.restoreGState()

        // Draw zoom/rotation indicator
        if zoomScale != 1.0 || rotationAngle != 0.0 {
            drawTransformIndicator(in: context)
        }
    }

    private func drawTransformIndicator(in context: CGContext) {
        var indicators: [String] = []

        if zoomScale != 1.0 {
            indicators.append(String(format: "%.0f%%", zoomScale * 100))
        }

        if rotationAngle != 0.0 {
            let degrees = Int(rotationAngle * 180 / .pi) % 360
            indicators.append(String(format: "%d°", degrees))
        }

        let text = indicators.joined(separator: " • ")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = text.size(withAttributes: attributes)
        let point = CGPoint(x: bounds.width - size.width - 16, y: bounds.height - size.height - 16)
        text.draw(at: point, withAttributes: attributes)
    }

    private func drawElement(_ element: FloorPlanElement, in context: CGContext) {
        let transformedRect = transformRect(element.rect)

        context.saveGState()

        // Apply rotation around center
        let center = CGPoint(x: transformedRect.midX, y: transformedRect.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: element.rotation)
        context.translateBy(x: -center.x, y: -center.y)

        switch element.type {
        case .wall:
            drawWall(rect: transformedRect, in: context)
        case .door:
            drawDoor(rect: transformedRect, in: context)
        case .window:
            drawWindow(rect: transformedRect, in: context)
        case .opening:
            drawOpening(rect: transformedRect, in: context)
        case .object(let category):
            drawObject(rect: transformedRect, category: category, label: element.label, in: context)
        }

        context.restoreGState()
    }

    private func transformRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * FloorPlanConfig.metersToPoints * scale + offset.x,
            y: rect.origin.y * FloorPlanConfig.metersToPoints * scale + offset.y,
            width: rect.width * FloorPlanConfig.metersToPoints * scale,
            height: rect.height * FloorPlanConfig.metersToPoints * scale
        )
    }

    private func drawWall(rect: CGRect, in context: CGContext) {
        context.setFillColor(FloorPlanConfig.wallColor.cgColor)
        context.fill(rect)
    }

    private func drawDoor(rect: CGRect, in context: CGContext) {
        context.setStrokeColor(FloorPlanConfig.doorColor.cgColor)
        context.setLineWidth(FloorPlanConfig.doorThickness)

        // Draw door as an arc (swing indicator)
        let arcRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.width)
        context.addArc(center: CGPoint(x: arcRect.minX, y: arcRect.midY),
                       radius: rect.width,
                       startAngle: -.pi / 2,
                       endAngle: 0,
                       clockwise: false)
        context.strokePath()

        // Draw door line
        context.move(to: CGPoint(x: rect.minX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.strokePath()
    }

    private func drawWindow(rect: CGRect, in context: CGContext) {
        context.setStrokeColor(FloorPlanConfig.windowColor.cgColor)
        context.setLineWidth(FloorPlanConfig.windowThickness)

        // Draw window as double line
        let inset: CGFloat = 2
        context.stroke(rect)
        context.stroke(rect.insetBy(dx: inset, dy: inset))
    }

    private func drawOpening(rect: CGRect, in context: CGContext) {
        context.setStrokeColor(FloorPlanConfig.openingColor.cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawObject(rect: CGRect, category: String, label: String?, in context: CGContext) {
        let color = colorFor(categoryString: category)
        context.setFillColor(color.withAlphaComponent(0.3).cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)

        let path = UIBezierPath(roundedRect: rect, cornerRadius: FloorPlanConfig.objectCornerRadius)
        context.addPath(path.cgPath)
        context.drawPath(using: .fillStroke)

        // Draw label
        if showLabels, let label = label, rect.width > 20 {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: FloorPlanConfig.labelFontSize, weight: .medium),
                .foregroundColor: color
            ]
            let size = label.size(withAttributes: attributes)
            if size.width < rect.width - 4 {
                let point = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
                label.draw(at: point, withAttributes: attributes)
            }
        }
    }

    private func colorFor(category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .bed, .sofa, .chair:
            return .systemPurple
        case .table:
            return .systemBrown
        case .storage, .refrigerator, .stove, .oven, .dishwasher, .washerDryer:
            return .systemGray
        case .sink, .toilet, .bathtub:
            return .systemCyan
        case .television:
            return .systemIndigo
        case .fireplace:
            return .systemOrange
        case .stairs:
            return .systemYellow
        @unknown default:
            return FloorPlanConfig.objectColor
        }
    }

    private func colorFor(categoryString: String) -> UIColor {
        switch categoryString.lowercased() {
        case let s where s.contains("bed"), let s where s.contains("sofa"), let s where s.contains("chair"):
            return .systemPurple
        case let s where s.contains("table"):
            return .systemBrown
        case let s where s.contains("storage"), let s where s.contains("refrigerator"), let s where s.contains("stove"),
             let s where s.contains("oven"), let s where s.contains("dishwasher"), let s where s.contains("washer"):
            return .systemGray
        case let s where s.contains("sink"), let s where s.contains("toilet"), let s where s.contains("bathtub"):
            return .systemCyan
        case let s where s.contains("television"):
            return .systemIndigo
        case let s where s.contains("fireplace"):
            return .systemOrange
        case let s where s.contains("stairs"):
            return .systemYellow
        default:
            return FloorPlanConfig.objectColor
        }
    }

    private func drawDimensions(data: FloorPlanData, in context: CGContext) {
        let dims = data.roomDimensions
        guard dims.width > 0, dims.depth > 0 else { return }

        let widthText = String(format: "%.2f m", dims.width)
        let depthText = String(format: "%.2f m", dims.depth)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: FloorPlanConfig.dimensionFontSize),
            .foregroundColor: FloorPlanConfig.dimensionColor
        ]

        // Draw width dimension at bottom
        let widthSize = widthText.size(withAttributes: attributes)
        let widthPoint = CGPoint(
            x: bounds.midX - widthSize.width / 2,
            y: bounds.maxY - FloorPlanConfig.padding / 2 - widthSize.height / 2
        )
        widthText.draw(at: widthPoint, withAttributes: attributes)

        // Draw depth dimension on right side
        let depthSize = depthText.size(withAttributes: attributes)
        context.saveGState()
        context.translateBy(x: bounds.maxX - FloorPlanConfig.padding / 2, y: bounds.midY)
        context.rotate(by: -.pi / 2)
        depthText.draw(at: CGPoint(x: -depthSize.width / 2, y: -depthSize.height / 2), withAttributes: attributes)
        context.restoreGState()
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch, pan, and rotation to work simultaneously
        return true
    }
}
