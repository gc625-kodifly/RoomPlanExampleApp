/*
See LICENSE folder for this sample's licensing information.

Abstract:
Unified library item representing either a RoomPlan scan or a saved point cloud capture.
*/

import Foundation

enum LibraryCaptureItem {
    case room(SavedRoom)
    case pointCloud(SavedPointCloud)

    var id: UUID {
        switch self {
        case .room(let room): return room.id
        case .pointCloud(let pointCloud): return pointCloud.id
        }
    }

    var date: Date {
        switch self {
        case .room(let room): return room.date
        case .pointCloud(let pointCloud): return pointCloud.date
        }
    }

    var name: String {
        switch self {
        case .room(let room): return room.name
        case .pointCloud(let pointCloud): return pointCloud.name
        }
    }
}
