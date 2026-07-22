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

    // WiFi heatmap colors
    static let wifiExcellentColor = UIColor.systemGreen
    static let wifiGoodColor = UIColor.systemYellow
    static let wifiFairColor = UIColor.systemOrange
    static let wifiPoorColor = UIColor.systemRed
    static let wifiDotRadius: CGFloat = 15.0
    static let wifiDotAlpha: CGFloat = 0.6
}

// MARK: - Floor Plan Element

struct FloorPlanElement: Codable {
    let rect: CGRect
    let rotation: CGFloat
    let type: ElementType
    let label: String?

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

struct FloorPlanData: Codable {
    let elements: [FloorPlanElement]
    let boundingBox: CGRect
    let roomDimensions: (width: Float, height: Float, depth: Float)
    let boundary: [CGPoint]
    let roomArea: Float
    let roomName: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case elements, boundingBox, roomWidth, roomHeight, roomDepth
        case boundary, roomArea, roomName, createdAt
    }

    init(
        elements: [FloorPlanElement],
        boundingBox: CGRect,
        roomDimensions: (width: Float, height: Float, depth: Float),
        boundary: [CGPoint] = [],
        roomArea: Float = 0,
        roomName: String = "Room",
        createdAt: Date = Date()
    ) {
        self.elements = elements
        self.boundingBox = boundingBox
        self.roomDimensions = roomDimensions
        self.boundary = boundary
        self.roomArea = roomArea
        self.roomName = roomName
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elements = try container.decode([FloorPlanElement].self, forKey: .elements)
        boundingBox = try container.decode(CGRect.self, forKey: .boundingBox)
        let width = try container.decode(Float.self, forKey: .roomWidth)
        let height = try container.decode(Float.self, forKey: .roomHeight)
        let depth = try container.decode(Float.self, forKey: .roomDepth)
        roomDimensions = (width, height, depth)
        boundary = try container.decodeIfPresent([CGPoint].self, forKey: .boundary) ?? []
        roomArea = try container.decodeIfPresent(Float.self, forKey: .roomArea) ?? width * depth
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName) ?? "Room"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(elements, forKey: .elements)
        try container.encode(boundingBox, forKey: .boundingBox)
        try container.encode(roomDimensions.width, forKey: .roomWidth)
        try container.encode(roomDimensions.height, forKey: .roomHeight)
        try container.encode(roomDimensions.depth, forKey: .roomDepth)
        try container.encode(boundary, forKey: .boundary)
        try container.encode(roomArea, forKey: .roomArea)
        try container.encode(roomName, forKey: .roomName)
        try container.encode(createdAt, forKey: .createdAt)
    }

    static func from(_ room: CapturedRoom) -> FloorPlanData {
        var elements: [FloorPlanElement] = []

        // Process walls
        for wall in room.walls {
            let element = FloorPlanElement(
                rect: rectFrom(surface: wall),
                rotation: rotationFrom(transform: wall.transform),
                type: .wall,
                label: nil
            )
            elements.append(element)
        }

        // Process doors
        for door in room.doors {
            let element = FloorPlanElement(
                rect: rectFrom(surface: door),
                rotation: rotationFrom(transform: door.transform),
                type: .door,
                label: nil
            )
            elements.append(element)
        }

        // Process windows
        for window in room.windows {
            let element = FloorPlanElement(
                rect: rectFrom(surface: window),
                rotation: rotationFrom(transform: window.transform),
                type: .window,
                label: nil
            )
            elements.append(element)
        }

        // Process openings
        for opening in room.openings {
            let element = FloorPlanElement(
                rect: rectFrom(surface: opening),
                rotation: rotationFrom(transform: opening.transform),
                type: .opening,
                label: nil
            )
            elements.append(element)
        }

        // Process objects
        for object in room.objects {
            let element = FloorPlanElement(
                rect: rectFrom(object: object),
                rotation: rotationFrom(transform: object.transform),
                type: .object(category: String(describing: object.category)),
                label: labelFor(category: object.category)
            )
            elements.append(element)
        }

        let boundingBox = calculateBoundingBox(elements: elements)
        let dimensions = RoomGeometry.getBoundingBox(from: room)
        let boundary = makeBoundary(from: room.walls)
        let area = polygonArea(boundary)
        let detectedType = RoomTypeDetector.detectRoomType(from: room).roomType
        let roomName = detectedType == .unknown ? "Room" : detectedType.rawValue

        return FloorPlanData(
            elements: elements,
            boundingBox: boundingBox,
            roomDimensions: dimensions,
            boundary: boundary,
            roomArea: area > 0 ? Float(area) : RoomGeometry.calculateApproximateFloorArea(from: room),
            roomName: roomName
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

    private static func calculateBoundingBox(elements: [FloorPlanElement]) -> CGRect {
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
        max(measuredThickness, 0.10)
    }

    private static func makeBoundary(from walls: [CapturedRoom.Surface]) -> [CGPoint] {
        var segments: [(CGPoint, CGPoint)] = walls.map { wall in
            let halfWidth = wall.dimensions.x / 2
            let left = wall.transform * SIMD4<Float>(-halfWidth, 0, 0, 1)
            let right = wall.transform * SIMD4<Float>(halfWidth, 0, 0, 1)
            return (
                CGPoint(x: CGFloat(left.x), y: CGFloat(left.z)),
                CGPoint(x: CGFloat(right.x), y: CGFloat(right.z))
            )
        }
        guard !segments.isEmpty else { return [] }

        let firstSegment = segments.removeFirst()
        var boundary = [firstSegment.0, firstSegment.1]

        while !segments.isEmpty {
            guard let current = boundary.last else { break }
            var bestIndex = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            var shouldReverse = false
            for (index, segment) in segments.enumerated() {
                let startDistance = hypot(segment.0.x - current.x, segment.0.y - current.y)
                let endDistance = hypot(segment.1.x - current.x, segment.1.y - current.y)
                if startDistance < bestDistance {
                    bestDistance = startDistance
                    bestIndex = index
                    shouldReverse = false
                }
                if endDistance < bestDistance {
                    bestDistance = endDistance
                    bestIndex = index
                    shouldReverse = true
                }
            }
            let segment = segments.remove(at: bestIndex)
            boundary.append(shouldReverse ? segment.0 : segment.1)
        }

        return removeNearDuplicates(boundary)
    }

    private static func removeNearDuplicates(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            guard let last = result.last else {
                result.append(point)
                continue
            }
            if hypot(point.x - last.x, point.y - last.y) > 0.05 {
                result.append(point)
            }
        }
        if result.count > 2, let first = result.first, let last = result.last,
           hypot(first.x - last.x, first.y - last.y) < 0.05 {
            result.removeLast()
        }
        return result
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

    // WiFi heatmap
    private var wifiSamples: [WiFiSample] = []

    var showDimensions: Bool = true {
        didSet { setNeedsDisplay() }
    }

    var showLabels: Bool = true {
        didSet { setNeedsDisplay() }
    }

    var showWifiHeatmap: Bool = true {
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

    func configure(with room: CapturedRoom, wifiSamples: [WiFiSample]) {
        floorPlanData = FloorPlanData.from(room)
        self.wifiSamples = wifiSamples
        calculateTransform()
        setNeedsDisplay()
    }

    func configure(with data: FloorPlanData, wifiSamples: [WiFiSample]) {
        floorPlanData = data
        self.wifiSamples = wifiSamples
        calculateTransform()
        setNeedsDisplay()
    }

    func setWifiSamples(_ samples: [WiFiSample]) {
        self.wifiSamples = samples
        setNeedsDisplay()
    }

    func clear() {
        floorPlanData = nil
        wifiSamples = []
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
            wifiSamples: wifiSamples,
            in: bounds,
            context: context,
            options: FloorPlanRenderOptions(
                showDimensions: showDimensions,
                showLabels: showLabels,
                showWiFi: showWifiHeatmap
            )
        )

        context.restoreGState()

        // Draw zoom/rotation indicator
        if zoomScale != 1.0 || rotationAngle != 0.0 {
            drawTransformIndicator(in: context)
        }
    }

    // MARK: - WiFi Heatmap Drawing

    private func drawWifiHeatmap(in context: CGContext) {
        guard !wifiSamples.isEmpty else { return }

        // Draw interpolated heatmap gradient
        drawInterpolatedHeatmap(in: context)

        // Draw sample point markers on top
        drawSampleMarkers(in: context)
    }

    private func drawInterpolatedHeatmap(in context: CGContext) {
        guard let floorPlanData = floorPlanData else { return }

        // Create a lower resolution grid for performance
        let gridSpacing: CGFloat = 20 // pixels
        let minX = floorPlanData.boundingBox.minX
        let minZ = floorPlanData.boundingBox.minY
        let maxX = floorPlanData.boundingBox.maxX
        let maxZ = floorPlanData.boundingBox.maxY

        // Transform to screen coordinates
        let screenMinPoint = transformPoint(x: Float(minX), z: Float(minZ))
        let screenMaxPoint = transformPoint(x: Float(maxX), z: Float(maxZ))

        // Calculate grid dimensions
        let width = abs(screenMaxPoint.x - screenMinPoint.x)
        let height = abs(screenMaxPoint.y - screenMinPoint.y)

        let cols = Int(width / gridSpacing) + 1
        let rows = Int(height / gridSpacing) + 1

        // Inverse Distance Weighting (IDW) interpolation
        let power: Float = 2.0 // IDW power parameter
        let radius: Float = 2.0 // meters - influence radius

        for row in 0..<rows {
            for col in 0..<cols {
                let screenX = min(screenMinPoint.x, screenMaxPoint.x) + CGFloat(col) * gridSpacing
                let screenY = min(screenMinPoint.y, screenMaxPoint.y) + CGFloat(row) * gridSpacing

                // Convert back to world coordinates
                let worldX = Float((screenX - offset.x) / (FloorPlanConfig.metersToPoints * scale))
                let worldZ = Float((screenY - offset.y) / (FloorPlanConfig.metersToPoints * scale))

                // Calculate interpolated signal strength
                var weightedSum: Float = 0
                var weightSum: Float = 0

                for sample in wifiSamples {
                    let dx = worldX - sample.position.x
                    let dz = worldZ - sample.position.z
                    let distance = sqrt(dx * dx + dz * dz)

                    // Skip if too far
                    if distance > radius { continue }

                    // Calculate weight (closer = more influence)
                    let weight = distance < 0.01 ? 1000.0 : 1.0 / pow(distance, power)

                    weightedSum += Float(sample.rssi) * weight
                    weightSum += weight
                }

                // Draw interpolated point if we have weights
                if weightSum > 0 {
                    let interpolatedRSSI = Int(weightedSum / weightSum)
                    let color = colorForSignal(rssi: interpolatedRSSI)

                    // Draw as semi-transparent square for smooth gradient
                    context.setFillColor(color.withAlphaComponent(0.3).cgColor)
                    context.fill(CGRect(
                        x: screenX,
                        y: screenY,
                        width: gridSpacing,
                        height: gridSpacing
                    ))
                }
            }
        }
    }

    private func drawSampleMarkers(in context: CGContext) {
        for sample in wifiSamples {
            let point = transformPoint(x: sample.position.x, z: sample.position.z)
            let color = colorForSignal(rssi: sample.rssi)
            let radius = FloorPlanConfig.wifiDotRadius * 0.5 // Smaller markers

            // Draw sample point marker
            context.saveGState()

            // White outline
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(
                x: point.x - radius * 1.2,
                y: point.y - radius * 1.2,
                width: radius * 2.4,
                height: radius * 2.4
            ))

            // Colored center
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))

            context.restoreGState()
        }
    }

    private func colorForSignal(rssi: Int) -> UIColor {
        switch rssi {
        case -50...0:
            return FloorPlanConfig.wifiExcellentColor
        case -60..<(-50):
            return FloorPlanConfig.wifiGoodColor
        case -70..<(-60):
            return FloorPlanConfig.wifiFairColor
        default:
            return FloorPlanConfig.wifiPoorColor
        }
    }

    private func transformPoint(x: Float, z: Float) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * FloorPlanConfig.metersToPoints * scale + offset.x,
            y: CGFloat(z) * FloorPlanConfig.metersToPoints * scale + offset.y
        )
    }

    private func drawWifiLegend(in context: CGContext) {
        let legendX: CGFloat = 16
        let legendY: CGFloat = bounds.height - 100
        let dotSize: CGFloat = 12
        let spacing: CGFloat = 20

        let items: [(String, UIColor)] = [
            ("Excellent", FloorPlanConfig.wifiExcellentColor),
            ("Good", FloorPlanConfig.wifiGoodColor),
            ("Fair", FloorPlanConfig.wifiFairColor),
            ("Poor", FloorPlanConfig.wifiPoorColor)
        ]

        // Background
        let bgRect = CGRect(x: legendX - 8, y: legendY - 8, width: 90, height: CGFloat(items.count) * spacing + 12)
        context.setFillColor(SpatialSenseTheme.Color.canvas.withAlphaComponent(0.92).cgColor)
        context.fill(bgRect)
        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(0.5)
        context.stroke(bgRect)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.label
        ]

        for (index, item) in items.enumerated() {
            let y = legendY + CGFloat(index) * spacing

            // Draw colored dot
            context.setFillColor(item.1.cgColor)
            context.fillEllipse(in: CGRect(x: legendX, y: y, width: dotSize, height: dotSize))

            // Draw label
            item.0.draw(at: CGPoint(x: legendX + dotSize + 6, y: y - 1), withAttributes: attributes)
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
