/*
See LICENSE folder for this sample's licensing information.

Abstract:
Renders a professional, print-style single-room floor-plan document.
*/

import UIKit

struct FloorPlanRenderOptions {
    var showDimensions = true
    var showLabels = true
    var showWiFi = false
    var title = "SpatialSense Floor Plan"
}

enum FloorPlanDocumentRenderer {
    private struct Layout {
        let scale: CGFloat
        let offset: CGPoint
        let planRect: CGRect

        func point(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x * scale + offset.x,
                y: point.y * scale + offset.y
            )
        }

        func rect(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX * scale + offset.x,
                y: rect.minY * scale + offset.y,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }
    }

    static func image(
        data: FloorPlanData,
        size: CGSize,
        wifiSamples: [WiFiSample] = [],
        options: FloorPlanRenderOptions = FloorPlanRenderOptions()
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            draw(
                data: data,
                wifiSamples: wifiSamples,
                in: CGRect(origin: .zero, size: size),
                context: rendererContext.cgContext,
                options: options
            )
        }
    }

    static func draw(
        data: FloorPlanData,
        wifiSamples: [WiFiSample] = [],
        in bounds: CGRect,
        context: CGContext,
        options: FloorPlanRenderOptions
    ) {
        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds)

        drawHeader(data: data, bounds: bounds, context: context, title: options.title)
        drawFooter(bounds: bounds, context: context)

        let layout = makeLayout(data: data, bounds: bounds)
        drawRoomFill(data: data, layout: layout, context: context)
        if options.showWiFi {
            drawWiFi(wifiSamples, layout: layout, context: context)
        }

        let walls = elements(data, matching: .wall)
        let openings = elements(data, matching: .opening)
        let doors = elements(data, matching: .door)
        let windows = elements(data, matching: .window)
        let objects = data.elements.filter {
            if case .object = $0.type { return true }
            return false
        }

        walls.forEach { drawWall($0, layout: layout, context: context) }
        openings.forEach { drawOpening($0, layout: layout, context: context) }
        doors.forEach { drawDoor($0, layout: layout, context: context) }
        windows.forEach { drawWindow($0, layout: layout, context: context) }
        objects.forEach {
            drawObject($0, layout: layout, context: context, showLabel: options.showLabels)
        }

        if options.showLabels {
            drawRoomLabel(data: data, layout: layout, context: context)
        }
        if options.showDimensions {
            drawWallDimensions(walls, data: data, layout: layout, context: context)
            drawOverallDimensions(data: data, layout: layout, context: context)
        }
        drawOrientationMarker(bounds: bounds, context: context)
        drawScaleBar(layout: layout, bounds: bounds, context: context)
        context.restoreGState()
    }

    private static func makeLayout(data: FloorPlanData, bounds: CGRect) -> Layout {
        let horizontalMargin = max(42, bounds.width * 0.075)
        let headerHeight = max(72, bounds.height * 0.09)
        let footerHeight = max(58, bounds.height * 0.07)
        let annotationMargin = max(48, min(bounds.width, bounds.height) * 0.08)
        let planRect = CGRect(
            x: horizontalMargin + annotationMargin,
            y: headerHeight + annotationMargin,
            width: bounds.width - (horizontalMargin + annotationMargin) * 2,
            height: bounds.height - headerHeight - footerHeight - annotationMargin * 2
        )
        let width = max(data.boundingBox.width, 0.1)
        let height = max(data.boundingBox.height, 0.1)
        let scale = min(planRect.width / width, planRect.height / height)
        let renderedWidth = width * scale
        let renderedHeight = height * scale
        let offset = CGPoint(
            x: planRect.midX - renderedWidth / 2 - data.boundingBox.minX * scale,
            y: planRect.midY - renderedHeight / 2 - data.boundingBox.minY * scale
        )
        return Layout(scale: scale, offset: offset, planRect: planRect)
    }

    private static func drawHeader(
        data: FloorPlanData,
        bounds: CGRect,
        context: CGContext,
        title: String
    ) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(18, bounds.width * 0.025), weight: .semibold),
            .foregroundColor: UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1)
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(9, bounds.width * 0.011), weight: .regular),
            .foregroundColor: UIColor(white: 0.35, alpha: 1)
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        title.draw(
            at: CGPoint(x: bounds.midX - titleSize.width / 2, y: 18),
            withAttributes: titleAttributes
        )
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let subtitle = "\(data.roomName) · \(formatter.string(from: data.createdAt))"
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        subtitle.draw(
            at: CGPoint(x: bounds.midX - subtitleSize.width / 2, y: 24 + titleSize.height),
            withAttributes: subtitleAttributes
        )
    }

    private static func drawFooter(bounds: CGRect, context: CGContext) {
        let text = "SPATIALSENSE"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(10, bounds.width * 0.012), weight: .bold),
            .foregroundColor: SpatialSenseTheme.Color.primary
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - 18),
            withAttributes: attributes
        )
    }

    private static func drawRoomFill(data: FloorPlanData, layout: Layout, context: CGContext) {
        guard data.boundary.count >= 3 else { return }
        let path = CGMutablePath()
        path.move(to: layout.point(data.boundary[0]))
        data.boundary.dropFirst().forEach { path.addLine(to: layout.point($0)) }
        path.closeSubpath()
        context.setFillColor(UIColor(red: 0.965, green: 0.972, blue: 0.985, alpha: 1).cgColor)
        context.addPath(path)
        context.fillPath()
    }

    private static func drawWall(_ element: FloorPlanElement, layout: Layout, context: CGContext) {
        withElementTransform(element, layout: layout, context: context) { rect in
            context.setFillColor(UIColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1).cgColor)
            context.fill(rect)
        }
    }

    private static func drawOpening(_ element: FloorPlanElement, layout: Layout, context: CGContext) {
        withElementTransform(element, layout: layout, context: context) { rect in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect.insetBy(dx: -1, dy: -2))
            context.setStrokeColor(UIColor(white: 0.68, alpha: 1).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(rect)
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    private static func drawDoor(_ element: FloorPlanElement, layout: Layout, context: CGContext) {
        withElementTransform(element, layout: layout, context: context) { rect in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect.insetBy(dx: -1, dy: -3))
            let radius = rect.width
            let hinge = CGPoint(x: rect.minX, y: rect.midY)
            context.setStrokeColor(UIColor(white: 0.34, alpha: 1).cgColor)
            context.setLineWidth(1.2)
            context.move(to: hinge)
            context.addLine(to: CGPoint(x: rect.minX, y: rect.midY - radius))
            context.strokePath()
            context.addArc(
                center: hinge,
                radius: radius,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: false
            )
            context.strokePath()
        }
    }

    private static func drawWindow(_ element: FloorPlanElement, layout: Layout, context: CGContext) {
        withElementTransform(element, layout: layout, context: context) { rect in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect.insetBy(dx: -1, dy: -3))
            context.setStrokeColor(SpatialSenseTheme.Color.primary.cgColor)
            context.setLineWidth(1.5)
            let y1 = rect.midY - 2
            let y2 = rect.midY + 2
            context.move(to: CGPoint(x: rect.minX, y: y1))
            context.addLine(to: CGPoint(x: rect.maxX, y: y1))
            context.move(to: CGPoint(x: rect.minX, y: y2))
            context.addLine(to: CGPoint(x: rect.maxX, y: y2))
            context.strokePath()
        }
    }

    private static func drawObject(
        _ element: FloorPlanElement,
        layout: Layout,
        context: CGContext,
        showLabel: Bool
    ) {
        withElementTransform(element, layout: layout, context: context) { rect in
            let category: String
            if case .object(let value) = element.type { category = value.lowercased() } else { return }
            context.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
            context.setStrokeColor(UIColor(white: 0.66, alpha: 1).cgColor)
            context.setLineWidth(0.9)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: min(4, rect.height * 0.08))
            context.addPath(path.cgPath)
            context.drawPath(using: .fillStroke)
            drawFurnitureSymbol(category: category, rect: rect, context: context)

            if showLabel, let label = element.label, rect.width > 40, rect.height > 24 {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: max(7, min(11, rect.width / 8)), weight: .regular),
                    .foregroundColor: UIColor(white: 0.38, alpha: 1)
                ]
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 3),
                    withAttributes: attributes
                )
            }
        }
    }

    private static func drawFurnitureSymbol(
        category: String,
        rect: CGRect,
        context: CGContext
    ) {
        context.setStrokeColor(UIColor(white: 0.72, alpha: 1).cgColor)
        context.setLineWidth(0.8)
        if category.contains("bed") {
            let pillowHeight = min(rect.height * 0.22, 18)
            context.stroke(rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.06))
            context.stroke(CGRect(
                x: rect.minX + rect.width * 0.12,
                y: rect.minY + rect.height * 0.10,
                width: rect.width * 0.32,
                height: pillowHeight
            ))
            context.stroke(CGRect(
                x: rect.midX + rect.width * 0.06,
                y: rect.minY + rect.height * 0.10,
                width: rect.width * 0.32,
                height: pillowHeight
            ))
        } else if category.contains("table") {
            context.strokeEllipse(in: rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16))
        } else if category.contains("sofa") {
            context.stroke(rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.18))
            context.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18))
            context.strokePath()
        } else if category.contains("toilet") {
            context.strokeEllipse(in: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.15))
        } else if category.contains("bathtub") {
            let inset = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.10)
            context.strokeEllipse(in: inset)
        } else {
            context.stroke(rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14))
        }
    }

    private static func drawRoomLabel(data: FloorPlanData, layout: Layout, context: CGContext) {
        let center = layout.point(CGPoint(x: data.boundingBox.midX, y: data.boundingBox.midY))
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
        ]
        let areaAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor(white: 0.38, alpha: 1)
        ]
        let nameSize = data.roomName.size(withAttributes: nameAttributes)
        data.roomName.draw(
            at: CGPoint(x: center.x - nameSize.width / 2, y: center.y - nameSize.height),
            withAttributes: nameAttributes
        )
        let areaText = String(format: "%.1f m²", data.roomArea)
        let areaSize = areaText.size(withAttributes: areaAttributes)
        areaText.draw(
            at: CGPoint(x: center.x - areaSize.width / 2, y: center.y + 2),
            withAttributes: areaAttributes
        )
    }

    private static func drawWallDimensions(
        _ walls: [FloorPlanElement],
        data: FloorPlanData,
        layout: Layout,
        context: CGContext
    ) {
        let roomCenter = CGPoint(x: data.boundingBox.midX, y: data.boundingBox.midY)
        for wall in walls {
            let center = CGPoint(x: wall.rect.midX, y: wall.rect.midY)
            let half = wall.rect.width / 2
            let axis = CGPoint(x: cos(wall.rotation), y: sin(wall.rotation))
            let start = CGPoint(x: center.x - axis.x * half, y: center.y - axis.y * half)
            let end = CGPoint(x: center.x + axis.x * half, y: center.y + axis.y * half)
            var normal = CGPoint(x: -axis.y, y: axis.x)
            let outward = CGPoint(x: center.x - roomCenter.x, y: center.y - roomCenter.y)
            if normal.x * outward.x + normal.y * outward.y < 0 {
                normal.x *= -1
                normal.y *= -1
            }
            let offset = 16 / layout.scale
            let a = layout.point(CGPoint(x: start.x + normal.x * offset, y: start.y + normal.y * offset))
            let b = layout.point(CGPoint(x: end.x + normal.x * offset, y: end.y + normal.y * offset))
            drawDimensionLine(from: a, to: b, text: String(format: "%.2f m", wall.rect.width), context: context)
        }
    }

    private static func drawOverallDimensions(
        data: FloorPlanData,
        layout: Layout,
        context: CGContext
    ) {
        let min = layout.point(CGPoint(x: data.boundingBox.minX, y: data.boundingBox.maxY))
        let max = layout.point(CGPoint(x: data.boundingBox.maxX, y: data.boundingBox.maxY))
        drawDimensionLine(
            from: CGPoint(x: min.x, y: min.y + 34),
            to: CGPoint(x: max.x, y: max.y + 34),
            text: String(format: "%.2f m", data.boundingBox.width),
            context: context
        )
        let top = layout.point(CGPoint(x: data.boundingBox.maxX, y: data.boundingBox.minY))
        let bottom = layout.point(CGPoint(x: data.boundingBox.maxX, y: data.boundingBox.maxY))
        drawDimensionLine(
            from: CGPoint(x: top.x + 34, y: top.y),
            to: CGPoint(x: bottom.x + 34, y: bottom.y),
            text: String(format: "%.2f m", data.boundingBox.height),
            context: context
        )
    }

    private static func drawDimensionLine(
        from start: CGPoint,
        to end: CGPoint,
        text: String,
        context: CGContext
    ) {
        context.setStrokeColor(UIColor(white: 0.48, alpha: 1).cgColor)
        context.setLineWidth(0.7)
        context.move(to: start)
        context.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let normal = CGPoint(x: -sin(angle) * 4, y: cos(angle) * 4)
        for point in [start, end] {
            context.move(to: CGPoint(x: point.x - normal.x, y: point.y - normal.y))
            context.addLine(to: CGPoint(x: point.x + normal.x, y: point.y + normal.y))
        }
        context.strokePath()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor(white: 0.42, alpha: 1),
            .backgroundColor: UIColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        context.saveGState()
        context.translateBy(x: midpoint.x, y: midpoint.y)
        var textAngle = angle
        if textAngle > .pi / 2 || textAngle < -.pi / 2 { textAngle += .pi }
        context.rotate(by: textAngle)
        text.draw(at: CGPoint(x: -size.width / 2, y: -size.height - 2), withAttributes: attributes)
        context.restoreGState()
    }

    private static func drawOrientationMarker(bounds: CGRect, context: CGContext) {
        let center = CGPoint(x: bounds.maxX - 52, y: 48)
        context.setStrokeColor(UIColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1).cgColor)
        context.setFillColor(UIColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1).cgColor)
        context.setLineWidth(1.2)
        context.move(to: CGPoint(x: center.x, y: center.y + 15))
        context.addLine(to: CGPoint(x: center.x, y: center.y - 14))
        context.strokePath()
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: center.x, y: center.y - 18))
        arrow.addLine(to: CGPoint(x: center.x - 5, y: center.y - 8))
        arrow.addLine(to: CGPoint(x: center.x + 5, y: center.y - 8))
        arrow.close()
        context.addPath(arrow.cgPath)
        context.fillPath()
        "N".draw(
            at: CGPoint(x: center.x - 4, y: center.y + 16),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1)
            ]
        )
    }

    private static func drawScaleBar(layout: Layout, bounds: CGRect, context: CGContext) {
        let length = layout.scale
        let start = CGPoint(x: 36, y: bounds.maxY - 36)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(2)
        context.move(to: start)
        context.addLine(to: CGPoint(x: start.x + length, y: start.y))
        context.strokePath()
        "1 m".draw(
            at: CGPoint(x: start.x, y: start.y + 4),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.black
            ]
        )
    }

    private static func drawWiFi(
        _ samples: [WiFiSample],
        layout: Layout,
        context: CGContext
    ) {
        for sample in samples {
            let point = layout.point(CGPoint(
                x: CGFloat(sample.position.x),
                y: CGFloat(sample.position.z)
            ))
            let color: UIColor
            switch sample.rssi {
            case -50...0: color = .systemGreen
            case -60..<(-50): color = .systemYellow
            case -70..<(-60): color = .systemOrange
            default: color = .systemRed
            }
            context.setFillColor(color.withAlphaComponent(0.28).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        }
    }

    private static func withElementTransform(
        _ element: FloorPlanElement,
        layout: Layout,
        context: CGContext,
        draw: (CGRect) -> Void
    ) {
        let rect = layout.rect(element.rect)
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: element.rotation)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        draw(rect)
        context.restoreGState()
    }

    private static func elements(
        _ data: FloorPlanData,
        matching type: FloorPlanElement.ElementType
    ) -> [FloorPlanElement] {
        data.elements.filter { element in
            switch (element.type, type) {
            case (.wall, .wall), (.door, .door), (.window, .window), (.opening, .opening):
                return true
            default:
                return false
            }
        }
    }
}
