/*
See LICENSE folder for this sample's licensing information.

Abstract:
Projects ARKit mesh vertices into camera frames and accumulates true RGB colors.
*/

import UIKit
import ARKit

final class PointCloudColorSampler {
    private struct SpatialKey: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    private struct Observation {
        let position: SIMD3<Float>
        let color: PointCloudExporter.RGBColor
        let score: Float
    }

    private static let spatialCellSize: Float = 0.025
    private static let maximumMatchDistanceSquared: Float = 0.000576

    private let processingQueue = DispatchQueue(
        label: "com.spatialsense.pointcloud.colors",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var observations: [SpatialKey: Observation] = [:]
    private var isProcessing = false

    func sample(
        frame: ARFrame,
        anchors: [ARMeshAnchor],
        orientation: UIInterfaceOrientation,
        viewportSize: CGSize
    ) {
        lock.lock()
        guard !isProcessing else {
            lock.unlock()
            return
        }
        isProcessing = true
        lock.unlock()

        processingQueue.async { [self] in
            observations.reserveCapacity(
                max(observations.count, anchors.reduce(0) { $0 + $1.geometry.vertices.count })
            )
            let pixelBuffer = frame.capturedImage
            let depthBuffer = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            if let depthBuffer {
                CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
            }
            defer {
                if let depthBuffer {
                    CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                self.lock.lock()
                self.isProcessing = false
                self.lock.unlock()
            }

            let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
            let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
            guard imageWidth > 0, imageHeight > 0,
                  viewportSize.width > 0, viewportSize.height > 0 else {
                return
            }

            let inverseDisplayTransform = frame
                .displayTransform(for: orientation, viewportSize: viewportSize)
                .inverted()
            let cameraFromWorld = frame.camera.transform.inverse

            for anchor in anchors {
                let vertices = anchor.geometry.vertices
                let bufferStart = vertices.buffer.contents().advanced(by: vertices.offset)

                for index in 0..<vertices.count {
                    let pointer = bufferStart
                        .advanced(by: index * vertices.stride)
                        .assumingMemoryBound(to: Float.self)
                    let localPosition = SIMD3<Float>(pointer[0], pointer[1], pointer[2])
                    let local = SIMD4<Float>(localPosition, 1)
                    let world = anchor.transform * local
                    let worldPosition = SIMD3<Float>(world.x, world.y, world.z)
                    let cameraPoint = cameraFromWorld * world

                    if cameraPoint.z < -0.05 {
                        let projected = frame.camera.projectPoint(
                            worldPosition,
                            orientation: orientation,
                            viewportSize: viewportSize
                        )
                        if projected.x.isFinite, projected.y.isFinite,
                           projected.x >= 0, projected.y >= 0,
                           projected.x < viewportSize.width,
                           projected.y < viewportSize.height {
                            let viewNormalized = CGPoint(
                                x: projected.x / viewportSize.width,
                                y: projected.y / viewportSize.height
                            )
                            let imageNormalized = viewNormalized.applying(inverseDisplayTransform)
                            if imageNormalized.x >= 0, imageNormalized.y >= 0,
                               imageNormalized.x < 1, imageNormalized.y < 1,
                               Self.isVisible(
                                   cameraDepth: -cameraPoint.z,
                                   imageNormalized: imageNormalized,
                                   depthBuffer: depthBuffer
                               ) {
                                let pixelX = Int(imageNormalized.x * CGFloat(imageWidth))
                                let pixelY = Int(imageNormalized.y * CGFloat(imageHeight))
                                if let color = Self.sampleRGB(
                                    from: pixelBuffer,
                                    x: pixelX,
                                    y: pixelY
                                ) {
                                    let cameraPosition = SIMD3<Float>(
                                        cameraPoint.x,
                                        cameraPoint.y,
                                        cameraPoint.z
                                    )
                                    let candidate = Observation(
                                        position: worldPosition,
                                        color: color,
                                        score: 1 / max(simd_length(cameraPosition), 0.05)
                                    )
                                    let key = Self.spatialKey(for: worldPosition)
                                    if candidate.score > (observations[key]?.score ?? 0) {
                                        observations[key] = candidate
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Waits for the current camera frame to finish and spatially maps retained
    /// observations onto the latest mesh topology.
    func snapshot(alignedTo anchors: [ARMeshAnchor]) -> [UUID: [PointCloudExporter.RGBColor]] {
        let storedObservations = processingQueue.sync { observations }

        var result: [UUID: [PointCloudExporter.RGBColor]] = [:]
        result.reserveCapacity(anchors.count)
        for anchor in anchors {
            let vertices = anchor.geometry.vertices
            let bufferStart = vertices.buffer.contents().advanced(by: vertices.offset)
            var alignedColors = Array(repeating: PointCloudExporter.RGBColor.fallback, count: vertices.count)

            for index in 0..<vertices.count {
                let pointer = bufferStart
                    .advanced(by: index * vertices.stride)
                    .assumingMemoryBound(to: Float.self)
                let localPosition = SIMD4<Float>(pointer[0], pointer[1], pointer[2], 1)
                let transformed = anchor.transform * localPosition
                let currentPosition = SIMD3<Float>(transformed.x, transformed.y, transformed.z)
                if let observation = Self.nearestObservation(
                    to: currentPosition,
                    in: storedObservations
                ) {
                    alignedColors[index] = observation.color
                }
            }
            result[anchor.identifier] = alignedColors
        }
        return result
    }

    func reset() {
        processingQueue.sync {
            observations.removeAll()
        }
    }

    static func yCbCrToRGB(
        y: UInt8,
        cb: UInt8,
        cr: UInt8,
        fullRange: Bool = true
    ) -> PointCloudExporter.RGBColor {
        let normalizedY = fullRange ? Float(y) : 1.164 * (Float(y) - 16)
        let normalizedCb = Float(cb) - 128
        let normalizedCr = Float(cr) - 128
        return PointCloudExporter.RGBColor(
            red: clamp(normalizedY + (fullRange ? 1.5748 : 1.793) * normalizedCr),
            green: clamp(
                normalizedY -
                    (fullRange ? 0.1873 : 0.213) * normalizedCb -
                    (fullRange ? 0.4681 : 0.533) * normalizedCr
            ),
            blue: clamp(normalizedY + (fullRange ? 1.8556 : 2.112) * normalizedCb)
        )
    }

    private static func sampleRGB(
        from pixelBuffer: CVPixelBuffer,
        x: Int,
        y: Int
    ) -> PointCloudExporter.RGBColor? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }

        if CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
           let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
           let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let yValue = yBase.assumingMemoryBound(to: UInt8.self)[y * yStride + x]
            let chromaOffset = (y / 2) * chromaStride + (x / 2) * 2
            let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
            let isFullRange = CVPixelBufferGetPixelFormatType(pixelBuffer) ==
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            return yCbCrToRGB(
                y: yValue,
                cb: chroma[chromaOffset],
                cr: chroma[chromaOffset + 1],
                fullRange: isFullRange
            )
        }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixel = base.assumingMemoryBound(to: UInt8.self).advanced(by: y * stride + x * 4)
        return PointCloudExporter.RGBColor(red: pixel[2], green: pixel[1], blue: pixel[0])
    }

    private static func clamp(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, Int(value.rounded()))))
    }

    private static func spatialKey(for position: SIMD3<Float>) -> SpatialKey {
        SpatialKey(
            x: Int(floor(position.x / spatialCellSize)),
            y: Int(floor(position.y / spatialCellSize)),
            z: Int(floor(position.z / spatialCellSize))
        )
    }

    private static func nearestObservation(
        to position: SIMD3<Float>,
        in observations: [SpatialKey: Observation]
    ) -> Observation? {
        let center = spatialKey(for: position)
        var nearest: Observation?
        var nearestDistanceSquared = maximumMatchDistanceSquared

        for xOffset in -1...1 {
            for yOffset in -1...1 {
                for zOffset in -1...1 {
                    let key = SpatialKey(
                        x: center.x + xOffset,
                        y: center.y + yOffset,
                        z: center.z + zOffset
                    )
                    guard let candidate = observations[key] else { continue }
                    let distanceSquared = simd_distance_squared(candidate.position, position)
                    if distanceSquared <= nearestDistanceSquared {
                        nearest = candidate
                        nearestDistanceSquared = distanceSquared
                    }
                }
            }
        }
        return nearest
    }

    private static func isVisible(
        cameraDepth: Float,
        imageNormalized: CGPoint,
        depthBuffer: CVPixelBuffer?
    ) -> Bool {
        guard let depthBuffer,
              CVPixelBufferGetPixelFormatType(depthBuffer) == kCVPixelFormatType_DepthFloat32,
              let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return true
        }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard width > 0, height > 0 else { return true }
        let x = min(max(Int(imageNormalized.x * CGFloat(width)), 0), width - 1)
        let y = min(max(Int(imageNormalized.y * CGFloat(height)), 0), height - 1)
        let stride = CVPixelBufferGetBytesPerRow(depthBuffer) / MemoryLayout<Float32>.size
        let measuredDepth = baseAddress.assumingMemoryBound(to: Float32.self)[y * stride + x]
        guard measuredDepth.isFinite, measuredDepth > 0 else { return true }

        let tolerance = max(0.12, cameraDepth * 0.06)
        return cameraDepth <= measuredDepth + tolerance
    }
}
