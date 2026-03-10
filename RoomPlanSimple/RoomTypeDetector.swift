/*
See LICENSE folder for this sample's licensing information.

Abstract:
Intelligent room type detection based on furniture and object analysis.
Adapted from TangoEcho/RoomPlanExampleApp fork.
*/

import Foundation
import RoomPlan

/// Detects the type of room based on analyzed furniture and objects
final class RoomTypeDetector {

    // MARK: - Room Type

    enum RoomType: String, Codable, CaseIterable {
        case kitchen = "Kitchen"
        case bedroom = "Bedroom"
        case bathroom = "Bathroom"
        case livingRoom = "Living Room"
        case diningRoom = "Dining Room"
        case office = "Office"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .kitchen: return "🍳"
            case .bedroom: return "🛏️"
            case .bathroom: return "🚿"
            case .livingRoom: return "🛋️"
            case .diningRoom: return "🍽️"
            case .office: return "💼"
            case .unknown: return "📦"
            }
        }

        var localizedKey: String {
            switch self {
            case .kitchen: return "roomType.kitchen"
            case .bedroom: return "roomType.bedroom"
            case .bathroom: return "roomType.bathroom"
            case .livingRoom: return "roomType.livingRoom"
            case .diningRoom: return "roomType.diningRoom"
            case .office: return "roomType.office"
            case .unknown: return "roomType.unknown"
            }
        }
    }

    // MARK: - Detection Result

    struct DetectionResult {
        let roomType: RoomType
        let confidence: Float  // 0.0 - 1.0
        let matchingObjects: [String]  // Objects that contributed to classification

        var isHighConfidence: Bool {
            confidence >= 0.7
        }

        var isMediumConfidence: Bool {
            confidence >= 0.4 && confidence < 0.7
        }
    }

    // MARK: - Object Scoring

    /// Points assigned to room types based on detected objects
    private struct ObjectScore {
        static let scores: [CapturedRoom.Object.Category: [RoomType: Int]] = [
            // Bedroom indicators
            .bed: [.bedroom: 5],

            // Bathroom indicators
            .toilet: [.bathroom: 5],
            .bathtub: [.bathroom: 5],
            .sink: [.bathroom: 2, .kitchen: 1],  // Sink can be in both

            // Kitchen indicators
            .refrigerator: [.kitchen: 4],
            .stove: [.kitchen: 4],
            .oven: [.kitchen: 4],
            .dishwasher: [.kitchen: 3],

            // Living room indicators
            .sofa: [.livingRoom: 4],
            .television: [.livingRoom: 3],
            .fireplace: [.livingRoom: 3],

            // Dining room indicators
            .table: [.diningRoom: 3, .office: 1, .kitchen: 1],

            // Office indicators
            .storage: [.office: 2, .bedroom: 1],

            // Multi-purpose
            .chair: [.diningRoom: 1, .office: 1],
            .washerDryer: [.bathroom: 2, .kitchen: 1]
        ]

        static func pointsFor(category: CapturedRoom.Object.Category, roomType: RoomType) -> Int {
            scores[category]?[roomType] ?? 0
        }
    }

    // MARK: - Public API

    /// Detect room type from captured room data
    static func detectRoomType(from room: CapturedRoom) -> DetectionResult {
        let objects = room.objects

        // If no objects detected, return unknown
        guard !objects.isEmpty else {
            return DetectionResult(
                roomType: .unknown,
                confidence: 0.0,
                matchingObjects: []
            )
        }

        // Calculate scores for each room type
        var roomScores: [RoomType: Int] = [:]
        var matchingObjectsByType: [RoomType: [String]] = [:]

        for object in objects {
            for roomType in RoomType.allCases {
                let points = ObjectScore.pointsFor(category: object.category, roomType: roomType)
                if points > 0 {
                    roomScores[roomType, default: 0] += points
                    matchingObjectsByType[roomType, default: []].append(categoryName(object.category))
                }
            }
        }

        // Remove unknown from scoring
        roomScores.removeValue(forKey: .unknown)

        // Find highest scoring room type
        guard let (detectedType, maxScore) = roomScores.max(by: { $0.value < $1.value }) else {
            return DetectionResult(
                roomType: .unknown,
                confidence: 0.0,
                matchingObjects: []
            )
        }

        // Calculate confidence based on:
        // 1. Score strength (how many relevant objects)
        // 2. RoomPlan confidence of detected objects
        // 3. Ratio of matching objects to total objects

        let matchingObjects = matchingObjectsByType[detectedType] ?? []
        let matchRatio = Float(matchingObjects.count) / Float(objects.count)

        // Average RoomPlan confidence of all objects
        let avgObjectConfidence = averageObjectConfidence(objects)

        // Score-based confidence (normalize by max possible score ~20)
        let scoreConfidence = min(Float(maxScore) / 15.0, 1.0)

        // Combined confidence (weighted average)
        let confidence = (scoreConfidence * 0.5) +
                        (avgObjectConfidence * 0.3) +
                        (matchRatio * 0.2)

        return DetectionResult(
            roomType: detectedType,
            confidence: min(confidence, 1.0),
            matchingObjects: matchingObjects
        )
    }

    // MARK: - Helper Methods

    private static func averageObjectConfidence(_ objects: [CapturedRoom.Object]) -> Float {
        guard !objects.isEmpty else { return 0.0 }

        let totalConfidence = objects.reduce(0.0) { sum, object in
            sum + confidenceValue(object.confidence)
        }

        return totalConfidence / Float(objects.count)
    }

    private static func confidenceValue(_ confidence: CapturedRoom.Confidence) -> Float {
        switch confidence {
        case .high: return 0.9
        case .medium: return 0.6
        case .low: return 0.3
        @unknown default: return 0.5
        }
    }

    private static func categoryName(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .bed: return L10n.ObjectType.bed.localized
        case .toilet: return L10n.ObjectType.toilet.localized
        case .bathtub: return L10n.ObjectType.bathtub.localized
        case .sink: return L10n.ObjectType.sink.localized
        case .refrigerator: return L10n.ObjectType.refrigerator.localized
        case .stove: return L10n.ObjectType.stove.localized
        case .oven: return L10n.ObjectType.oven.localized
        case .dishwasher: return L10n.ObjectType.dishwasher.localized
        case .sofa: return L10n.ObjectType.sofa.localized
        case .television: return L10n.ObjectType.television.localized
        case .fireplace: return L10n.ObjectType.fireplace.localized
        case .table: return L10n.ObjectType.table.localized
        case .chair: return L10n.ObjectType.chair.localized
        case .storage: return L10n.ObjectType.storage.localized
        case .washerDryer: return L10n.ObjectType.washerDryer.localized
        case .stairs: return L10n.ObjectType.stairs.localized
        @unknown default: return L10n.ObjectType.unknownObject.localized
        }
    }
}

// MARK: - Localization Keys

extension RoomTypeDetector.RoomType {
    var localized: String {
        NSLocalizedString(localizedKey, tableName: "Localizable", bundle: Bundle.main, value: rawValue, comment: "")
    }
}
