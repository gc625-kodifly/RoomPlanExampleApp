/*
See LICENSE folder for this sample's licensing information.

Abstract:
Manages export functionality for captured room data (Issue #14 refactoring).
*/

import UIKit
import RoomPlan
import ModelIO
import SceneKit
import ARKit

/// Handles room export operations and share sheet presentation
@MainActor
final class RoomExportManager {

    // MARK: - Properties

    private weak var presentingViewController: UIViewController?
    private weak var sourceView: UIView?

    // MARK: - Initialization

    init(presentingViewController: UIViewController, sourceView: UIView?) {
        self.presentingViewController = presentingViewController
        self.sourceView = sourceView
    }

    // MARK: - Export Methods

    /// Shows export options action sheet
    func showExportOptions(
        statistics: ScanStatistics,
        onFloorPlan: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onPointCloud: (() -> Void)? = nil,
        onExport: @escaping (ExportFormat) -> Void
    ) {
        let alert = UIAlertController(
            title: AppConstants.Strings.exportTitle,
            message: "\(L10n.Export.detectedSummary.localized(statistics.summary))\n\n\(AppConstants.Strings.exportMessage)",
            preferredStyle: .actionSheet
        )

        // Save Room option
        alert.addAction(UIAlertAction(title: L10n.Export.saveRoom.localized, style: .default) { _ in
            onSave()
        })

        // View Floor Plan option
        alert.addAction(UIAlertAction(title: L10n.Export.viewFloorPlan.localized, style: .default) { _ in
            onFloorPlan()
        })

        if let onPointCloud {
            alert.addAction(UIAlertAction(title: "PCD Point Cloud", style: .default) { _ in
                onPointCloud()
            })
        }

        for format in ExportFormat.allCases {
            alert.addAction(UIAlertAction(title: format.localizedName, style: .default) { _ in
                onExport(format)
            })
        }

        alert.addAction(UIAlertAction(title: AppConstants.Strings.cancelButton, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView?.bounds ?? .zero
        }

        presentingViewController?.present(alert, animated: true)
    }

    /// Performs export of captured room to file
    func performExport(
        results: CapturedRoom,
        format: ExportFormat,
        onError: @escaping (RoomCaptureError) -> Void
    ) {
        let fileName = "\(AppConstants.Export.filePrefix)_\(formatDate(Date())).\(format.fileExtension)"
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // Clean up any existing file
        try? FileManager.default.removeItem(at: destinationURL)

        do {
            if format.isIfcExport {
                // Generate IFC via Rust bimifc-writer from CapturedRoom data
                let floorPlanData = FloorPlanData.from(results)
                try IfcExportBridge.writeIFC(from: floorPlanData, to: destinationURL)
            } else if format.requiresConversion {
                // First export to USDZ, then convert
                let tempUSDZ = FileManager.default.temporaryDirectory.appendingPathComponent("temp_export.usdz")
                try? FileManager.default.removeItem(at: tempUSDZ)
                try results.export(to: tempUSDZ, exportOptions: format.exportOption)

                // Convert using ModelIO
                try convertToFormat(from: tempUSDZ, to: destinationURL, format: format)

                // Clean up temp file
                try? FileManager.default.removeItem(at: tempUSDZ)
            } else {
                try results.export(to: destinationURL, exportOptions: format.exportOption)
            }
            presentShareSheet(for: destinationURL, onError: onError)
        } catch {
            onError(RoomCaptureError.exportFailed(underlying: error))
        }
    }

    /// Exports reconstructed ARKit mesh vertices as a voxel-filtered PCD file.
    func performPointCloudExport(
        anchors: [ARMeshAnchor],
        voxelSize: Float = 0.02,
        onError: @escaping (RoomCaptureError) -> Void
    ) {
        let fileName = "\(AppConstants.Export.filePrefix)_\(formatDate(Date())).pcd"
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destinationURL)

        do {
            _ = try PointCloudExporter.export(
                anchors: anchors,
                to: destinationURL,
                voxelSize: voxelSize
            )
            presentShareSheet(for: destinationURL, onError: onError)
        } catch {
            onError(RoomCaptureError.exportFailed(underlying: error))
        }
    }

    /// Convert USDZ to OBJ/STL using ModelIO
    private func convertToFormat(from sourceURL: URL, to destinationURL: URL, format: ExportFormat) throws {
        // Load USDZ with ModelIO
        let asset = MDLAsset(url: sourceURL)

        // Check if format is supported
        guard MDLAsset.canExportFileExtension(format.fileExtension) else {
            throw NSError(domain: "RoomExportManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Format \(format.fileExtension) not supported"])
        }

        // Export to target format
        try asset.export(to: destinationURL)
    }

    // MARK: - Private Methods

    private func presentShareSheet(for url: URL, onError: @escaping (RoomCaptureError) -> Void) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.modalPresentationStyle = .popover

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView?.bounds ?? .zero
        }

        activityVC.completionWithItemsHandler = { _, _, _, error in
            if let error = error {
                onError(RoomCaptureError.exportFailed(underlying: error))
            }
        }

        presentingViewController?.present(activityVC, animated: true)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = AppConstants.Export.dateFormat
        return formatter.string(from: date)
    }
}
