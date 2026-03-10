/*
 RFPropagationModel.swift
 RoomPlanSimple

 RF Propagation model for predicting WiFi signal strength based on distance and obstacles.
 Uses path loss equations and material attenuation to estimate coverage.
*/

import Foundation
import RoomPlan
import simd

/// RF Propagation model for WiFi signal prediction
@MainActor
final class RFPropagationModel {

    // MARK: - Configuration

    /// WiFi frequency band
    enum FrequencyBand {
        case band2_4GHz
        case band5GHz
        case band6GHz

        var frequencyMHz: Double {
            switch self {
            case .band2_4GHz: return 2400.0
            case .band5GHz: return 5000.0
            case .band6GHz: return 6000.0
            }
        }

        var freeSpacePathLossExponent: Double {
            2.0 // Free space path loss exponent
        }
    }

    /// Material attenuation values (dB loss per meter)
    enum WallMaterial {
        case drywall      // 3-5 dB
        case wood         // 4-6 dB
        case brick        // 6-10 dB
        case concrete     // 10-15 dB
        case metal        // 20-30 dB

        var attenuationDB: Double {
            switch self {
            case .drywall: return 4.0
            case .wood: return 5.0
            case .brick: return 8.0
            case .concrete: return 12.0
            case .metal: return 25.0
            }
        }
    }

    // MARK: - Properties

    private let frequencyBand: FrequencyBand
    private let transmitPower: Double // dBm
    private let defaultWallMaterial: WallMaterial

    // MARK: - Initialization

    init(
        frequencyBand: FrequencyBand = .band5GHz,
        transmitPower: Double = 20.0, // Typical router TX power
        defaultWallMaterial: WallMaterial = .drywall
    ) {
        self.frequencyBand = frequencyBand
        self.transmitPower = transmitPower
        self.defaultWallMaterial = defaultWallMaterial
    }

    // MARK: - Public API

    /// Predict signal strength at a given position
    func predictSignalStrength(
        routerPosition: SIMD3<Float>,
        targetPosition: SIMD3<Float>,
        walls: [Wall] = []
    ) -> Int {
        // Calculate distance
        let distance = simd_distance(routerPosition, targetPosition)

        // Free space path loss
        let pathLoss = calculateFreeSpacePathLoss(distance: Double(distance))

        // Wall penetration loss
        let wallLoss = calculateWallLoss(
            from: routerPosition,
            to: targetPosition,
            walls: walls
        )

        // Indoor environmental loss (furniture, reflections, etc)
        let environmentalLoss = 5.0 // dB

        // Calculate received signal strength
        let rssi = transmitPower - pathLoss - wallLoss - environmentalLoss

        return Int(rssi.rounded())
    }

    /// Generate a coverage map for the given room
    func generateCoverageMap(
        routerPosition: SIMD3<Float>,
        floorPlanData: FloorPlanData,
        gridResolution: Float = 0.5 // meters
    ) -> [CoveragePoint] {
        var coveragePoints: [CoveragePoint] = []

        // Extract walls
        let walls = floorPlanData.elements.compactMap { element -> Wall? in
            guard case .wall = element.type else { return nil }
            return Wall(
                start: SIMD3<Float>(
                    Float(element.rect.minX),
                    Float(element.rect.midY),
                    Float(element.rect.minY)
                ),
                end: SIMD3<Float>(
                    Float(element.rect.maxX),
                    Float(element.rect.midY),
                    Float(element.rect.maxY)
                ),
                thickness: 0.1
            )
        }

        // Generate grid
        let minX = floorPlanData.boundingBox.minX
        let minZ = floorPlanData.boundingBox.minY
        let maxX = floorPlanData.boundingBox.maxX
        let maxZ = floorPlanData.boundingBox.maxY

        var x = minX
        while x <= maxX {
            var z = minZ
            while z <= maxZ {
                let position = SIMD3<Float>(Float(x), routerPosition.y, Float(z))
                let rssi = predictSignalStrength(
                    routerPosition: routerPosition,
                    targetPosition: position,
                    walls: walls
                )

                coveragePoints.append(CoveragePoint(
                    position: position,
                    rssi: rssi
                ))

                z += CGFloat(gridResolution)
            }
            x += CGFloat(gridResolution)
        }

        return coveragePoints
    }

    // MARK: - Path Loss Calculations

    private func calculateFreeSpacePathLoss(distance: Double) -> Double {
        // Friis transmission equation: FSPL = 20*log10(d) + 20*log10(f) + 20*log10(4π/c)
        // Simplified: FSPL(dB) = 20*log10(d) + 20*log10(f) - 27.55

        guard distance > 0 else { return 0 }

        let distanceMeters = max(distance, 1.0) // Minimum 1 meter
        let frequencyMHz = frequencyBand.frequencyMHz

        let fspl = 20 * log10(distanceMeters) + 20 * log10(frequencyMHz) - 27.55

        return fspl
    }

    private func calculateWallLoss(
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        walls: [Wall]
    ) -> Double {
        var totalLoss: Double = 0

        // Count walls intersected by ray
        for wall in walls {
            if lineSegmentIntersectsWall(from: from, to: to, wall: wall) {
                totalLoss += defaultWallMaterial.attenuationDB
            }
        }

        return totalLoss
    }

    private func lineSegmentIntersectsWall(
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        wall: Wall
    ) -> Bool {
        // Simplified 2D line-segment intersection (ignoring Y axis)
        let p1 = SIMD2<Float>(from.x, from.z)
        let p2 = SIMD2<Float>(to.x, to.z)
        let p3 = SIMD2<Float>(wall.start.x, wall.start.z)
        let p4 = SIMD2<Float>(wall.end.x, wall.end.z)

        return lineSegmentsIntersect(p1, p2, p3, p4)
    }

    private func lineSegmentsIntersect(
        _ p1: SIMD2<Float>,
        _ p2: SIMD2<Float>,
        _ p3: SIMD2<Float>,
        _ p4: SIMD2<Float>
    ) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        return false
    }

    private func direction(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>) -> Float {
        return (p3.x - p1.x) * (p2.y - p1.y) - (p2.x - p1.x) * (p3.y - p1.y)
    }

    // MARK: - Supporting Types

    struct Wall {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let thickness: Float
    }

    struct CoveragePoint {
        let position: SIMD3<Float>
        let rssi: Int
    }
}
