/*
See LICENSE folder for this sample's licensing information.

Abstract:
Subtle construction sketch grid for library and plan surfaces
(Tailwind / Polycam-inspired motif: quiet lines + faint marks).
*/

import UIKit

final class BlueprintBackgroundView: UIView {

    enum Variant {
        case darkStudio
        case planPaper
    }

    var variant: Variant = .darkStudio {
        didSet { setNeedsDisplay() }
    }

    /// Grid spacing in points.
    var gridSpacing: CGFloat = 32 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let lineColor: UIColor
        let majorColor: UIColor
        let watermarkColor: UIColor
        let accentColor: UIColor

        switch variant {
        case .darkStudio:
            lineColor = UIColor.white.withAlphaComponent(0.028)
            majorColor = UIColor.white.withAlphaComponent(0.048)
            watermarkColor = UIColor.white.withAlphaComponent(0.04)
            accentColor = SpatialSenseTheme.Color.primary.withAlphaComponent(0.08)
        case .planPaper:
            lineColor = FloorPlanStyle.gridLine
            majorColor = FloorPlanStyle.gridLineMajor
            watermarkColor = FloorPlanStyle.gridLine.withAlphaComponent(0.35)
            accentColor = SpatialSenseTheme.Color.primary.withAlphaComponent(0.06)
        }

        context.setLineWidth(0.5)
        var x: CGFloat = 0
        var column = 0
        while x <= rect.maxX {
            context.setStrokeColor((column % 4 == 0 ? majorColor : lineColor).cgColor)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.strokePath()
            x += gridSpacing
            column += 1
        }

        var y: CGFloat = 0
        var row = 0
        while y <= rect.maxY {
            context.setStrokeColor((row % 4 == 0 ? majorColor : lineColor).cgColor)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
            y += gridSpacing
            row += 1
        }

        drawSketchMarks(in: rect, color: watermarkColor, accent: accentColor)
    }

    private func drawSketchMarks(in rect: CGRect, color: UIColor, accent: UIColor) {
        let samples = ["1:50", "N", "3.20 m"]
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let anchors: [(CGPoint, CGFloat)] = [
            (CGPoint(x: rect.maxX - 64, y: rect.minY + 72), 0),
            (CGPoint(x: rect.minX + 28, y: rect.maxY - 72), -.pi / 2),
            (CGPoint(x: rect.maxX - 80, y: rect.maxY - 48), 0)
        ]

        for (index, anchor) in anchors.enumerated() where index < samples.count {
            let text = samples[index]
            let size = text.size(withAttributes: attributes)
            guard let context = UIGraphicsGetCurrentContext() else { continue }
            context.saveGState()
            context.translateBy(x: anchor.0.x, y: anchor.0.y)
            context.rotate(by: anchor.1)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attributes)
            context.restoreGState()
        }

        // Quiet diagonal construction tick in the corner (not a busy pattern).
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1)
        let origin = CGPoint(x: rect.minX + 18, y: rect.minY + 96)
        context.move(to: origin)
        context.addLine(to: CGPoint(x: origin.x + 28, y: origin.y))
        context.move(to: origin)
        context.addLine(to: CGPoint(x: origin.x, y: origin.y + 28))
        context.strokePath()
    }
}
