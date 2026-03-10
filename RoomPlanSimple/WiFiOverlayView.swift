/*
 WiFiOverlayView.swift
 RoomPlanSimple

 Overlay view that displays WiFi sample points and coverage visualization during scanning.
 Shows colored dots for WiFi samples and coverage markers to indicate where user has scanned.
*/

import UIKit
import simd

@MainActor
final class WiFiOverlayView: UIView {

    // MARK: - Configuration

    private let maxVisibleSamples = 20 // Node pooling limit
    private let sampleDotSize: CGFloat = 24
    private let coverageMarkerSize: CGFloat = 12
    private let fadeDistance: Float = 5.0 // meters - fade out beyond this

    // MARK: - Properties

    private var wifiSamples: [WiFiSampleDisplay] = []
    private var coveragePoints: [CoveragePoint] = []
    private var cameraPosition: SIMD3<Float> = .zero
    private var cameraForward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)

    // MARK: - Display Models

    struct WiFiSampleDisplay {
        let id: UUID
        let position: SIMD3<Float>
        let rssi: Int
        let timestamp: Date
        var screenPosition: CGPoint?

        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }
    }

    struct CoveragePoint {
        let position: SIMD3<Float>
        let timestamp: Date
        var screenPosition: CGPoint?
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    // MARK: - Public API

    /// Add a new WiFi sample to display
    func addWiFiSample(id: UUID, position: SIMD3<Float>, rssi: Int) {
        let sample = WiFiSampleDisplay(
            id: id,
            position: position,
            rssi: rssi,
            timestamp: Date(),
            screenPosition: nil
        )

        // Add to array
        wifiSamples.append(sample)

        // Enforce pooling limit - remove oldest
        if wifiSamples.count > maxVisibleSamples {
            wifiSamples.sort { $0.timestamp < $1.timestamp }
            wifiSamples.removeFirst()
        }

        setNeedsDisplay()
    }

    /// Add a coverage point marker
    func addCoveragePoint(position: SIMD3<Float>) {
        let point = CoveragePoint(
            position: position,
            timestamp: Date(),
            screenPosition: nil
        )
        coveragePoints.append(point)

        // Keep last 50 coverage points
        if coveragePoints.count > 50 {
            coveragePoints.removeFirst()
        }

        setNeedsDisplay()
    }

    /// Update camera position for proper projection
    func updateCameraTransform(position: SIMD3<Float>, forward: SIMD3<Float>) {
        cameraPosition = position
        cameraForward = normalize(forward)
        updateProjections()
        setNeedsDisplay()
    }

    /// Clear all visualizations
    func clear() {
        wifiSamples.removeAll()
        coveragePoints.removeAll()
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Draw coverage points (semi-transparent dots showing where scanned)
        drawCoveragePoints(in: context)

        // Draw WiFi samples (colored spheres)
        drawWiFiSamples(in: context)
    }

    private func drawCoveragePoints(in context: CGContext) {
        context.saveGState()

        for point in coveragePoints {
            guard let screenPos = point.screenPosition else { continue }

            // Check if on screen
            guard bounds.contains(screenPos) else { continue }

            // Age-based fade
            let age = Date().timeIntervalSince(point.timestamp)
            let alpha = max(0.1, 1.0 - CGFloat(age) / 30.0) // Fade over 30 seconds

            // Draw small blue dot
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(alpha * 0.4).cgColor)
            let rect = CGRect(
                x: screenPos.x - coverageMarkerSize / 2,
                y: screenPos.y - coverageMarkerSize / 2,
                width: coverageMarkerSize,
                height: coverageMarkerSize
            )
            context.fillEllipse(in: rect)
        }

        context.restoreGState()
    }

    private func drawWiFiSamples(in context: CGContext) {
        context.saveGState()

        for sample in wifiSamples {
            guard let screenPos = sample.screenPosition else { continue }

            // Check if on screen
            guard bounds.contains(screenPos) else { continue }

            // Distance-based fade
            let distance = simd_distance(sample.position, cameraPosition)
            let distanceFade = CGFloat(max(0.2, 1.0 - distance / fadeDistance))

            // Age-based fade (fade out old samples)
            let ageFade = max(0.3, 1.0 - CGFloat(sample.age) / 60.0) // Fade over 60 seconds

            let alpha = min(distanceFade, ageFade)

            // Get color based on signal strength
            let color = colorForSignal(rssi: sample.rssi)

            // Draw outer glow
            context.setFillColor(color.withAlphaComponent(alpha * 0.2).cgColor)
            let glowRect = CGRect(
                x: screenPos.x - sampleDotSize,
                y: screenPos.y - sampleDotSize,
                width: sampleDotSize * 2,
                height: sampleDotSize * 2
            )
            context.fillEllipse(in: glowRect)

            // Draw main dot
            context.setFillColor(color.withAlphaComponent(alpha * 0.8).cgColor)
            let mainRect = CGRect(
                x: screenPos.x - sampleDotSize / 2,
                y: screenPos.y - sampleDotSize / 2,
                width: sampleDotSize,
                height: sampleDotSize
            )
            context.fillEllipse(in: mainRect)

            // Draw white border
            context.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: mainRect)

            // Draw center highlight
            context.setFillColor(UIColor.white.withAlphaComponent(alpha * 0.5).cgColor)
            let highlightRect = CGRect(
                x: screenPos.x - sampleDotSize / 4,
                y: screenPos.y - sampleDotSize / 4,
                width: sampleDotSize / 2,
                height: sampleDotSize / 2
            )
            context.fillEllipse(in: highlightRect)
        }

        context.restoreGState()
    }

    // MARK: - Projection

    private func updateProjections() {
        // Simple 3D to 2D projection
        // This is a simplified projection - assumes camera looking down negative Z

        for i in 0..<wifiSamples.count {
            wifiSamples[i].screenPosition = projectToScreen(wifiSamples[i].position)
        }

        for i in 0..<coveragePoints.count {
            coveragePoints[i].screenPosition = projectToScreen(coveragePoints[i].position)
        }
    }

    private func projectToScreen(_ worldPos: SIMD3<Float>) -> CGPoint {
        // Relative position to camera
        let relative = worldPos - cameraPosition

        // Simple perspective projection
        // Assuming vertical FOV of ~60 degrees
        let fov: Float = 60.0 * .pi / 180.0
        let aspectRatio = Float(bounds.width / bounds.height)

        // Project to normalized device coordinates
        let z = max(relative.z, 0.1) // Prevent division by zero
        let tanHalfFov = tan(fov / 2.0)

        // Perspective divide
        let ndcX = relative.x / (z * tanHalfFov * aspectRatio)
        let ndcY = -relative.y / (z * tanHalfFov) // Flip Y for screen coordinates

        // Convert to screen space
        let screenX = (ndcX + 1.0) * Float(bounds.width) / 2.0
        let screenY = (ndcY + 1.0) * Float(bounds.height) / 2.0

        return CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
    }

    // MARK: - Helpers

    private func colorForSignal(rssi: Int) -> UIColor {
        // Map RSSI (-30 excellent to -90 poor) to color
        let normalizedSignal = (Double(rssi) + 90) / 60.0

        if normalizedSignal > 0.75 {
            return UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0) // Green
        } else if normalizedSignal > 0.5 {
            return UIColor(red: 0.5, green: 1.0, blue: 0.0, alpha: 1.0) // Yellow-green
        } else if normalizedSignal > 0.25 {
            return UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // Yellow
        } else {
            return UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Red
        }
    }
}
