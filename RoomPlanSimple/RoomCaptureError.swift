/*
See LICENSE folder for this sample's licensing information.

Abstract:
Error types for room capture operations (Issue #16).
*/

import Foundation

// MARK: - Room Capture Error Types

enum RoomCaptureError: LocalizedError {
    case noScanData
    case exportFailed(underlying: Error)
    case sessionFailed(underlying: Error)
    case processingFailed(underlying: Error)
    case deviceNotSupported

    var errorDescription: String? {
        switch self {
        case .noScanData:
            return L10n.Scan.Error.noData.localized
        case .exportFailed(let error):
            return L10n.Scan.Error.exportFailed.localized + ": " + error.localizedDescription
        case .sessionFailed(let error):
            return L10n.Scan.Error.sessionFailed.localized + ": " + error.localizedDescription
        case .processingFailed(let error):
            return L10n.Scan.failed.localized + ": " + error.localizedDescription
        case .deviceNotSupported:
            return L10n.Scan.Error.deviceNotSupported.localized
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noScanData:
            return L10n.Scan.Error.completeScanFirst.localized
        case .exportFailed:
            return L10n.Scan.Error.tryDifferentFormat.localized
        case .sessionFailed:
            return L10n.Scan.Error.adequateLighting.localized
        case .processingFailed:
            return L10n.Scan.Error.slowerMovements.localized
        case .deviceNotSupported:
            return L10n.Scan.Error.requiresLidar.localized
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable {
    // USDZ variants (native RoomPlan export)
    case parametric
    case model
    case mesh
    // Converted formats (via ModelIO)
    case obj
    case stl
    // BIM format (via bimifc-writer Rust library)
    case ifc

    /// Localized display name for the format
    var localizedName: String {
        switch self {
        case .parametric: return L10n.Export.usdzParametric.localized
        case .model: return L10n.Export.usdzTextured.localized
        case .mesh: return L10n.Export.usdzMesh.localized
        case .obj: return L10n.Export.obj.localized
        case .stl: return L10n.Export.stl.localized
        case .ifc: return L10n.Export.ifc.localized
        }
    }

    var exportOption: CapturedRoom.USDExportOptions {
        switch self {
        case .parametric, .obj, .stl, .ifc: return .parametric
        case .model: return .model
        case .mesh: return .mesh
        }
    }

    var fileExtension: String {
        switch self {
        case .parametric, .model, .mesh: return "usdz"
        case .obj: return "obj"
        case .stl: return "stl"
        case .ifc: return "ifc"
        }
    }

    /// Whether this format requires conversion from USDZ
    var requiresConversion: Bool {
        switch self {
        case .parametric, .model, .mesh: return false
        case .obj, .stl: return true
        case .ifc: return false
        }
    }

    /// Whether this format uses the IFC export path (floor plan data → Rust writer)
    var isIfcExport: Bool {
        return self == .ifc
    }

    var description: String {
        switch self {
        case .parametric:
            return L10n.Export.FormatDesc.parametric.localized
        case .model:
            return L10n.Export.FormatDesc.textured.localized
        case .mesh:
            return L10n.Export.FormatDesc.mesh.localized
        case .obj:
            return L10n.Export.FormatDesc.obj.localized
        case .stl:
            return L10n.Export.FormatDesc.stl.localized
        case .ifc:
            return L10n.Export.FormatDesc.ifc.localized
        }
    }
}

import RoomPlan
